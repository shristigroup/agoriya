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
import 'route_cleaner.dart';

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
    bool punchOut = false,
    void Function(int done, int total)? onProgress,
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
          punchOut: punchOut,
          onProgress: onProgress,
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
    bool punchOut = false,
    void Function(int done, int total)? onProgress,
  }) =>
      syncPending(
        pending: snap?.currentBatch ?? const [],
        anchorStay: snap?.lastConfirmedPoint?.durationSeconds,
        finalLocations: finalLocations,
        finalLocationsDistance: finalLocationsDistance,
        holdBackTail: holdBackTail,
        punchOut: punchOut,
        onProgress: onProgress,
        match: OsrmService.matchTrace,
        persist: (all, distance) => DataManager.persistLocations(
          userId: userId,
          trackingId: trackingId,
          allLocations: all,
          distanceKm: distance,
        ),
        confirm: (anchor, distance, trimUpTo) =>
            LocationTrackingService.confirmBatchSynced(anchor,
                distanceKm: distance, trimUpTo: trimUpTo),
      );

  /// The sync itself, with OSRM, the Firestore write and the confirmation to the
  /// tracking isolate passed in so it can be exercised with fakes.
  static Future<(List<LocationPoint>, double)?> syncPending({
    required List<LocationPoint> pending,
    required int? anchorStay,
    required List<LocationPoint> finalLocations,
    required double finalLocationsDistance,
    required Future<OsrmTrace> Function(List<LatLng> points, List<DateTime> times)
        match,
    required Future<void> Function(List<LocationPoint> all, double distanceKm)
        persist,
    required void Function(
            LocationPoint anchor, double distanceKm, DateTime trimUpTo)
        confirm,
    bool holdBackTail = false,
    bool punchOut = false,
    void Function(int done, int total)? onProgress,
  }) async {
    try {
      final sorted = List<LocationPoint>.from(pending)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final lastStored =
          finalLocations.isNotEmpty ? finalLocations.last.timestamp : null;
      var toSend = lastStored != null
          ? sorted.where((p) => p.timestamp.isAfter(lastStored)).toList()
          : sorted;
      if (toSend.isEmpty && finalLocations.isEmpty) return null;

      LocationPoint? heldBack;
      if (holdBackTail &&
          toSend.isNotEmpty &&
          (toSend.last.durationSeconds ?? 0) == 0) {
        print('[LocationSync] Holding back the newest point until the next '
            'sample confirms it');
        heldBack = toSend.last;
        toSend = toSend.sublist(0, toSend.length - 1);
      }

      var all = List<LocationPoint>.from(finalLocations);
      var distance = finalLocationsDistance;

      // Writes the whole list, then tells the tracking isolate to trim what is
      // now synced and move its anchor. The anchor is the last point that was
      // KEPT (a trailing dropped point must not become the reference for later
      // samples); the trim covers everything saved.
      Future<void> commit() async {
        await persist(all, distance);
        final kept = all.visible;
        confirm(kept.isNotEmpty ? kept.last : all.last, distance,
            all.last.timestamp);
      }

      // Nothing new to store: fold in the isolate's anchor stay duration, the
      // only thing that can have changed, and write that.
      if (toSend.isEmpty) {
        final idx = _lastVisibleIndex(all);
        if (idx >= 0 && anchorStay != null && all[idx].durationSeconds != anchorStay) {
          all[idx] = all[idx].copyWith(durationSeconds: anchorStay);
        }
        if (all.isEmpty) return null;
        await commit();
        return (all, distance);
      }

      // Units of up to 10 OSRM coordinates (the last saved point goes first so
      // each road path starts exactly where the previous one ended). Each unit
      // is matched, cleaned, written and trimmed before the next one starts.
      final total = toSend.length;
      var done = 0;
      var osrmSkipped = false; // punch-out only: OSRM did not answer once
      var wroteAny = false;
      var i = 0;
      onProgress?.call(0, total);
      while (i < toSend.length) {
        final carryIdx = _lastVisibleIndex(all);
        final carry = carryIdx >= 0 ? all[carryIdx] : null;
        final room = AppConstants.osrmMaxCoordinates - (carry != null ? 1 : 0);
        final end = (i + room).clamp(0, toSend.length);
        final unit = toSend.sublist(i, end);
        final next = end < toSend.length ? toSend[end] : heldBack;
        final inputs = [if (carry != null) carry, ...unit];

        final OsrmTrace trace = osrmSkipped
            ? OsrmTrace.failed('skipped', inputs.length)
            : inputs.length < 2
                ? OsrmTrace.failed('batch_too_small', inputs.length)
                : await match(
                    inputs.map((p) => p.position).toList(),
                    inputs.map((p) => p.timestamp).toList(),
                  );

        if (trace.noAnswer) {
          if (!punchOut) {
            // OSRM did not answer (not "no match": that is an answer). Keep
            // this unit and everything after it pending; the next sync retries.
            print('[LocationSync] OSRM gave no answer (${trace.reason}) — '
                'keeping ${toSend.length - i} points pending');
            break;
          }
          // Punching out: do not wait. Store the points as they are, and do not
          // ask OSRM again for the rest of this run.
          osrmSkipped = true;
        }

        // Clean the points OSRM could not place (the saved carry too, when it
        // is unmatched), then rebuild without the dropped ones.
        var built = RouteBuilder.build(carry: carry, raw: unit, trace: trace);
        final droppedMs =
            RouteCleaner.clean(history: all, unit: built.stored, next: next);
        final p8 = carryIdx > 0 ? _visibleBefore(all, carryIdx) : null;
        if (droppedMs.isNotEmpty) {
          built = RouteBuilder.build(
            carry: carry,
            raw: unit,
            trace: trace,
            droppedMs: droppedMs,
            fallbackStart: p8,
          );
          print('[LocationSync] Dropped ${droppedMs.length} stray point(s)');
        }

        final carryDropped = carry != null &&
            droppedMs.contains(carry.timestamp.millisecondsSinceEpoch);
        if (carryDropped) {
          all[carryIdx] = carry.copyWith(dropped: true);
          if (p8 != null) {
            distance -=
                AppUtils.haversineMeters(p8.position, carry.position) / 1000.0;
          }
        } else if (built.carry != null) {
          all[carryIdx] = built.carry!;
        }
        all.addAll(built.stored);
        distance += built.distanceKm;
        // Why OSRM was or wasn't used, and this unit's distance, on its last point.
        all[all.length - 1] = all.last.copyWith(
          cumulativeDistanceKm: distance,
          batchDistanceKm: built.distanceKm,
          snapReason: trace.reason,
        );

        print('[LocationSync] Unit of ${unit.length} points → ${trace.reason} '
            '(distance ${distance.toStringAsFixed(3)} km)');
        await commit();
        wroteAny = true;
        done += unit.length;
        onProgress?.call(done, total);
        i = end;
      }

      return wroteAny ? (all, distance) : null;
    } catch (e) {
      print('[LocationSync] syncPending error: $e');
      return null;
    }
  }

  /// Index of the last point that was not dropped, or -1.
  static int _lastVisibleIndex(List<LocationPoint> points) {
    for (var i = points.length - 1; i >= 0; i--) {
      if (!points[i].dropped) return i;
    }
    return -1;
  }

  /// The last kept point before index [idx], or null.
  static LocationPoint? _visibleBefore(List<LocationPoint> points, int idx) {
    for (var i = idx - 1; i >= 0; i--) {
      if (!points[i].dropped) return points[i];
    }
    return null;
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
    final kept = finalLocations.visible;
    if (kept.isNotEmpty) return kept.last;
    return null;
  }

  /// Live haversine estimate for the unsynced [batch], anchored to the last
  /// committed point in [finalLocations].
  static double batchDistanceKm(
      List<LocationPoint> batch, List<LocationPoint> finalLocations) {
    if (batch.isEmpty) return 0.0;
    final kept = finalLocations.visible;
    final points = [if (kept.isNotEmpty) kept.last, ...batch];
    double sum = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      sum += AppUtils.haversineMeters(points[i].position, points[i + 1].position) /
          1000.0;
    }
    return sum;
  }
}
