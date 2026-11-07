import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/utils/app_utils.dart';
import '../data/local/local_storage_service.dart';

/// "Report auto punch-out": opens WhatsApp to the support number with a short
/// pre-filled message. Device, OS, app build and permission details are NOT
/// repeated here — they are already on the user's Users doc (written at login
/// and refreshed at every punch-in by DeviceInfoService), so support only
/// needs to know who this is and when it happened, then can look the rest up
/// and decide whether to set `autoPunchOutDisabled`.
class AutoPunchOutReport {
  static const supportWhatsAppNumber = '919538384545';

  static String buildMessage({DateTime? autoPunchedOutAt}) {
    final user = LocalStorageService.getUser();
    return [
      'TrackFolks auto punch-out report',
      if (user != null) 'Name: ${user.fullName}',
      if (user != null) 'Phone: ${user.phoneNumber}',
      if (user != null) 'User ID: ${user.id}',
      if (autoPunchedOutAt != null)
        'Auto punched out: ${AppUtils.formatDate(autoPunchedOutAt)} '
            '${AppUtils.formatTime(autoPunchedOutAt)}',
    ].join('\n');
  }

  /// Opens WhatsApp with the message ready to send. Returns false (and shows
  /// a snackbar) if WhatsApp can't be opened.
  static Future<bool> open(BuildContext context,
      {DateTime? autoPunchedOutAt}) async {
    final text = buildMessage(autoPunchedOutAt: autoPunchedOutAt);
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
