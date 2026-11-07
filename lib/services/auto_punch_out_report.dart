import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/utils/app_utils.dart';
import '../data/local/local_storage_service.dart';
import 'device_info_service.dart';
import 'oem_settings_service.dart';

/// "Report auto punch-out": opens WhatsApp to the support number with a
/// pre-filled message carrying everything needed to diagnose the phone, so
/// support can decide whether to set `autoPunchOutDisabled` for the user.
class AutoPunchOutReport {
  static const supportWhatsAppNumber = '919538384545';

  static Future<String> buildMessage({DateTime? autoPunchedOutAt}) async {
    final user = LocalStorageService.getUser();
    final info = await DeviceInfoService.collect();
    final oemAt = OemSettingsService.confirmedAt;

    String yn(dynamic v) => v == null ? '?' : (v == true ? 'yes' : 'no');

    final lines = <String>[
      'TrackFolks auto punch-out report',
      '',
      if (user != null) 'Name: ${user.fullName}',
      if (user != null) 'Phone: ${user.phoneNumber}',
      if (user != null) 'User ID: ${user.id}',
      if (autoPunchedOutAt != null)
        'Auto punched out: ${AppUtils.formatDate(autoPunchedOutAt)} ${AppUtils.formatTime(autoPunchedOutAt)}',
      '',
      'App: ${info['appVersion'] ?? '?'} (build ${info['appBuild'] ?? '?'}) ${info['platform'] ?? ''}',
      'Device: ${info['deviceManufacturer'] ?? '?'} ${info['deviceModel'] ?? ''}',
      'OS: ${info['osVersion'] ?? '?'}${info['sdkInt'] != null ? ' (SDK ${info['sdkInt']})' : ''}',
      'Location: ${info['locationPermission'] ?? '?'}',
      'Notifications: ${yn(info['notificationsGranted'])}',
      if (info.containsKey('batteryOptimizationExempt'))
        'Battery exemption: ${yn(info['batteryOptimizationExempt'])}',
      if (info.containsKey('backgroundRestricted'))
        'Background restricted: ${yn(info['backgroundRestricted'])}',
      if (info.containsKey('standbyBucket'))
        'Standby bucket: ${info['standbyBucket']}',
      if (info.containsKey('backgroundRefresh'))
        'Background App Refresh: ${info['backgroundRefresh']}',
      if (info.containsKey('lowPowerMode'))
        'Low Power Mode: ${yn(info['lowPowerMode'])}',
      if (info.containsKey('locationAccuracy'))
        'Location accuracy: ${info['locationAccuracy']}',
      'Phone-brand settings guide confirmed: '
          '${oemAt == null ? 'no' : oemAt.toIso8601String().substring(0, 10)}',
    ];
    return lines.join('\n');
  }

  /// Opens WhatsApp with the message ready to send. Returns false (and shows
  /// a snackbar) if WhatsApp can't be opened.
  static Future<bool> open(BuildContext context,
      {DateTime? autoPunchedOutAt}) async {
    final text = await buildMessage(autoPunchedOutAt: autoPunchedOutAt);
    final uri = Uri.parse(
        'https://wa.me/$supportWhatsAppNumber?text=${Uri.encodeComponent(text)}');
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return true;
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not open WhatsApp. Please message +91 95383 84545.'),
      ));
    }
    return false;
  }
}
