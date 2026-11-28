import '../../data/models/shift_model.dart';
import 'geofence.dart';
import 'shift_time.dart';

/// The phone's last known position, and how old it is.
class KnownPosition {
  final double lat;
  final double lng;
  final double? accuracyM;
  final Duration age;
  const KnownPosition(
      {required this.lat, required this.lng, this.accuracyM, required this.age});
}

/// What a punch-in or punch-out looks like against the user's shift.
class ShiftCheck {
  final GeoResult geo;
  final int lateMinutes;
  final int earlyMinutes;
  final ShiftLocation? target;

  const ShiftCheck({
    required this.geo,
    required this.lateMinutes,
    required this.earlyMinutes,
    required this.target,
  });

  /// The user is farther than the radius: ask before going on.
  bool get needsWarning => geo.verdict == GeoVerdict.warn;

  /// The record kept on the session (and shown to the manager), or null when
  /// there is nothing unusual. The distance is recorded only if the user was
  /// warned and carried on.
  Map<String, dynamic>? anomaly({required bool warnedAndContinued}) {
    final map = <String, dynamic>{
      if (lateMinutes > 0) 'lateMinutes': lateMinutes,
      if (earlyMinutes > 0) 'earlyMinutes': earlyMinutes,
      if (warnedAndContinued && geo.distanceM != null) ...{
        'distanceM': geo.distanceM!.round(),
        'locationName': target?.name ?? '',
      },
    };
    return map.isEmpty ? null : map;
  }
}

ShiftCheck evaluateShift({
  required ShiftModel shift,
  required bool isPunchIn,
  required DateTime now,
  KnownPosition? position,
}) {
  final target = isPunchIn ? shift.inLocation : shift.effectiveOutLocation;
  final geo = Geofence.check(
    target: target,
    radiusM: shift.radiusM,
    lat: position?.lat,
    lng: position?.lng,
    accuracyM: position?.accuracyM,
    age: position?.age,
  );
  return ShiftCheck(
    geo: geo,
    lateMinutes: isPunchIn ? ShiftTime.lateMinutes(shift, now) : 0,
    earlyMinutes: isPunchIn ? 0 : ShiftTime.earlyMinutes(shift, now),
    target: target,
  );
}
