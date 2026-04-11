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
    _bgService.invoke('setParams', {'userId': userId, 'date': date});
    await _bgService.startService();
  }

  static void stop() {
    _bgService.invoke('stopTracking');
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

  // Firebase must be initialised in background isolate separately
  await Firebase.initializeApp();

  String? userId;
  String? date;
  Position? lastPosition;
  final List<Map<String, dynamic>> pendingBatch = [];
  DateTime? lastDistanceUpdate;
  Timer? samplingTimer;

  service.on('setParams').listen((data) {
    if (data == null) return;
    userId = data['userId'] as String?;
    date = data['date'] as String?;
  });

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
    } catch (_) {}
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
    } catch (_) {}
  }

  void collectLocation() async {
    if (userId == null || date == null) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      bool shouldRecord = false;
      if (lastPosition == null) {
        shouldRecord = true;
      } else {
        final distM = Geolocator.distanceBetween(
          lastPosition!.latitude,
          lastPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
        final minsSinceLast = DateTime.now()
            .difference(
              DateTime.fromMillisecondsSinceEpoch(
                lastPosition!.timestamp.millisecondsSinceEpoch,
              ),
            )
            .inMinutes;
        if (distM >= AppConstants.locationIntervalMeters ||
            minsSinceLast >= AppConstants.locationIntervalMinutes) {
          shouldRecord = true;
        }
      }

      if (!shouldRecord) return;

      lastPosition = pos;
      final point = {
        'geoPoint': GeoPoint(pos.latitude, pos.longitude),
        'timestamp': Timestamp.fromDate(DateTime.now()),
      };
      pendingBatch.add(point);

      // Notify UI of new point
      service.invoke('newPoint', {
        'lat': pos.latitude,
        'lng': pos.longitude,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Flush when batch is full
      if (pendingBatch.length >= AppConstants.locationBatchSize) {
        final toFlush = List<Map<String, dynamic>>.from(pendingBatch);
        pendingBatch.clear();
        await flushBatch(toFlush);
      }

      // Update distance every 15 min
      if (lastDistanceUpdate == null ||
          DateTime.now().difference(lastDistanceUpdate!).inMinutes >=
              AppConstants.distanceCalculationMinutes) {
        lastDistanceUpdate = DateTime.now();
        await updateDistance(pendingBatch);
      }
    } catch (_) {}
  }

  // Sample every 5 minutes
  samplingTimer = Timer.periodic(
    Duration(seconds: AppConstants.locationSamplingSeconds),
    (_) => collectLocation(),
  );

  // Immediate first sample
  collectLocation();

  service.on('stopTracking').listen((_) async {
    samplingTimer?.cancel();
    if (pendingBatch.isNotEmpty) {
      await flushBatch(pendingBatch);
      await updateDistance(pendingBatch);
    }
    service.stopSelf();
  });
}
