import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../core/constants/app_constants.dart';
import '../../firebase_options.dart';

class LocationTrackingService {
  static final FlutterBackgroundService _bgService =
      FlutterBackgroundService();

  static Future<void> initialize() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      AppConstants.bgServiceChannel,
      'Location Tracking',
      description: 'Agoriya tracks your location while punched in.',
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
        initialNotificationTitle: 'Agoriya',
        initialNotificationContent: 'Tracking location...',
        foregroundServiceNotificationId: AppConstants.bgNotificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  static Future<void> start(String userId, String date) async {
    final already = await _bgService.isRunning();

    if (!already) {
      await _bgService.startService();
      debugPrint('[LocationService] Service started fresh');
      // Wait for the background isolate to boot and register its listeners.
      await Future.delayed(const Duration(milliseconds: 1200));
    } else {
      debugPrint(
          '[LocationService] Service already running — updating params');
    }

    _bgService.invoke('setParams', {'userId': userId, 'date': date});
    debugPrint(
        '[LocationService] setParams sent → userId=$userId, date=$date');
  }

  static void stop() {
    _bgService.invoke('stopTracking');
    debugPrint('[LocationService] stopTracking sent');
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
  // Counts collected points since the last batchFlushed signal.
  // HomeBloc owns all location storage and distance calculation —
  // the bg service only drives the GPS sampling cadence.
  int pointsSinceLastSignal = 0;
  Timer? samplingTimer;

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> collectLocation() async {
    if (userId == null || date == null) {
      debugPrint(
          '[LocationService] collectLocation skipped: params not set yet');
      return;
    }
    debugPrint('[LocationService] Collecting GPS position...');
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

      final now = DateTime.now();
      pointsSinceLastSignal++;

      // Notify UI so it can update the map and local storage immediately.
      service.invoke('newPoint', {
        'lat': pos.latitude,
        'lng': pos.longitude,
        'timestamp': now.toIso8601String(),
      });

      // Signal HomeBloc to OSRM-snap and commit every N points.
      // HomeBloc is the sole owner of Firestore writes and distance calculation.
      if (pointsSinceLastSignal >= AppConstants.locationBatchSize) {
        pointsSinceLastSignal = 0;
        service.invoke('batchFlushed', {
          'batchSize': AppConstants.locationBatchSize,
        });
        debugPrint(
            '[LocationService] batchFlushed signal sent → HomeBloc will snap & commit');
      }
    } catch (e) {
      debugPrint('[LocationService] collectLocation error: $e');
    }
  }

  // ── Listeners ─────────────────────────────────────────────────────────────
  // Registered BEFORE Firebase.initializeApp() so that setParams sent by the
  // main isolate (after its 1200 ms startup delay) is never missed.

  service.on('setParams').listen((data) {
    if (data == null) return;
    userId = data['userId'] as String?;
    date = data['date'] as String?;
    debugPrint(
        '[LocationService] setParams received → userId=$userId, date=$date');
    collectLocation();
  });

  service.on('stopTracking').listen((_) async {
    debugPrint('[LocationService] Stopping');
    samplingTimer?.cancel();
    // Signal HomeBloc to snap and commit any remaining points in currentBatch.
    if (pointsSinceLastSignal > 0) {
      service.invoke('batchFlushed', {'batchSize': pointsSinceLastSignal});
      debugPrint(
          '[LocationService] Final batchFlushed signal sent (${pointsSinceLastSignal} remaining points)');
    }
    debugPrint('[LocationService] Stopped');
    service.stopSelf();
  });

  // ── Firebase init ─────────────────────────────────────────────────────────
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[LocationService] Isolate started, Firebase ready');

  // ── Periodic sampling ─────────────────────────────────────────────────────
  samplingTimer = Timer.periodic(
    Duration(seconds: AppConstants.locationSamplingSeconds),
    (_) => collectLocation(),
  );
}
