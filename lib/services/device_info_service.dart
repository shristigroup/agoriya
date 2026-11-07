import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../data/repositories/firestore_repository.dart';

/// Records which app build / device / permission state each user is on, at
/// the Users-doc level. Used to (a) tell old builds from new when looking at
/// auto punch-outs, (b) spot OEM / OS patterns, and (c) pick who gets the
/// one-time "please update" push (scripts/notify_app_update.js).
class DeviceInfoService {
  static String? _reportedFor;

  /// Writes the info at most once per process per user unless [force] —
  /// the auth builder that calls this rebuilds often. Never throws: this is
  /// diagnostics and must not affect login or punch-in.
  static Future<void> report(String userId, {bool force = false}) async {
    if (!force && _reportedFor == userId) return;
    _reportedFor = userId;
    try {
      final pkg = await PackageInfo.fromPlatform();
      final data = <String, dynamic>{
        'appVersion': pkg.version,
        'appBuild': int.tryParse(pkg.buildNumber),
        'platform': Platform.isIOS ? 'ios' : 'android',
        'appInfoUpdatedAt': FieldValue.serverTimestamp(),
      };

      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await plugin.androidInfo;
        data['deviceManufacturer'] = a.manufacturer;
        data['deviceModel'] = a.model;
        data['osVersion'] = a.version.release;
        data['sdkInt'] = a.version.sdkInt;
        data['batteryOptimizationExempt'] =
            await Permission.ignoreBatteryOptimizations.isGranted;
      } else if (Platform.isIOS) {
        final i = await plugin.iosInfo;
        data['deviceManufacturer'] = 'Apple';
        data['deviceModel'] = i.utsname.machine;
        data['osVersion'] = i.systemVersion;
      }

      data['locationPermission'] = await Permission.locationAlways.isGranted
          ? 'always'
          : (await Permission.locationWhenInUse.isGranted
              ? 'whileInUse'
              : 'denied');
      data['notificationsGranted'] = await Permission.notification.isGranted;

      await FirestoreRepository().updateDeviceInfo(userId, data);
    } catch (e) {
      print('[DeviceInfo] report failed: $e');
    }
  }
}
