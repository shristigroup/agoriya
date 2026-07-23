import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:latlong2/latlong.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/app_utils.dart';
import '../data/local/local_storage_service.dart';
import '../data/models/location_model.dart';
import '../firebase_options.dart';

/// Snapshot of the background isolate's tracking-cursor state, returned by
/// [LocationTrackingService.requestSnapshot]. HomeBloc uses this instead of
/// ever opening the cursor Hive box itself — see AppConstants.trackingCursorBox
/// for why that box must stay isolate-exclusive.
class TrackingSnapshot {
  final List<LocationPoint> currentBatch;
  final LocationPoint? lastConfirmedPoint;
  final int pendingSampleCount;

  const TrackingSnapshot({
    required this.currentBatch,
    required this.lastConfirmedPoint,
    required this.pendingSampleCount,
  });
}

class LocationTrackingService {
  static final FlutterBackgroundService _bgService =
      FlutterBackgroundService();

  static Future<void> initialize() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      AppConstants.bgServiceChannel,
      'Location Tracking',
      description: 'TrackFolks tracks your location while punched in.',
      importance: Importance.low,
    );

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _bgService.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: AppConstants.bgServiceChannel,
        initialNotificationTitle: 'TrackFolks',
        initialNotificationContent: 'Tracking location...',
        foregroundServiceNotificationId: AppConstants.bgNotificationId,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  /// Starts (or updates params on an already-running) tracking session.
  /// [fresh] should be true ONLY for a genuine new punch-in — it tells the
  /// isolate to wipe its cursor state (currentBatch/pendingSampleCount/
  /// lastConfirmedPoint) before sampling begins. Every other caller (init
  /// reconciliation, resume, FCM wakeup, app-resume restart) continues an
  /// existing session and must leave cursor state intact.
  static Future<void> start(String userId, String date,
      {bool fresh = false}) async {
    // If a previous service is still shutting down (stopSelf is async),
    // wait until it fully stops before starting fresh. Without this, isRunning()
    // can return true mid-shutdown → we skip startService() → dying service
    // gets setParams → stopSelf() completes → service dies → no notification.
    if (await _bgService.isRunning()) {
      print('[LocationService] Service still stopping — waiting...');
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (!await _bgService.isRunning()) break;
      }
    }

    if (!await _bgService.isRunning()) {
      // Listen for the ready signal BEFORE starting the service so we never
      // miss it even if the isolate boots faster than expected.
      final readyCompleter = Completer<void>();
      final readySub = _bgService.on('serviceReady').listen((_) {
        if (!readyCompleter.isCompleted) readyCompleter.complete();
      });

      await _bgService.startService();
      print('[LocationService] Service started — waiting for isolate ready signal');

      // Wait for the background isolate to signal it's ready, with a 4s fallback.
      await readyCompleter.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () => print('[LocationService] serviceReady timeout — proceeding anyway'),
      );
      await readySub.cancel();
    } else {
      print('[LocationService] Service already running — updating params');
    }

    _bgService.invoke('setParams', {'userId': userId, 'date': date, 'fresh': fresh});
    print(
        '[LocationService] setParams sent → userId=$userId, date=$date, fresh=$fresh');
  }

  static void stop() {
    _bgService.invoke('stopTracking');
    print('[LocationService] stopTracking sent');
  }

  /// Confirms a successfully synced point so the background isolate (sole
  /// owner of the cursor box) can (a) trim currentBatch up to this point's
  /// timestamp and (b) update its stationary/movement anchor to this point.
  /// Never called on sync failure — leaving cursor state untouched is what
  /// makes a failed sync naturally retryable on the next signal/resume.
  static void confirmBatchSynced(LocationPoint lastSyncedPoint) {
    _bgService.invoke('batchSynced', {
      'uptoTimestamp': lastSyncedPoint.timestamp.toIso8601String(),
      'anchorLat': lastSyncedPoint.position.latitude,
      'anchorLng': lastSyncedPoint.position.longitude,
      'anchorTimestamp': lastSyncedPoint.timestamp.toIso8601String(),
      'anchorDurationSeconds': lastSyncedPoint.durationSeconds,
    });
  }

  /// Requests the isolate's current cursor state. Returns null if the
  /// isolate isn't running or doesn't respond within the timeout — callers
  /// should treat that as "nothing available right now", not block forever.
  static Future<TrackingSnapshot?> requestSnapshot() async {
    if (!await isRunning) return null;

    final completer = Completer<Map<String, dynamic>?>();
    final sub = _bgService.on('snapshot').listen((data) {
      if (!completer.isCompleted) completer.complete(data);
    });
    _bgService.invoke('requestSnapshot');

    final data = await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
    await sub.cancel();
    if (data == null) {
      print('[LocationService] requestSnapshot timed out');
      return null;
    }

    final batch = (data['currentBatch'] as List)
        .map((e) => LocationPoint.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final anchorJson = data['lastConfirmedPoint'] as Map?;
    final anchor = anchorJson != null
        ? LocationPoint.fromJson(Map<String, dynamic>.from(anchorJson))
        : null;
    final pendingCount = (data['pendingSampleCount'] as num?)?.toInt() ?? 0;

    return TrackingSnapshot(
      currentBatch: batch,
      lastConfirmedPoint: anchor,
      pendingSampleCount: pendingCount,
    );
  }

  static Future<bool> get isRunning => _bgService.isRunning();
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  String? userId;
  String? date;
  int pointsSinceLastSignal = 0;

  // Android: periodic timer (foreground service keeps the process alive).
  // iOS:     persistent position stream (keeps the isolate alive in background).
  Timer? samplingTimer;
  StreamSubscription<Position>? positionSub;

  String _ts([DateTime? at]) {
    final t = at ?? DateTime.now();
    return '${t.hour.toString().padLeft(2,'0')}:'
           '${t.minute.toString().padLeft(2,'0')}:'
           '${t.second.toString().padLeft(2,'0')}';
  }

  // Android only: re-shows the foreground-service notification with the same
  // id/channel so Android updates it in place instead of posting a new one.
  // Without this, "Tracking location..." stays static for the entire session
  // even if sampling has silently stalled (permission revoked, OEM battery
  // manager suspending callbacks, an unhandled error) — there'd be no way to
  // tell a healthy session from a dead one just by looking at the notification.
  final notificationsPlugin = FlutterLocalNotificationsPlugin();
  Future<void> updateTrackingNotification(DateTime sampledAt) async {
    if (!Platform.isAndroid) return;
    final hhmm = '${sampledAt.hour.toString().padLeft(2, '0')}:'
        '${sampledAt.minute.toString().padLeft(2, '0')}';
    await notificationsPlugin.show(
      AppConstants.bgNotificationId,
      'TrackFolks',
      'Tracking location · last sample $hhmm',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          AppConstants.bgServiceChannel,
          'Location Tracking',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
        ),
      ),
    );
  }

  // ── Sample handling: this isolate is the SOLE owner of the tracking
  // cursor box (currentBatch, pendingSampleCount, lastConfirmedPoint).
  // finalLocations stays entirely HomeBloc's own data — the isolate only
  // ever needs the single last-confirmed point as an anchor, never the full
  // synced history. See AppConstants.trackingCursorBox.

  Future<void> handleSample(double lat, double lng, DateTime timestamp) async {
    if (userId == null || date == null) {
      print('[LocationService] handleSample skipped: params not set yet');
      return;
    }

    final newPosition = LatLng(lat, lng);
    final currentBatch = LocalStorageService.getCurrentBatch();
    final anchor = LocalStorageService.getLastConfirmedPoint();
    final lastPoint = currentBatch.isNotEmpty ? currentBatch.last : anchor;

    final distanceMeters = lastPoint != null
        ? AppUtils.haversineMeters(lastPoint.position, newPosition)
        : 0.0;

    if (lastPoint != null &&
        distanceMeters < AppConstants.stationaryThresholdMeters.toDouble()) {
      // Stationary: update durationSeconds on the last point, don't append.
      final durationSeconds =
          timestamp.difference(lastPoint.timestamp).inSeconds;
      if (currentBatch.isNotEmpty) {
        final pts = List<LocationPoint>.from(currentBatch);
        pts[pts.length - 1] =
            pts.last.copyWith(durationSeconds: durationSeconds);
        await LocalStorageService.saveCurrentBatch(pts);
      } else if (anchor != null) {
        await LocalStorageService.saveLastConfirmedPoint(
            anchor.copyWith(durationSeconds: durationSeconds));
      }
      print('[LocationService ${_ts()}] stationary tick'
          ' | durationSeconds=$durationSeconds → $lat, $lng');
    } else {
      // Movement: append a new raw point to currentBatch.
      final pts = [
        ...currentBatch,
        LocationPoint(position: newPosition, timestamp: timestamp, isSnapped: false),
      ];
      await LocalStorageService.saveCurrentBatch(pts);
      print('[LocationService ${_ts()}] point stored → $lat, $lng');
    }

    // Tracks samples since the last CONFIRMED sync (reset only in the
    // batchSynced handler below, not just on wrapping) — persisted so a
    // fresh app open can tell a sync was missed even during a pure
    // stationary run, when currentBatch itself never grows.
    pointsSinceLastSignal++;
    await LocalStorageService.savePendingSampleCount(pointsSinceLastSignal);
    final bool flush = pointsSinceLastSignal % AppConstants.locationBatchSize == 0;

    // Push the fresh cursor state along with the signal so HomeBloc's live
    // UI update doesn't need a round-trip for the common case — only
    // cold-start catch-up (_onInit/_onAppResumed/_processBatch) uses
    // requestSnapshot.
    final freshBatch = LocalStorageService.getCurrentBatch();
    final freshAnchor = LocalStorageService.getLastConfirmedPoint();
    service.invoke('newPoint', {
      'processBatch': flush,
      'currentBatch': freshBatch.map((p) => p.toJson()).toList(),
      'lastConfirmedPoint': freshAnchor?.toJson(),
    });
    print('[LocationService ${_ts()}] signal'
        ' #$pointsSinceLastSignal'
        '${flush ? ' → flush' : ''}');

    await updateTrackingNotification(timestamp);
  }

  // ── Android: one-shot GPS collection ──────────────────────────────────────

  Future<void> collectLocation() async {
    if (userId == null || date == null) {
      print(
          '[LocationService] collectLocation skipped: params not set yet');
      return;
    }
    try {
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 15),
          ),
        );
      } catch (_) {
        print(
            '[LocationService] getCurrentPosition timed out, using last known');
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) {
        print('[LocationService] No position available, skipping');
        return;
      }
      print(
          '[LocationService] Position: ${pos.latitude}, ${pos.longitude} '
          '(accuracy: ${pos.accuracy.toStringAsFixed(1)}m)');
      await handleSample(pos.latitude, pos.longitude, DateTime.now());
    } catch (e) {
      print('[LocationService] collectLocation error: $e');
    }
  }

  // ── iOS: lazy position stream (started once on setParams) ─────────────────

  void startPositionStream() {
    if (positionSub != null) return; // idempotent

    // iOS: a CLLocationManager stream keeps the isolate alive in background.
    // A Dart timer would be suspended by iOS after ~30 s.
    // pauseLocationUpdatesAutomatically: false  — prevents iOS stopping
    //   updates when the device is stationary (e.g. user at a desk).
    // showBackgroundLocationIndicator: true — shows the blue status-bar pill;
    //   iOS requires this for persistent background location.
    DateTime? lastPointTime;
    final locationSettings = AppleSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: 0,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
      activityType: ActivityType.otherNavigation,
    );

    positionSub =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen(
      (pos) async {
        // Time-gate: honour the same sampling interval as Android.
        final now = DateTime.now();
        if (lastPointTime != null &&
            now.difference(lastPointTime!) <
                Duration(seconds: AppConstants.locationSamplingSeconds)) {
          return;
        }
        lastPointTime = now;
        await handleSample(pos.latitude, pos.longitude, now);
      },
      onError: (e) => print('[LocationService] positionStream error: $e'),
    );
    print('[LocationService] iOS position stream started');
  }

  // ── Listeners ──────────────────────────────────────────────────────────────
  // Registered BEFORE Firebase.initializeApp() so that setParams sent by the
  // main isolate (after its 1200 ms startup delay) is never missed.

  service.on('setParams').listen((data) async {
    if (data == null) return;
    userId = data['userId'] as String?;
    date = data['date'] as String?;
    final fresh = data['fresh'] as bool? ?? false;
    if (fresh) {
      await LocalStorageService.clearCursorState();
      pointsSinceLastSignal = 0;
      print('[LocationService] Fresh session — cleared cursor state');
    }
    print(
        '[LocationService] setParams received → userId=$userId, date=$date, fresh=$fresh');
    if (Platform.isAndroid) {
      collectLocation(); // immediate first point; timer handles the rest
    } else {
      startPositionStream(); // lazy start; idempotent on re-sends
    }
  });

  // HomeBloc requests the current cursor state (e.g. on cold start, app
  // resume, or right before syncing) instead of ever opening this isolate's
  // Hive box itself.
  service.on('requestSnapshot').listen((_) {
    final batch = LocalStorageService.getCurrentBatch();
    final anchor = LocalStorageService.getLastConfirmedPoint();
    final pending = LocalStorageService.getPendingSampleCount();
    service.invoke('snapshot', {
      'currentBatch': batch.map((p) => p.toJson()).toList(),
      'lastConfirmedPoint': anchor?.toJson(),
      'pendingSampleCount': pending,
    });
  });

  // HomeBloc confirms a successful OSRM+Firestore sync by sending the last
  // synced point. Trim currentBatch only up to that point's timestamp —
  // anything appended concurrently during the sync is left intact — and
  // adopt it as the new stationary/movement anchor.
  service.on('batchSynced').listen((data) async {
    if (data == null) return;
    final uptoIso = data['uptoTimestamp'] as String?;
    if (uptoIso == null) return;
    final upto = DateTime.parse(uptoIso);

    final remaining = LocalStorageService.getCurrentBatch()
        .where((p) => p.timestamp.isAfter(upto))
        .toList();
    await LocalStorageService.saveCurrentBatch(remaining);

    final anchorLat = data['anchorLat'] as num?;
    final anchorLng = data['anchorLng'] as num?;
    final anchorTsIso = data['anchorTimestamp'] as String?;
    if (anchorLat != null && anchorLng != null && anchorTsIso != null) {
      final anchor = LocationPoint(
        position: LatLng(anchorLat.toDouble(), anchorLng.toDouble()),
        timestamp: DateTime.parse(anchorTsIso),
        isSnapped: true,
        durationSeconds: (data['anchorDurationSeconds'] as num?)?.toInt(),
      );
      await LocalStorageService.saveLastConfirmedPoint(anchor);
    }

    // Confirmed synced — reset the pending-sample counter so a later dead
    // period is measured from here, not from whenever it last happened to
    // wrap. Any samples that arrived during the sync round-trip (after the
    // batch snapshot but before this confirmation) are undercounted by this
    // reset, but their data isn't lost — they're still in `remaining` above
    // and will be picked up by the next signal or catch-up check.
    pointsSinceLastSignal = 0;
    await LocalStorageService.savePendingSampleCount(0);
    print('[LocationService] batchSynced trim → upto=$uptoIso, '
        'remaining=${remaining.length}');
  });

  service.on('stopTracking').listen((_) async {
    print('[LocationService] Stopping');
    samplingTimer?.cancel();
    await positionSub?.cancel();
    positionSub = null;
    // No synthetic final point needed: every sample is written to Hive as
    // it's captured, so there's nothing pending to flush here. HomeBloc's
    // punch-out flow requests a snapshot before calling stop().
    print('[LocationService] Stopped');
    service.stopSelf();
  });

  // ── Hive + Firebase init ─────────────────────────────────────────────────
  await LocalStorageService.openCursorBoxOnly();
  // Resume the pending-sample count in case this isolate itself restarted
  // (crash, watchdog-triggered restart) — otherwise a fresh in-memory 0
  // would understate how much has actually gone unconfirmed.
  pointsSinceLastSignal = LocalStorageService.getPendingSampleCount();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Signal the main isolate that listeners are registered and Firebase is ready.
  // start() waits for this instead of a fixed delay.
  service.invoke('serviceReady', {});
  print('[LocationService] Isolate started, Firebase ready → serviceReady sent');

  // ── Start platform-specific GPS collection ─────────────────────────────────

  if (Platform.isAndroid) {
    // Foreground service keeps the process alive indefinitely — timer is safe.
    samplingTimer = Timer.periodic(
      Duration(seconds: AppConstants.locationSamplingSeconds),
      (_) => collectLocation(),
    );
    print('[LocationService] Android timer started '
        '(interval: ${AppConstants.locationSamplingSeconds}s)');
  }
  // iOS: position stream is started lazily from the setParams listener above.
}
