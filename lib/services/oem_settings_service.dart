import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/local/local_storage_service.dart';
import '../data/repositories/firestore_repository.dart';

/// Phone brands whose ROMs kill background apps unless the user whitelists
/// them in a vendor-specific screen. Android offers no API to READ those
/// settings, so the flow is: explain → open the screen → on return ask the
/// user to confirm → remember the confirmation. A later auto punch-out after
/// that confirmation brings the guide back (see [shouldShowGuide]).
class OemBrand {
  final String name;
  final List<String> steps;
  final bool hasBatterySaverScreen; // Xiaomi/HyperOS only
  const OemBrand(this.name, this.steps, {this.hasBatterySaverScreen = false});
}

class OemSettingsService {
  static const _channel = MethodChannel('com.agoriya.app/oem');
  static const _confirmedAtKey = 'oem_setup_confirmed_at';

  static const _xiaomi = OemBrand(
    'Xiaomi / Redmi / POCO',
    [
      'Turn ON "Autostart" for TrackFolks.',
      'Open Battery saver and choose "No restrictions" for TrackFolks.',
      'Open the recent-apps screen and lock TrackFolks (long-press its card → Lock).',
    ],
    hasBatterySaverScreen: true,
  );
  static const _oppo = OemBrand('Oppo / Realme / OnePlus', [
    'Allow "Auto-launch" / "Startup" for TrackFolks.',
    'In Battery settings, allow background activity for TrackFolks.',
  ]);
  static const _vivo = OemBrand('Vivo / iQOO', [
    'Allow "Autostart" / "Background startup" for TrackFolks.',
    'In Battery settings, allow high background power use for TrackFolks.',
  ]);
  static const _huawei = OemBrand('Huawei / Honor', [
    'Open App launch → TrackFolks → Manage manually.',
    'Turn ON Auto-launch, Secondary launch and Run in background.',
  ]);
  static const _samsung = OemBrand('Samsung', [
    'Open Battery → Background usage limits.',
    'Remove TrackFolks from "Sleeping apps" and "Deep sleeping apps".',
    'Add TrackFolks to "Never sleeping apps".',
  ]);
  static const _transsion = OemBrand('Infinix / Tecno / itel', [
    'Turn ON "Autostart" for TrackFolks.',
    'Allow TrackFolks to run in the background in the battery settings.',
  ]);

  static OemBrand? _brandFor(String manufacturer) {
    switch (manufacturer) {
      case 'xiaomi':
      case 'redmi':
      case 'poco':
        return _xiaomi;
      case 'oppo':
      case 'realme':
      case 'oneplus':
        return _oppo;
      case 'vivo':
      case 'iqoo':
        return _vivo;
      case 'huawei':
      case 'honor':
        return _huawei;
      case 'samsung':
        return _samsung;
      case 'infinix':
      case 'tecno':
      case 'itel':
        return _transsion;
    }
    return null;
  }

  /// The brand profile for this phone, or null (stock Android, iOS, unknown
  /// brand) — in which case no guide is needed.
  static Future<OemBrand?> detectBrand() async {
    if (!Platform.isAndroid) return null;
    try {
      final m = await _channel.invokeMethod<String>('manufacturer');
      return m == null ? null : _brandFor(m);
    } catch (_) {
      return null;
    }
  }

  static DateTime? get confirmedAt {
    final s = LocalStorageService.getSetting<String>(_confirmedAtKey);
    return s == null ? null : DateTime.tryParse(s);
  }

  /// Show the guide when the user hasn't confirmed yet, or when a session was
  /// auto-closed AFTER their last confirmation (it didn't work — go again).
  /// [lastAutoClosedAt] is the stop time of the latest session if the server
  /// auto-closed it, else null.
  static Future<OemBrand?> brandIfGuideNeeded({DateTime? lastAutoClosedAt}) async {
    final brand = await detectBrand();
    if (brand == null) return null;
    final confirmed = confirmedAt;
    if (confirmed == null) return brand;
    if (lastAutoClosedAt != null && lastAutoClosedAt.isAfter(confirmed)) {
      return brand;
    }
    return null;
  }

  /// "opened" | "fallback" | "failed". [kind] is "autostart" or "battery".
  static Future<String> openSettings(String kind) async {
    try {
      return await _channel
              .invokeMethod<String>('openSettings', {'kind': kind}) ??
          'failed';
    } catch (_) {
      return 'failed';
    }
  }

  /// {backgroundRestricted: bool?, standbyBucket: int?} — read-only.
  static Future<Map<String, dynamic>> backgroundState() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('backgroundState');
      return {
        if (m?['backgroundRestricted'] != null)
          'backgroundRestricted': m!['backgroundRestricted'],
        if (m?['standbyBucket'] != null) 'standbyBucket': m!['standbyBucket'],
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> _recordConfirmation(String userId, OemBrand brand) async {
    final now = DateTime.now();
    await LocalStorageService.setSetting(_confirmedAtKey, now.toIso8601String());
    try {
      await FirestoreRepository().updateDeviceInfo(userId, {
        'oemSetupConfirmedAt': FieldValue.serverTimestamp(),
        'oemSetupConfirmCount': FieldValue.increment(1),
        'oemSetupBrand': brand.name,
      });
    } catch (e) {
      print('[OemSettings] could not record confirmation: $e');
    }
  }

  /// Shows the guide. Never blocks punch-in: the caller proceeds either way.
  static Future<void> showGuide(
      BuildContext context, String userId, OemBrand brand) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OemGuideDialog(brand: brand),
    );
    if (confirmed == true) await _recordConfirmation(userId, brand);
  }
}

class _OemGuideDialog extends StatefulWidget {
  final OemBrand brand;
  const _OemGuideDialog({required this.brand});

  @override
  State<_OemGuideDialog> createState() => _OemGuideDialogState();
}

class _OemGuideDialogState extends State<_OemGuideDialog>
    with WidgetsBindingObserver {
  // 0 = explain, 1 = settings opened (waiting for the user to come back),
  // 2 = back from settings: ask for confirmation.
  int _phase = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _phase == 1 && mounted) {
      setState(() => _phase = 2);
    }
  }

  Future<void> _open(String kind) async {
    setState(() => _phase = 1);
    final result = await OemSettingsService.openSettings(kind);
    // Nothing opened (or it opened the generic app page): the user may not
    // leave the app, so go straight to the question.
    if (result == 'failed' && mounted) setState(() => _phase = 2);
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.brand.steps
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join('\n');

    if (_phase == 2) {
      return AlertDialog(
        title: const Text('Did you turn these on?'),
        content: Text(steps),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not yet'),
          ),
          TextButton(
            onPressed: () => _open('autostart'),
            child: const Text('Open again'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, done'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Keep tracking running'),
      content: SingleChildScrollView(
        child: Text(
          'On ${widget.brand.name} phones, the system can stop TrackFolks in '
          'the background, which punches you out automatically.\n\n'
          'Why we ask: TrackFolks records your location only while you are '
          'punched in, and these phone settings let it keep doing that when '
          'the screen is off. They do not give TrackFolks access to any '
          'other data, and you can change them back anytime in Settings.\n\n'
          'Please change these settings:\n\n$steps',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Later'),
        ),
        if (widget.brand.hasBatterySaverScreen)
          TextButton(
            onPressed: () => _open('battery'),
            child: const Text('Battery saver'),
          ),
        ElevatedButton(
          onPressed: () => _open('autostart'),
          child: Text(widget.brand.hasBatterySaverScreen
              ? 'Autostart'
              : 'Open settings'),
        ),
      ],
    );
  }
}
