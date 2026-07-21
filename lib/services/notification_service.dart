import 'dart:convert';
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import '../firebase_options.dart';
import 'location_sync_service.dart';

// Top-level FCM background handler (required to be top-level, and a
// separate isolate entry point on Android — needs its own plugin/Firebase
// init, same pattern as location_tracking_service.dart's _onStart).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('[FCM] Background message received | data=${message.data}');

  if (message.data['type'] != 'location_wakeup') {
    print('[FCM] Ignoring — type is not location_wakeup');
    return;
  }

  final userId = message.data['userId'] as String?;
  final date = message.data['date'] as String?;
  final trackingId = message.data['trackingId'] as String?;
  if (userId == null || date == null || trackingId == null) {
    print('[FCM] location_wakeup missing userId/date/trackingId — ignoring '
        '(data=${message.data})');
    return;
  }

  print('[FCM] location_wakeup → restarting tracking '
      '| userId=$userId date=$date trackingId=$trackingId');

  try {
    DartPluginRegistrant.ensureInitialized();
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }

    // Ensures the background-service plugin is initialized + the tracking
    // isolate is running (this handler is its own fresh engine, which
    // never ran the app's normal main(), so initialize() must happen here
    // too — before start() can work) and syncs any pending batch to
    // Firestore. See LocationSyncService.ensureRunningAndSync for exactly
    // what is/isn't parallelized internally. Safe to call even if the
    // service was already alive: start() no-ops to a param update, and the
    // sync is guarded by LocationsBoxLock so it backs off cleanly if the
    // main app turns out to be alive after all.
    final result = await LocationSyncService.ensureRunningAndSync(
      userId: userId,
      date: date,
      trackingId: trackingId,
    );
    if (result != null) {
      print('[FCM] Pending batch synced from background handler '
          '| ${result.finalLocations.length} points, '
          '${result.finalLocationsDistance.toStringAsFixed(3)} km');
    }

    print('[FCM] location_wakeup handled successfully');
  } catch (e, st) {
    print('[FCM] location_wakeup error: $e\n$st');
  }
}

class NotificationService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'trackfolks_notifications',
    'TrackFolks Notifications',
    description: 'Notifications for TrackFolks activities',
    importance: Importance.high,
  );

  /// Called by the app to navigate on notification tap.
  /// Receives a decoded Map<String, dynamic> of FCM data.
  static Function(Map<String, dynamic> data)? onNotificationTap;

  static Future<void> initialize() async {
    // Register background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifications.initialize(
      const InitializationSettings(
          android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: (details) {
        if (details.payload != null) {
          try {
            final data =
                Map<String, dynamic>.from(jsonDecode(details.payload!));
            onNotificationTap?.call(data);
          } catch (_) {}
        }
      },
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Foreground FCM
    FirebaseMessaging.onMessage.listen((message) {
      _showLocalNotification(message);
    });

    // App opened from background via notification tap
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      onNotificationTap?.call(message.data);
    });

    // App launched from terminated state via notification tap
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onNotificationTap?.call(initial.data);
      });
    }
  }

  static Future<bool> requestPermission() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  static Future<AuthorizationStatus> getPermissionStatus() async {
    final settings = await _fcm.getNotificationSettings();
    return settings.authorizationStatus;
  }

  static Future<String?> getToken() async {
    return await _fcm.getToken();
  }

  static void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      // Encode data as JSON string for payload
      payload: jsonEncode(message.data),
    );
  }
}
