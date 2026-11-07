import 'package:latlong2/latlong.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/app_utils.dart';
import '../data/data_manager.dart';
import '../data/local/local_storage_service.dart';
import '../data/local/locations_box_lock.dart';
import '../data/models/location_model.dart';
import 'location_tracking_service.dart';
import 'osrm_service.dart';
import 'route_builder.dart';

class LocationSyncResult {
  final List<LocationPoint> finalLocations;
  final double finalLocationsDistance;
  final List<LocationPoint> currentBatch;
  final double currentBatchDistance;
  final LatLng? lastKnownLocation;

  /// The effective "last active" time — timestamp + durationSeconds of
  /// whichever point [lastKnownLocation] was resolved from (currentBatch.last,
  /// the isolate's lastConfirmedPoint anchor, or finalLocations.last, in that
  /// priority order — see [LocationSyncService.resolveLastKnownLocationWithTimestamp]).
  /// Deliberately derived from the SAME resolved point as the position,
  /// rather than a separate DateTime.now()-at-processing-time or a
  /// finalLocations-only read — those alone go stale during a stationary
  /// run after a sync trims currentBatch to empty, since duration keeps
  /// climbing on the anchor, which finalLocations doesn't see until the
  /// next sync commits it.
  final DateTime? lastActiveAt;

  /// True if this call is the one that discovered the Firestore 1 MiB
  /// document-size limit was newly hit — computed here (where the lock is
  /// safely held) rather than by the caller separately touching
  /// LocalStorageService.isLocationSizeLimitHit(), which isn't safe to call
  /// from HomeBloc directly: by the time control returns to the caller, this
  /// function may have already closed locationsBox/settingsBox again (the
  /// backgrounded case), so a second, independent read from outside would
  /// throw "Box has already been closed".
  final bool sizeLimitJustHit;

  const LocationSyncResult({
    required this.finalLocations,
    required this.finalLocationsDistance,
    required this.currentBatch,
    required this.currentBatchDistance,
    required this.lastKnownLocation,
    required this.lastActiveAt,
    required this.sizeLimitJustHit,
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
      // Captured up front, inside the lock-held region, so the "did this
      // call newly trigger it" comparison below is always a safe read —
      // never touched by the caller directly (see LocationSyncResult.
      // sizeLimitJustHit).
      final wasLimitKnown = LocalStorageService.isLocationSizeLimitHit();

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
          holdBackTail: !forceSync,
        );
        if (synced != null) {
          final (syncedFinalLocations, syncedFinalDistance) = synced;
          final freshSnap = await LocationTrackingService.requestSnapshot();
          final freshBatch = freshSnap?.currentBatch ?? <LocationPoint>[];
          final freshPoint = resolveLastKnownLocationWithTimestamp(
            currentBatch: freshBatch,
            lastConfirmedPoint: freshSnap?.lastConfirmedPoint,
            finalLocations: syncedFinalLocations,
          );
          return LocationSyncResult(
            finalLocations: syncedFinalLocations,
            finalLocationsDistance: syncedFinalDistance,
            currentBatch: freshBatch,
            currentBatchDistance:
                batchDistanceKm(freshBatch, syncedFinalLocations),
            lastKnownLocation: freshPoint?.position,
            lastActiveAt: freshPoint?.timestamp.add(
                Duration(seconds: freshPoint.durationSeconds ?? 0)),
            sizeLimitJustHit: !wasLimitKnown &&
                LocalStorageService.isLocationSizeLimitHit(),
          );
        }
        // Sync was due but failed (or turned out to be nothing to sync) —
        // fall through and return the as-read values below instead.
      }

      final currentBatch = snap?.currentBatch ?? <LocationPoint>[];
      final point = resolveLastKnownLocationWithTimestamp(
        currentBatch: currentBatch,
        lastConfirmedPoint: snap?.lastConfirmedPoint,
        finalLocations: finalLocations,
      );
      return LocationSyncResult(
        finalLocations: finalLocations,
        finalLocationsDistance: finalLocationsDistance,
        currentBatch: currentBatch,
        currentBatchDistance: batchDistanceKm(currentBatch, finalLocations),
        lastKnownLocation: point?.position,
        lastActiveAt: point?.timestamp
            .add(Duration(seconds: point.durationSeconds ?? 0)),
        sizeLimitJustHit:
            !wasLimitKnown && LocalStorageService.isLocationSizeLimitHit(),
      );
    } finally {
      if (!alreadyHeld) {
        await LocalStorageService.closeLocationsBoxForBackground();
      }
    }
  }

  /// Snaps the isolate's pending points via OSRM, persists the merged array
  /// to Firestore+Hive, and confirms success back to the isolate so it can
  /// trim currentBatch. Wrapped in its own try/catch (rather than letting
  /// [processBatchAndEmitLatestLocationData] see the exception) so a
  /// persist failure — e.g. Firestore's 1 MiB size limit, which
  /// DataManager.persistLocations already flags internally — degrades to
  /// "nothing synced this round" instead of losing the as-read fallback
  /// data the caller still has.
  ///
  /// How a sync works:
  ///  * The newest point can't be judged yet — a stray there would become the
  ///    anchor for the next batch — so unless it has already been confirmed by
  ///    a later stationary tick (durationSeconds > 0), it is HELD BACK: left in
  ///    the isolate's currentBatch, and it starts the next sync. Forced
  ///    flushes (punch-out) send everything, as no next sample is coming.
  ///  * OSRM accepts at most [AppConstants.osrmMaxCoordinates] points per
  ///    request, so the points are sent in chunks. Every chunk starts with the
  ///    last point already stored (the "carry"), so each road path begins
  ///    exactly where the previous one ended.
  ///  * One stored point per point sent, always with its REAL timestamp:
  ///    moved onto the road if OSRM matched it, left as the raw fix if not.
  ///    OSRM's road path is attached to the point where it starts (see
  ///    [RouteBuilder]), so drawing follows the roads where OSRM could match
  ///    and falls back to straight lines where it could not — no points are
  ///    ever dropped because OSRM could not use them.
  static Future<(List<LocationPoint>, double)?> _syncPendingBatch({
    required String userId,
    required String trackingId,
    required TrackingSnapshot? snap,
    required List<LocationPoint> finalLocations,
    required double finalLocationsDistance,
    bool holdBackTail = false,
  }) async {
    try {
      final pending = List<LocationPoint>.from(snap?.currentBatch ?? const [])
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final lastStored =
          finalLocations.isNotEmpty ? finalLocations.last.timestamp : null;
      var toSend = lastStored != null
          ? pending.where((p) => p.timestamp.isAfter(lastStored)).toList()
          : pending;
      if (toSend.isEmpty && finalLocations.isEmpty) return null;

      if (holdBackTail &&
          toSend.isNotEmpty &&
          (toSend.last.durationSeconds ?? 0) == 0) {
        print('[LocationSync] Holding back the newest point until the next '
            'sample confirms it');
        toSend = toSend.sublist(0, toSend.length - 1);
      }

      var allLocations = List<LocationPoint>.from(finalLocations);
      var batchKm = 0.0;
      String? failure;
      var sentAny = false;

      var i = 0;
      while (i < toSend.length) {
        final carry = allLocations.isNotEmpty ? allLocations.last : null;
        final room = AppConstants.osrmMaxCoordinates - (carry != null ? 1 : 0);
        final end = (i + room).clamp(0, toSend.length);
        final chunk = toSend.sublist(i, end);
        final inputs = [if (carry != null) carry, ...chunk];

        final trace = inputs.length < 2
            ? OsrmTrace.failed('batch_too_small', inputs.length)
            : await OsrmService.matchTrace(
                inputs.map((p) => p.position).toList(),
                inputs.map((p) => p.timestamp).toList(),
              );
        final built =
            RouteBuilder.build(carry: carry, raw: chunk, trace: trace);

        if (built.carry != null) {
          allLocations[allLocations.length - 1] = built.carry!;
        }
        allLocations.addAll(built.stored);
        batchKm += built.distanceKm;
        if (!trace.ok) failure ??= trace.reason;
        sentAny = true;
        i = end;
      }

      // Pure stationary flush (nothing new to store): fold in the isolate's
      // anchor durationSeconds, since that's the only thing that changed.
      if (!sentAny &&
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

      final newFinalDistance = finalLocationsDistance + batchKm;
      allLocations = [
        ...allLocations.take(allLocations.length - 1),
        allLocations.last.copyWith(
          cumulativeDistanceKm: newFinalDistance,
          batchDistanceKm: batchKm,
          // Why OSRM was or wasn't used, on the batch's last point: the first
          // failure if any request failed, else `ok`.
          snapReason: sentAny ? (failure ?? 'ok') : null,
        ),
      ];

      print(
          '[LocationSync] Syncing ${allLocations.length} total points to Firestore '
          '(+${toSend.length} new, distance: ${newFinalDistance.toStringAsFixed(3)} km'
          '${failure != null ? ', snap: $failure' : ''})');
      await DataManager.persistLocations(
        userId: userId,
        trackingId: trackingId,
        allLocations: allLocations,
        distanceKm: newFinalDistance,
      );
      print('[LocationSync] Synced successfully to Firestore.');

      // Confirm success so the tracking isolate (sole owner of the cursor
      // box) can trim currentBatch up to this point and adopt it as the
      // new anchor — anything it appended concurrently, including the point
      // held back above, is left intact.
      LocationTrackingService.confirmBatchSynced(allLocations.last,
          distanceKm: newFinalDistance);

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
  static Future<void> initializeAndStart(
      String userId, String date, String trackingId) async {
    await LocationTrackingService.initialize();
    await LocationTrackingService.start(userId, date, trackingId);
  }

  /// Whether the last committed sync is older than a full batch interval —
  /// used by the FCM handler to decide whether a heartbeat-triggered wakeup
  /// (which can fire well before pendingSampleCount reaches the normal
  /// batch-size threshold) should still force a sync, so a session that was
  /// actually dead for a while doesn't sit waiting for the next natural
  /// batch boundary to become visible to the manager again. Manages the
  /// lock itself since it's a standalone read, independent of whatever the
  /// caller does next — safe to call even when nothing else holds it.
  static Future<bool> isFinalLocationsStale() async {
    final alreadyHeld = LocationsBoxLock.isHeldByThisIsolate;
    if (!alreadyHeld) {
      final acquired = await LocationsBoxLock.tryAcquire();
      if (!acquired) return false; // can't check right now — don't force
      await LocalStorageService.openLocationsBoxForSync();
    }
    try {
      final finalLocations = LocalStorageService.getFinalLocations();
      if (finalLocations.isEmpty) return false;
      return DateTime.now().difference(finalLocations.last.timestamp) >
          Duration(minutes: AppConstants.locationBatchMinutes);
    } finally {
      if (!alreadyHeld) {
        await LocalStorageService.closeLocationsBoxForBackground();
      }
    }
  }

  /// Picks the freshest known point, in strict recency order:
  /// currentBatch.last (newest raw sample the isolate has) → lastConfirmedPoint
  /// (the isolate's anchor — its durationSeconds can be fresher than
  /// finalLocations.last even with an unchanged position, from a pure
  /// stationary tick) → finalLocations.last (last Firestore-synced point).
  /// Returns the full point, not just its position — durationSeconds
  /// matters too: callers derive both the pin's location AND its "last
  /// active" time label from the SAME resolved point (see
  /// LocationSyncResult.lastActiveAt), so the two can never disagree the
  /// way they used to when time was computed separately from
  /// finalLocations.last alone — that goes stale during a stationary run
  /// after a sync trims currentBatch to empty, since duration keeps
  /// climbing on the anchor, which finalLocations doesn't see until the
  /// next sync commits it. Shared by every caller that maps a snapshot to
  /// UI state — HomeBloc's per-sample live update and this service's own
  /// sync paths — so they can't drift on which point they trust first.
  static LocationPoint? resolveLastKnownLocationWithTimestamp({
    required List<LocationPoint> currentBatch,
    required LocationPoint? lastConfirmedPoint,
    required List<LocationPoint> finalLocations,
  }) {
    if (currentBatch.isNotEmpty) return currentBatch.last;
    if (lastConfirmedPoint != null) return lastConfirmedPoint;
    if (finalLocations.isNotEmpty) return finalLocations.last;
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
}
