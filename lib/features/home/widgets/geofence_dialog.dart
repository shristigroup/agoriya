import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum GeofenceChoice { carryOn, openMaps }

/// "You seem to be far from the place." Returns what the user chose; null if
/// they dismissed it (treated as not carrying on).
Future<GeofenceChoice?> showGeofenceDialog(
  BuildContext context, {
  required int distanceM,
  required String placeName,
}) {
  final distance =
      distanceM >= 1000 ? '${(distanceM / 1000).toStringAsFixed(1)} km' : '$distanceM m';
  return showDialog<GeofenceChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('You seem far from $placeName'),
      content: Text(
        'Your phone puts you about $distance away. If that looks wrong, open '
        'Google Maps to see where your phone thinks you are, then come back '
        'and try again. If it is right, you can carry on; your manager will '
        'be told.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, GeofenceChoice.openMaps),
          child: const Text('Open Google Maps'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, GeofenceChoice.carryOn),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
}

Future<void> openGoogleMaps() async {
  try {
    await launchUrl(Uri.parse('https://www.google.com/maps'),
        mode: LaunchMode.externalApplication);
  } catch (_) {}
}
