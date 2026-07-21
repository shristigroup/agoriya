import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

class AppUtils {
  /// Distance in metres between two LatLng points.
  static double haversineMeters(LatLng a, LatLng b) {
    const r = 6371000.0; // Earth radius in metres
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(a.latitude)) *
            math.cos(_rad(b.latitude)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  static double _rad(double deg) => deg * math.pi / 180;

  static String formatDate(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);
  static String formatDateDisplay(DateTime dt) => DateFormat('dd MMM yyyy').format(dt);
  static String formatTime(DateTime dt) => DateFormat('hh:mm a').format(dt);
  static String formatDateTime(DateTime dt) => DateFormat('dd MMM, hh:mm a').format(dt);

  static String formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }

  static String formatDistance(double km) {
    if (km < 1) return '${(km * 1000).toStringAsFixed(0)}m';
    return '${km.toStringAsFixed(1)}km';
  }

  static String todayKey() => formatDate(DateTime.now());

  static String visitDocId(String clientName, String location, DateTime checkinTime) {
    final datePart = formatDate(checkinTime);
    final timePart = DateFormat('HH:mm:ss').format(checkinTime);
    final safeName = clientName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-');
    final safeLoc = location.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-');
    return '$safeName-$safeLoc-$datePart-$timePart';
  }

  static String userDocId(String firstName, String lastName, String phone) {
    return '${firstName.toLowerCase()}-${lastName.toLowerCase()}-$phone';
  }

  static String getInitials(String fullName) {
    final parts = fullName.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
