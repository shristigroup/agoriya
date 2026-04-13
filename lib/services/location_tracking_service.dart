import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../core/constants/app_constants.dart';
import '../../firebase_options.dart';

class LocationTrackingService {
  static final FlutterBackgroundService _bgService = FlutterBackgroundService();

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
      // Service survived a previous session — don't spawn a second isolate,
      // just update the params on the already-running one.
      debugPrint('[LocationService] Service already running — updating params');
    }

    _bgService.invoke('setParams', {'userId': userId, 'date': date});
    debugPrint('[LocationService] setParams sent → userId=$userId, date=$date');
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

  // Passing options directly avoids slow native config discovery which
  // can push past Android's 5-second startForeground() deadline.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[LocationService] Isolate started, Firebase ready');

  String? userId;
  String? date;
  Position? lastPosition;
  final List<Map<String, dynamic>> pendingBatch = [];
  final List<Map<String, dynamic>> allPoints = []; // never cleared — for distance calc
  DateTime? lastDistanceUpdate;
  Timer? samplingTimer;

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> flushBatch(List<Map<String, dynamic>> batch) async {
    if (batch.isEmpty || userId == null || date == null) return;
    try {
      final db = FirebaseFirestore.instance;
      await db
          .collection(AppConstants.usersCollection)
          .doc(userId!)
          .collection(AppConstants.locationsCollection)
          .doc(date!)
          .set(
            {'locations': FieldValue.arrayUnion(List.from(batch))},
            SetOptions(merge: true),
          );
      debugPrint('[LocationService] Flushed ${batch.length} point(s) to Firestore');
      // Notify UI so it can OSRM-snap this batch
      service.invoke('batchFlushed', {'batchSize': batch.length});
    } catch (e) {
      debugPrint('[LocationService] flushBatch error: $e');
    }
  }

  Future<void> updateDistance(List<Map<String, dynamic>> allPoints) async {
    if (allPoints.length < 2 || userId == null || date == null) return;
    try {
      double totalKm = 0.0;
      final dist = const Distance();
      for (int i = 0; i < allPoints.length - 1; i++) {
        final a = allPoints[i]['geoPoint'] as GeoPoint;
        final b = allPoints[i + 1]['geoPoint'] as GeoPoint;
        totalKm += dist.as(
          LengthUnit.Kilometer,
          LatLng(a.latitude, a.longitude),
          LatLng(b.latitude, b.longitude),
        );
      }
      final db = FirebaseFirestore.instance;
      await db
          .collection(AppConstants.usersCollection)
          .doc(userId!)
          .collection(AppConstants.attendanceCollection)
          .doc(date!)
          .update({'distance': totalKm});
      debugPrint('[LocationService] Distance updated: ${totalKm.toStringAsFixed(3)} km');
    } catch (e) {
      debugPrint('[LocationService] updateDistance error: $e');
    }
  }

  Future<void> collectLocation() async {
    if (userId == null || date == null) {
      debugPrint('[LocationService] collectLocation skipped: params not set yet');
      return;
    }
    debugPrint('[LocationService] Collecting GPS position...');
    try {
      // Use medium accuracy so network/WiFi positioning works indoors.
      // Cap at 15 s — if no fix arrives, fall back to last known position.
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 15),
          ),
        );
      } catch (_) {
        debugPrint('[LocationService] getCurrentPosition timed out, using last known');
        pos = await Geolocator.getLastKnownPosition();
      }

      if (pos == null) {
        debugPrint('[LocationService] No position available, skipping');
        return;
      }
      debugPrint('[LocationService] Position: ${pos.latitude}, ${pos.longitude} '
          '(accuracy: ${pos.accuracy.toStringAsFixed(1)}m)');

      // Record every sample — the 1-min timer is the throttle.
      lastPosition = pos;
      final now = DateTime.now();
      final point = {
        'geoPoint': GeoPoint(pos.latitude, pos.longitude),
        'timestamp': Timestamp.fromDate(now),
        'snapped': false, // raw GPS — UI will OSRM-snap in batches
      };
      pendingBatch.add(point);
      allPoints.add(point);
      debugPrint('[LocationService] Point recorded — batch: ${pendingBatch.length}, total: ${allPoints.length}');

      // Notify UI so it can update the map and local storage immediately.
      service.invoke('newPoint', {
        'lat': pos.latitude,
        'lng': pos.longitude,
        'timestamp': now.toIso8601String(),
      });

      // Flush to Firestore every 10 points (~10 min at 1-min sampling).
      if (pendingBatch.length >= AppConstants.locationBatchSize) {
        final toFlush = List<Map<String, dynamic>>.from(pendingBatch);
        pendingBatch.clear();
        await flushBatch(toFlush);
      }

      // Update distance every 10 min (use allPoints so history isn't lost after flushes)
      if (lastDistanceUpdate == null ||
          DateTime.now().difference(lastDistanceUpdate!).inMinutes >=
              AppConstants.distanceCalculationMinutes) {
        lastDistanceUpdate = DateTime.now();
        await updateDistance(allPoints);
      }
    } catch (e) {
      debugPrint('[LocationService] collectLocation error: $e');
    }
  }

  // ── Listeners ─────────────────────────────────────────────────────────────

  // setParams is sent by the app after startService(). Once received,
  // trigger an immediate collection so the UI gets a point right away
  // instead of waiting for the first timer tick.
  service.on('setParams').listen((data) {
    if (data == null) return;
    userId = data['userId'] as String?;
    date = data['date'] as String?;
    debugPrint('[LocationService] setParams received → userId=$userId, date=$date');
    collectLocation();
  });

  service.on('stopTracking').listen((_) async {
    debugPrint('[LocationService] Stopping — flushing remaining ${pendingBatch.length} point(s)');
    samplingTimer?.cancel();
    if (pendingBatch.isNotEmpty) {
      await flushBatch(pendingBatch);
    }
    if (allPoints.length >= 2) {
      await updateDistance(allPoints);
    }
    debugPrint('[LocationService] Stopped');
    service.stopSelf();
  });

  // ── Periodic sampling ─────────────────────────────────────────────────────
  samplingTimer = Timer.periodic(
    Duration(seconds: AppConstants.locationSamplingSeconds),
    (_) => collectLocation(),
  );
}
