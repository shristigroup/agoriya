import 'dart:io';
import '../core/utils/app_utils.dart';
import '../data/data_manager.dart';
import '../data/local/local_storage_service.dart';
import '../data/local/locations_box_lock.dart';
import '../data/models/location_model.dart';
import 'location_tracking_service.dart';
import 'osrm_service.dart';

class LocationSyncResult {
  final List<LocationPoint> finalLocations;
  final double finalLocationsDistance;
  const LocationSyncResult({
    required this.finalLocations,
    required this.finalLocationsDistance,
  });
}

/// The "sync a pending batch to Firestore" job — shared by HomeBloc (which
/// already has locationsBox/settingsBox open for its whole lifetime) and
/// the FCM watchdog handler (a separate, short-lived isolate that opens
/// them fresh, guarded by [LocationsBoxLock]). One implementation, so the
/// two call sites can't drift apart.
class LocationSyncService {
  /// Core algorithm: request the tracking isolate's pending batch, snap it
  /// via OSRM, build the full locations array, persist to Firestore+Hive,
  /// and confirm back to the isolate. Callers must ensure safe access to
  /// locationsBox/settingsBox before calling this — see
  /// [ensureRunningAndSync] for the FCM-handler path; HomeBloc's own box
  /// access is already safe since it's the box's session-long owner.
  static Future<LocationSyncResult?> syncCore({
    required String userId,
    required String trackingId,
    required List<LocationPoint> finalLocations,
    required double finalLocationsDistance,
  }) async {
    try {
      final snap = await LocationTrackingService.requestSnapshot();
      final batchToProcess = snap?.currentBatch ?? <LocationPoint>[];
      if (batchToProcess.isEmpty && finalLocations.isEmpty) return null;

      double osrmDistance = 0.0;
      List<LocationPoint> snappedBatch = [];
      if (batchToProcess.isNotEmpty) {
        final snapResult = await snapBatch(
          batch: batchToProcess,
          finalLocations: finalLocations,
        );
        if (snapResult != null) {
          (snappedBatch, osrmDistance) = snapResult;
        }
      }

      final newFinalDistance = finalLocationsDistance + osrmDistance;
      var allLocations = [...finalLocations, ...snappedBatch];

      // Pure stationary flush (currentBatch was empty): fold in the
      // isolate's anchor durationSeconds, since that's the only thing that
      // changed — nothing new was appended to sync.
      if (snappedBatch.isEmpty &&
          snap?.lastConfirmedPoint?.durationSeconds != null &&
          allLocations.isNotEmpty &&
          allLocations.last.durationSeconds !=
              snap!.lastConfirmedPoint!.durationSeconds) {
        allLocations = [
          ...allLocations.take(allLocations.length - 1),
          allLocations.last
              .copyWith(durationSeconds: snap.lastConfirmedPoint!.durationSeconds),
        ];
      }

      if (allLocations.isEmpty) return null;

      allLocations = [
        ...allLocations.take(allLocations.length - 1),
        allLocations.last.copyWith(
          cumulativeDistanceKm: newFinalDistance,
          batchDistanceKm: osrmDistance,
        ),
      ];

      print(
          '[LocationSync] Syncing ${allLocations.length} total points to Firestore '
          '(+${snappedBatch.length} new, distance: ${newFinalDistance.toStringAsFixed(3)} km)'
          ' | last.ts=${allLocations.last.timestamp.toIso8601String()}'
          ' | last.durationSeconds=${allLocations.last.durationSeconds}');
      await DataManager.persistLocations(
        userId: userId,
        trackingId: trackingId,
        allLocations: allLocations,
        distanceKm: newFinalDistance,
      );
      print('[LocationSync] Synced successfully to Firestore.');

      // Confirm success so the tracking isolate (sole owner of the cursor
      // box) can trim currentBatch up to this point and adopt it as the
      // new anchor — anything it appended concurrently is left intact.
      LocationTrackingService.confirmBatchSynced(allLocations.last);

      return LocationSyncResult(
        finalLocations: allLocations,
        finalLocationsDistance: newFinalDistance,
      );
    } catch (e) {
      print('[LocationSync] syncCore error: $e');
      return null;
    }
  }

  /// For the FCM watchdog handler ONLY.
  ///
  /// Only two things run in parallel here: {initialize the background-
  /// service plugin, then start/update-params the tracking isolate} as one
  /// chain, alongside {acquire the cross-isolate lock, then read
  /// finalLocations} as the other. Those two chains genuinely don't depend
  /// on each other, and both can take real time (service boot; lock
  /// contention), so it's worth overlapping them given the tight
  /// background-execution budget. initialize() itself isn't skippable based
  /// on isRunning() — it registers this isolate's own platform-channel
  /// bindings for invoke()/start(), which is per-engine-instance, not a
  /// global "is a service running" flag; the FCM handler is always a fresh
  /// engine, so it always needs its own initialize() regardless of whether
  /// the native service happens to already be alive.
  ///
  /// The actual sync ([syncCore]: requestSnapshot → OSRM → Firestore)
  /// canNOT start until the service is confirmed running — requestSnapshot
  /// asks the tracking isolate for the points sitting in currentBatch, and
  /// there's nothing to ask for until that isolate has booted and opened
  /// its cursor box. So syncCore is unavoidably sequential, gated on
  /// `serviceFuture` below — there is no way to parallelize the sync itself
  /// with the service restart, only these two setup chains.
  ///
  /// Returns null if the lock couldn't be acquired in time (the main app is
  /// most likely alive and already syncing on its own) or if there was
  /// nothing to sync.
  static Future<LocationSyncResult?> ensureRunningAndSync({
    required String userId,
    required String date,
    required String trackingId,
  }) async {
    // (_, locked) — both futures start running the instant they're created
    // above; .wait just makes "these two run concurrently, wait for both"
    // visually explicit instead of relying on Dart's eager-async-start
    // semantics being obvious from two bare `await` lines.
    final (_, locked) = await (
      _initializeAndStart(userId, date),
      _acquireLockAndReadFinalLocations(),
    ).wait;
    if (locked == null) {
      print('[LocationSync] Could not acquire locations_box lock — main '
          'app likely alive, skipping FCM-driven sync.');
      return null;
    }

    final (lockHandle, finalLocations, finalDistance) = locked;
    try {
      return await syncCore(
        userId: userId,
        trackingId: trackingId,
        finalLocations: finalLocations,
        finalLocationsDistance: finalDistance,
      );
    } finally {
      await lockHandle.unlock();
      await lockHandle.close();
    }
  }

  /// initialize() must complete before start() can work (configure()
  /// registers this engine's own invoke()/on() bindings) — so these two are
  /// sequential relative to each other, but the whole chain runs in
  /// parallel with the lock+read chain in [ensureRunningAndSync].
  static Future<void> _initializeAndStart(String userId, String date) async {
    await LocationTrackingService.initialize();
    await LocationTrackingService.start(userId, date);
  }

  static Future<(RandomAccessFile, List<LocationPoint>, double)?>
      _acquireLockAndReadFinalLocations() async {
    final raf = await LocationsBoxLock.tryAcquire();
    if (raf == null) return null;
    await LocalStorageService.openLocationsBoxForSync();
    final finalLocations = LocalStorageService.getFinalLocations();
    final finalDistance = LocalStorageService.getFinalLocationsDistance();
    return (raf, finalLocations, finalDistance);
  }

  /// Snaps [batch] to roads via OSRM, anchored against the last already-
  /// synced point in [finalLocations] (needed both to de-dupe against
  /// already-synced points and to correctly chain the distance calc from
  /// where the last sync left off). Public — also used directly by
  /// HomeBloc's punch-out flow, which has its own final-sync shape.
  static Future<(List<LocationPoint>, double)?> snapBatch({
    required List<LocationPoint> batch,
    required List<LocationPoint> finalLocations,
  }) async {
    if (batch.isEmpty) return null;

    final sorted = List<LocationPoint>.from(batch)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final lastSyncedTs =
        finalLocations.isNotEmpty ? finalLocations.last.timestamp : null;
    final valid = lastSyncedTs != null
        ? sorted.where((p) => p.timestamp.isAfter(lastSyncedTs)).toList()
        : sorted;

    if (valid.isEmpty) return null;

    final tracepoints = await OsrmService.snapTracepoints(
      valid.map((p) => p.position).toList(),
    );

    final snapped = <LocationPoint>[];
    for (int i = 0; i < valid.length; i++) {
      final pos = tracepoints[i] ?? valid[i].position;
      snapped.add(LocationPoint(
        position: pos,
        timestamp: valid[i].timestamp,
        isSnapped: true,
        durationSeconds: valid[i].durationSeconds,
      ));
    }

    double distance = 0.0;
    final prevPoint = finalLocations.isNotEmpty ? finalLocations.last : null;
    final distInput = [if (prevPoint != null) prevPoint, ...snapped];
    for (int i = 0; i < distInput.length - 1; i++) {
      distance += AppUtils.haversineMeters(
              distInput[i].position, distInput[i + 1].position) /
          1000.0;
    }

    return (snapped, distance);
  }
}
