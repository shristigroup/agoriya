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

  static Future<void> start(String userId, String date) async {
    // If a previous service is still shutting down (stopSelf is async),
    // wait until it fully stops before starting fresh. Without this, isRunning()
    // can return true mid-shutdown → we skip startService() → dying service
    // gets setParams → stopSelf() completes → service dies → no notification.
    if (await _bgService.isRunning()) {
      debugPrint('[LocationService] Service still stopping — waiting...');
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
      debugPrint('[LocationService] Service started — waiting for isolate ready signal');

      // Wait for the background isolate to signal it's ready, with a 4s fallback.
      await readyCompleter.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () => debugPrint('[LocationService] serviceReady timeout — proceeding anyway'),
      );
      await readySub.cancel();
    } else {
      debugPrint('[LocationService] Service already running — updating params');
    }

    _bgService.invoke('setParams', {'userId': userId, 'date': date});
    debugPrint(
        '[LocationService] setParams sent → userId=$userId, date=$date');
  }

  static void stop() {
    _bgService.invoke('stopTracking');
    debugPrint('[LocationService] stopTracking sent');
  }

  /// Confirms a successfully synced batch so the background isolate (the
  /// sole writer of currentBatch) can trim entries up to this timestamp.
  /// Never called on sync failure — leaving currentBatch untouched is what
  /// makes a failed sync naturally retryable on the next signal/resume.
  static void confirmBatchSynced(DateTime uptoTimestamp) {
    _bgService.invoke('batchSynced', {
      'uptoTimestamp': uptoTimestamp.toIso8601String(),
    });
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

  String _ts() {
    final t = DateTime.now();
    return '${t.hour.toString().padLeft(2,'0')}:'
           '${t.minute.toString().padLeft(2,'0')}:'
           '${t.second.toString().padLeft(2,'0')}';
  }

  // ── Sample handling: this isolate is the SOLE writer of currentBatch ──────
  // (and of the durationSeconds field on the last finalLocations entry, for
  // the stationary case with an empty currentBatch). HomeBloc only reads
  // these — see location_tracking_service design notes in the fix plan.

  Future<void> handleSample(double lat, double lng, DateTime timestamp) async {
    if (userId == null || date == null) {
      debugPrint('[LocationService] handleSample skipped: params not set yet');
      return;
    }

    // Cross-isolate box: reload so we see any finalLocations write HomeBloc
    // may have made (e.g. after a batch sync) since our last sample.
    await LocalStorageService.reloadLocationsBox();

    final newPosition = LatLng(lat, lng);
    final currentBatch = LocalStorageService.getCurrentBatch();
    final finalLocations = LocalStorageService.getFinalLocations();
    final lastPoint = currentBatch.isNotEmpty
        ? currentBatch.last
        : (finalLocations.isNotEmpty ? finalLocations.last : null);

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
      } else if (finalLocations.isNotEmpty) {
        final pts = List<LocationPoint>.from(finalLocations);
        pts[pts.length - 1] =
            pts.last.copyWith(durationSeconds: durationSeconds);
        await LocalStorageService.saveFinalLocations(pts);
      }
      debugPrint('[LocationService ${_ts()}] stationary'
          ' | durationSeconds=$durationSeconds → $lat, $lng');
    } else {
      // Movement: append a new raw point to currentBatch.
      final pts = [
        ...currentBatch,
        LocationPoint(position: newPosition, timestamp: timestamp, isSnapped: false),
      ];
      await LocalStorageService.saveCurrentBatch(pts);
    }

    pointsSinceLastSignal++;
    final bool flush = pointsSinceLastSignal >= AppConstants.locationBatchSize;
    if (flush) pointsSinceLastSignal = 0;
    service.invoke('newPoint', {'processBatch': flush});
    debugPrint('[LocationService ${_ts()}] sample stored'
        ' #${flush ? AppConstants.locationBatchSize : pointsSinceLastSignal}'
        '/${AppConstants.locationBatchSize}'
        '${flush ? ' → flush' : ''}'
        ' → $lat, $lng');
  }

  // ── Android: one-shot GPS collection ──────────────────────────────────────

  Future<void> collectLocation() async {
    if (userId == null || date == null) {
      debugPrint(
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
        debugPrint(
            '[LocationService] getCurrentPosition timed out, using last known');
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) {
        debugPrint('[LocationService] No position available, skipping');
        return;
      }
      debugPrint(
          '[LocationService] Position: ${pos.latitude}, ${pos.longitude} '
          '(accuracy: ${pos.accuracy.toStringAsFixed(1)}m)');
      await handleSample(pos.latitude, pos.longitude, DateTime.now());
    } catch (e) {
      debugPrint('[LocationService] collectLocation error: $e');
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
      onError: (e) => debugPrint('[LocationService] positionStream error: $e'),
    );
    debugPrint('[LocationService] iOS position stream started');
  }

  // ── Listeners ──────────────────────────────────────────────────────────────
  // Registered BEFORE Firebase.initializeApp() so that setParams sent by the
  // main isolate (after its 1200 ms startup delay) is never missed.

  service.on('setParams').listen((data) {
    if (data == null) return;
    userId = data['userId'] as String?;
    date = data['date'] as String?;
    debugPrint(
        '[LocationService] setParams received → userId=$userId, date=$date');
    if (Platform.isAndroid) {
      collectLocation(); // immediate first point; timer handles the rest
    } else {
      startPositionStream(); // lazy start; idempotent on re-sends
    }
  });

  // HomeBloc confirms a successful OSRM+Firestore sync by sending the
  // timestamp of the last point it processed. Trim only up to that point —
  // anything appended concurrently during the sync is left intact.
  service.on('batchSynced').listen((data) async {
    if (data == null) return;
    final uptoIso = data['uptoTimestamp'] as String?;
    if (uptoIso == null) return;
    final upto = DateTime.parse(uptoIso);

    final remaining = LocalStorageService.getCurrentBatch()
        .where((p) => p.timestamp.isAfter(upto))
        .toList();
    await LocalStorageService.saveCurrentBatch(remaining);
    debugPrint('[LocationService] batchSynced trim → upto=$uptoIso, '
        'remaining=${remaining.length}');
  });

  service.on('stopTracking').listen((_) async {
    debugPrint('[LocationService] Stopping');
    samplingTimer?.cancel();
    await positionSub?.cancel();
    positionSub = null;
    // No synthetic final point needed: every sample is written to Hive as
    // it's captured, so there's nothing pending to flush here. HomeBloc's
    // punch-out flow reads currentBatch fresh from Hive and syncs it.
    debugPrint('[LocationService] Stopped');
    service.stopSelf();
  });

  // ── Hive + Firebase init ─────────────────────────────────────────────────
  await LocalStorageService.openLocationsBoxOnly();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Signal the main isolate that listeners are registered and Firebase is ready.
  // start() waits for this instead of a fixed delay.
  service.invoke('serviceReady', {});
  debugPrint('[LocationService] Isolate started, Firebase ready → serviceReady sent');

  // ── Start platform-specific GPS collection ─────────────────────────────────

  if (Platform.isAndroid) {
    // Foreground service keeps the process alive indefinitely — timer is safe.
    samplingTimer = Timer.periodic(
      Duration(seconds: AppConstants.locationSamplingSeconds),
      (_) => collectLocation(),
    );
    debugPrint('[LocationService] Android timer started '
        '(interval: ${AppConstants.locationSamplingSeconds}s)');
  }
  // iOS: position stream is started lazily from the setParams listener above.
}
