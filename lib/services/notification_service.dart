import 'dart:convert';
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import '../firebase_options.dart';
import 'location_tracking_service.dart';

// Top-level FCM background handler (required to be top-level, and a
// separate isolate entry point on Android — needs its own plugin/Firebase
// init, same pattern as location_tracking_service.dart's _onStart).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (message.data['type'] != 'location_wakeup') return;

  final userId = message.data['userId'] as String?;
  final date = message.data['date'] as String?;
  if (userId == null || date == null) return;

  DartPluginRegistrant.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }

  // This handler runs in its own headless isolate (Android may spin up a
  // fresh process for it), which never ran the app's normal main() — so the
  // background-service plugin config (onStart callback, notification
  // channel, etc.) needs to be (re-)registered here before start() can work.
  await LocationTrackingService.initialize();

  // Server-side watchdog only sends this when the tracking session is still
  // punched-in and stale — just restart the service; LocationTrackingService
  // handles the "already running" case as a no-op param update.
  await LocationTrackingService.start(userId, date);
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
