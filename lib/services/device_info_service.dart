import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../data/repositories/firestore_repository.dart';
import 'oem_settings_service.dart';

/// Records which app build / device / permission state each user is on, at
/// the Users-doc level. Used to (a) tell old builds from new when looking at
/// auto punch-outs, (b) spot OEM / OS patterns, and (c) pick who gets the
/// one-time "please update" push (scripts/notify_app_update.js). The same
/// snapshot is attached to the "report auto punch-out" WhatsApp message.
class DeviceInfoService {
  static const _iosDiag = MethodChannel('com.agoriya.app/ios_diag');
  static String? _reportedFor;

  /// Plain-value snapshot (no server timestamps). Never throws — fields that
  /// can't be read are simply left out.
  static Future<Map<String, dynamic>> collect() async {
    final data = <String, dynamic>{};
    try {
      final pkg = await PackageInfo.fromPlatform();
      data['appVersion'] = pkg.version;
      data['appBuild'] = int.tryParse(pkg.buildNumber);
      data['platform'] = Platform.isIOS ? 'ios' : 'android';

      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await plugin.androidInfo;
        data['deviceManufacturer'] = a.manufacturer;
        data['deviceModel'] = a.model;
        data['osVersion'] = a.version.release;
        data['sdkInt'] = a.version.sdkInt;
        data['batteryOptimizationExempt'] =
            await Permission.ignoreBatteryOptimizations.isGranted;
        // Read-only: "Restricted" background mode and the standby bucket
        // (10 active, 20 working set, 30 frequent, 40 rare, 45 restricted).
        data.addAll(await OemSettingsService.backgroundState());
      } else if (Platform.isIOS) {
        final i = await plugin.iosInfo;
        data['deviceManufacturer'] = 'Apple';
        data['deviceModel'] = i.utsname.machine;
        data['osVersion'] = i.systemVersion;
        try {
          final diag = await _iosDiag.invokeMapMethod<String, dynamic>('state');
          if (diag != null) {
            data['backgroundRefresh'] = diag['backgroundRefresh'];
            data['lowPowerMode'] = diag['lowPowerMode'];
          }
        } catch (_) {}
        try {
          data['locationAccuracy'] =
              (await Geolocator.getLocationAccuracy()) ==
                      LocationAccuracyStatus.precise
                  ? 'precise'
                  : 'reduced';
        } catch (_) {}
      }

      data['locationPermission'] = await Permission.locationAlways.isGranted
          ? 'always'
          : (await Permission.locationWhenInUse.isGranted
              ? 'whileInUse'
              : 'denied');
      data['notificationsGranted'] = await Permission.notification.isGranted;
    } catch (e) {
      print('[DeviceInfo] collect failed: $e');
    }
    return data;
  }

  /// Writes the snapshot at most once per process per user unless [force] —
  /// the auth builder that calls this rebuilds often. Never throws: this is
  /// diagnostics and must not affect login or punch-in.
  static Future<void> report(String userId, {bool force = false}) async {
    if (!force && _reportedFor == userId) return;
    _reportedFor = userId;
    try {
      final data = await collect();
      data['appInfoUpdatedAt'] = FieldValue.serverTimestamp();
      await FirestoreRepository().updateDeviceInfo(userId, data);
    } catch (e) {
      print('[DeviceInfo] report failed: $e');
    }
  }
}
