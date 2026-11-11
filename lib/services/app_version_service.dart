import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// The server refused a punch-in because this app build is below the
/// minimum it will accept (Config/app → minBuild, see functions checkAppVersion).
class AppUpdateRequired implements Exception {
  final String message;
  final String? storeUrl;
  const AppUpdateRequired(this.message, this.storeUrl);

  @override
  String toString() => message;
}

class AppVersionService {
  static const _checkUrl =
      'https://asia-south1-agoriya-app.cloudfunctions.net/checkAppVersion';

  /// Page with the Play Store and TestFlight / App Store buttons. Used for the
  /// update push, and as the fallback when the server sends no store link.
  static const downloadPageUrl = 'https://tf.shristigroup.com/#download';

  static String get _platform => Platform.isIOS ? 'ios' : 'android';

  /// Asks the server whether this build may punch in. Returns null when it
  /// may — and also when the check itself can't be completed (no network,
  /// timeout, server error): field staff must never be blocked from working
  /// because of a connectivity problem. Returns [AppUpdateRequired] only on
  /// the server's explicit 426 `update_required` answer.
  static Future<AppUpdateRequired?> checkPunchInAllowed() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber);
      if (build == null) return null;

      final response = await http
          .post(
            Uri.parse(_checkUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'platform': _platform, 'buildNumber': build}),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 426) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['code'] != 'update_required') return null;
      return AppUpdateRequired(
        (body['message'] as String?) ??
            'A newer version of TrackFolks is required to punch in.',
        body['storeUrl'] as String?,
      );
    } catch (e) {
      print('[AppVersion] check skipped: $e');
      return null;
    }
  }

  /// Opens the store page for the "update required" dialog. [url] is the
  /// server-provided link; without one, the download page (which has both
  /// stores' buttons) is opened.
  static Future<void> openStore([String? url]) async {
    final target = url ?? downloadPageUrl;
    try {
      await launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication);
    } catch (e) {
      print('[AppVersion] could not open store: $e');
    }
  }

  /// Tap handler for the one-time `app_update` push: opens the download page
  /// (or the push's own `url`) so the user picks the right button there.
  static Future<void> openDownloadPage(Map<String, dynamic> data) {
    final url = data['url'] as String?;
    return openStore((url == null || url.isEmpty) ? null : url);
  }

  /// Blocking "update required" dialog — no dismiss, the only way forward is
  /// the store (or backing out of the punch-in).
  static Future<void> showUpdateRequiredDialog(
      BuildContext context, AppUpdateRequired update) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Update required'),
          content: Text(
            '${update.message}\n\nPlease update TrackFolks from the '
            '${Platform.isIOS ? 'App Store' : 'Play Store'} and try again.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => openStore(update.storeUrl),
              child: const Text('Update now'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
