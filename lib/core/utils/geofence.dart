import 'dart:math' as math;

import '../../data/models/shift_model.dart';

enum GeoVerdict {
  /// Within the radius (or near enough, given the position's accuracy).
  ok,

  /// Farther than the radius: ask the user before going on.
  warn,

  /// Nothing to compare (no location set, or no recent position): no warning.
  skip,
}

class GeoResult {
  final GeoVerdict verdict;
  final double? distanceM;
  const GeoResult(this.verdict, [this.distanceM]);
}

/// Distance and the warn / skip decision for a punch-in or punch-out.
class Geofence {
  /// A position older than this is not trusted (the user may have moved).
  static const Duration maxAge = Duration(minutes: 30);

  static double distanceMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadius * math.asin(math.min(1, math.sqrt(a)));
  }

  /// Compares the user's last known position with [target].
  /// The position's accuracy gives the user the benefit of the doubt: they
  /// are warned only if even the closest they could be is outside the radius.
  static GeoResult check({
    required ShiftLocation? target,
    required int radiusM,
    required double? lat,
    required double? lng,
    double? accuracyM,
    Duration? age,
  }) {
    if (target == null || lat == null || lng == null) {
      return const GeoResult(GeoVerdict.skip);
    }
    if (age != null && age > maxAge) return const GeoResult(GeoVerdict.skip);
    final distance = distanceMeters(lat, lng, target.lat, target.lng);
    final closest = distance - (accuracyM ?? 0);
    return GeoResult(
        closest > radiusM ? GeoVerdict.warn : GeoVerdict.ok, distance);
  }
}
