import 'package:latlong2/latlong.dart';
import '../core/constants/app_constants.dart';
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
  final List<LocationPoint> currentBatch;
  final double currentBatchDistance;
  final LatLng? lastKnownLocation;
  const LocationSyncResult({
    required this.finalLocations,
    required this.finalLocationsDistance,
    required this.currentBatch,
    required this.currentBatchDistance,
    required this.lastKnownLocation,
  });
}

/// Everything to do with turning tracking-isolate + Hive data into what the
/// UI shows and what Firestore stores. One implementation shared by
/// HomeBloc (foreground UI), the FCM watchdog, and any future boot/update-
/// triggered recovery — so none of these call sites can drift apart.
class LocationSyncService {
  /// The single entry point for "give me the latest tracking data, syncing
  /// a pending batch to Firestore first if one's due." Always returns the
  /// freshest finalLocations/currentBatch available for display, whether or
  /// not an actual sync happened — [forceSync] or a pending sample count
  /// at/past [AppConstants.locationBatchSize] triggers the OSRM+Firestore
  /// work; otherwise this is just a cheap read. Returns null only if the
  /// cross-isolate lock couldn't be acquired at all.
  ///
  /// [LocationsBoxLock.isHeldByThisIsolate] is the single source of truth
  /// for whether the caller already owns locationsBox/settingsBox — no
  /// separate "am I backgrounded" flag to keep in sync with reality:
  /// - Already held (HomeBloc's own foreground-session hold): reuses the
  ///   already-open box, leaves it exactly as found.
  /// - Not held (HomeBloc backgrounded, or a fresh FCM/boot isolate): tries
  ///   to acquire it fresh (bounded timeout); backs off with null if that
  ///   fails (another isolate is using these boxes right now). On success,
  ///   opens the box just for this call and closes it + releases the lock
  ///   again afterward.
  static Future<LocationSyncResult?> processBatchAndEmitLatestLocationData({
    required String userId,
    required String trackingId,
    bool forceSync = false,
  }) async {
    final alreadyHeld = LocationsBoxLock.isHeldByThisIsolate;
    if (!alreadyHeld) {
      final acquired = await LocationsBoxLock.tryAcquire();
      if (!acquired) {
        print('[LocationSync] Could not acquire locations_box lock — '
            'another isolate is using it right now, skipping.');
        return null;
      }
      await LocalStorageService.openLocationsBoxForSync();
    }

    try {
      final finalLocations = LocalStorageService.getFinalLocations();
      final finalLocationsDistance =
          LocalStorageService.getFinalLocationsDistance();
      final snap = await LocationTrackingService.requestSnapshot();
      final pendingSampleCount = snap?.pendingSampleCount ?? 0;

      final shouldSync =
          forceSync || pendingSampleCount >= AppConstants.locationBatchSize;
      if (shouldSync) {
        final synced = await _syncPendingBatch(
          userId: userId,
          trackingId: trackingId,
          snap: snap,
          finalLocations: finalLocations,
          finalLocationsDistance: finalLocationsDistance,
        );
        if (synced != null) {
          final (syncedFinalLocations, syncedFinalDistance) = synced;
          final freshSnap = await LocationTrackingService.requestSnapshot();
          final freshBatch = freshSnap?.currentBatch ?? <LocationPoint>[];
          return LocationSyncResult(
            finalLocations: syncedFinalLocations,
            finalLocationsDistance: syncedFinalDistance,
            currentBatch: freshBatch,
            currentBatchDistance:
                batchDistanceKm(freshBatch, syncedFinalLocations),
            lastKnownLocation: resolveLastKnownLocation(
              currentBatch: freshBatch,
              lastConfirmedPoint: freshSnap?.lastConfirmedPoint,
              finalLocations: syncedFinalLocations,
            ),
          );
        }
        // Sync was due but failed (or turned out to be nothing to sync) —
        // fall through and return the as-read values below instead.
      }

      final currentBatch = snap?.currentBatch ?? <LocationPoint>[];
      return LocationSyncResult(
        finalLocations: finalLocations,
        finalLocationsDistance: finalLocationsDistance,
        currentBatch: currentBatch,
        currentBatchDistance: batchDistanceKm(currentBatch, finalLocations),
        lastKnownLocation: resolveLastKnownLocation(
          currentBatch: currentBatch,
          lastConfirmedPoint: snap?.lastConfirmedPoint,
          finalLocations: finalLocations,
        ),
      );
    } finally {
      if (!alreadyHeld) {
        await LocalStorageService.closeLocationsBoxForBackground();
      }
    }
  }

  /// Snaps the isolate's pending batch via OSRM, persists the merged array
  /// to Firestore+Hive, and confirms success back to the isolate so it can
  /// trim currentBatch. Wrapped in its own try/catch (rather than letting
  /// [processBatchAndEmitLatestLocationData] see the exception) so a
  /// persist failure — e.g. Firestore's 1 MiB size limit, which
  /// DataManager.persistLocations already flags internally — degrades to
  /// "nothing synced this round" instead of losing the as-read fallback
  /// data the caller still has.
  static Future<(List<LocationPoint>, double)?> _syncPendingBatch({
    required String userId,
    required String trackingId,
    required TrackingSnapshot? snap,
    required List<LocationPoint> finalLocations,
    required double finalLocationsDistance,
  }) async {
    try {
      final batchToProcess = snap?.currentBatch ?? <LocationPoint>[];
      if (batchToProcess.isEmpty && finalLocations.isEmpty) return null;

      double osrmDistance = 0.0;
      List<LocationPoint> snappedBatch = [];
      if (batchToProcess.isNotEmpty) {
        final snapResult =
            await _snapBatch(batch: batchToProcess, finalLocations: finalLocations);
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
          allLocations.last.copyWith(
              durationSeconds: snap.lastConfirmedPoint!.durationSeconds),
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
          '(+${snappedBatch.length} new, distance: ${newFinalDistance.toStringAsFixed(3)} km)');
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

      return (allLocations, newFinalDistance);
    } catch (e) {
      print('[LocationSync] _syncPendingBatch error: $e');
      return null;
    }
  }

  /// For the FCM watchdog handler (and any future boot/update-triggered
  /// recovery) ONLY — a fresh, short-lived engine that never ran the app's
  /// normal main(), so it always needs its own initialize()+start() before
  /// [processBatchAndEmitLatestLocationData] can do anything (unlike
  /// HomeBloc, whose service is already known to be running).
  static Future<void> initializeAndStart(String userId, String date) async {
    await LocationTrackingService.initialize();
    await LocationTrackingService.start(userId, date);
  }

  /// Picks the freshest known position, in strict recency order:
  /// currentBatch.last (newest raw sample the isolate has) → lastConfirmedPoint
  /// (the isolate's anchor — its durationSeconds can be fresher than
  /// finalLocations.last even with an unchanged position, from a pure
  /// stationary tick) → finalLocations.last (last Firestore-synced point).
  /// Shared by every caller that maps a snapshot to UI state — HomeBloc's
  /// per-sample live update and this service's own sync paths — so they
  /// can't drift on which point they trust first.
  static LatLng? resolveLastKnownLocation({
    required List<LocationPoint> currentBatch,
    required LocationPoint? lastConfirmedPoint,
    required List<LocationPoint> finalLocations,
  }) {
    if (currentBatch.isNotEmpty) return currentBatch.last.position;
    if (lastConfirmedPoint != null) return lastConfirmedPoint.position;
    if (finalLocations.isNotEmpty) return finalLocations.last.position;
    return null;
  }

  /// Live haversine estimate for the unsynced [batch], anchored to the last
  /// committed point in [finalLocations].
  static double batchDistanceKm(
      List<LocationPoint> batch, List<LocationPoint> finalLocations) {
    if (batch.isEmpty) return 0.0;
    final points = [if (finalLocations.isNotEmpty) finalLocations.last, ...batch];
    double sum = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      sum += AppUtils.haversineMeters(points[i].position, points[i + 1].position) /
          1000.0;
    }
    return sum;
  }

  /// Snaps [batch] to roads via OSRM, anchored against the last already-
  /// synced point in [finalLocations] (needed both to de-dupe against
  /// already-synced points and to correctly chain the distance calc from
  /// where the last sync left off).
  ///
  /// The batch is replaced by OSRM's simplified (Douglas-Peucker reduced)
  /// road geometry rather than just repositioning each raw sample 1:1 — so
  /// the stored path actually hugs the road when the UI connects the dots,
  /// not just straight lines between sparse samples. Intermediate points
  /// get an interpolated timestamp (proportional to cumulative distance
  /// along the path, i.e. assuming constant speed across the batch) since
  /// they're not real GPS fixes — only for display, nothing reads them.
  /// The first and last point keep their REAL timestamp, and the last also
  /// keeps its real durationSeconds, since track_tab.dart's "last update"
  /// display and the Cloud Functions "stationary" notification both depend
  /// on the last point's timestamp/duration being accurate.
  static Future<(List<LocationPoint>, double)?> _snapBatch({
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

    final geometry = await OsrmService.matchSimplifiedGeometry(
      valid.map((p) => p.position).toList(),
    );

    final snapped = (geometry != null && geometry.isNotEmpty)
        ? _interpolateFromGeometry(geometry, valid)
        // OSRM failed or the batch was too small to match — keep the raw
        // points as-is rather than losing them.
        : valid.map((p) => p.copyWith(isSnapped: false)).toList();

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

  /// Builds the final point list from OSRM's simplified road [geometry],
  /// assigning each intermediate point a timestamp interpolated between
  /// [valid]'s real first/last timestamps, proportional to cumulative
  /// distance along the path — see [_snapBatch] doc for why only the first
  /// and last points keep their real timestamp/duration.
  static List<LocationPoint> _interpolateFromGeometry(
    List<LatLng> geometry,
    List<LocationPoint> valid,
  ) {
    if (geometry.length == 1) {
      return [valid.last.copyWith(position: geometry.first, isSnapped: true)];
    }

    final cumulative = <double>[0.0];
    for (int i = 1; i < geometry.length; i++) {
      cumulative.add(cumulative[i - 1] +
          AppUtils.haversineMeters(geometry[i - 1], geometry[i]));
    }
    final totalDistance = cumulative.last;

    final firstTs = valid.first.timestamp;
    final lastTs = valid.last.timestamp;
    final totalMicros = lastTs.difference(firstTs).inMicroseconds;

    final result = <LocationPoint>[];
    for (int i = 0; i < geometry.length; i++) {
      if (i == 0) {
        result.add(LocationPoint(
          position: geometry[i],
          timestamp: firstTs,
          isSnapped: true,
        ));
        continue;
      }
      if (i == geometry.length - 1) {
        result.add(LocationPoint(
          position: geometry[i],
          timestamp: lastTs,
          isSnapped: true,
          durationSeconds: valid.last.durationSeconds,
        ));
        continue;
      }
      final fraction = totalDistance > 0 ? cumulative[i] / totalDistance : 0.0;
      final ts =
          firstTs.add(Duration(microseconds: (totalMicros * fraction).round()));
      result.add(LocationPoint(position: geometry[i], timestamp: ts, isSnapped: true));
    }
    return result;
  }
}
