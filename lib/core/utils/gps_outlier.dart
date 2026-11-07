import 'package:latlong2/latlong.dart';
import '../constants/app_constants.dart';
import 'app_utils.dart';

/// Stray-GPS-fix detection by speed.
///
/// A fix B between its neighbours A (before) and C (after) is a *spike* when
/// both legs are long and the speed into B and out of B are each much higher
/// than the speed of going straight from A to C. A rider genuinely moving in a
/// line has the same speed on all three, so is never flagged; a stray that
/// jumps out and back (or that sits far off the path actually travelled) makes
/// both legs look several times faster than the real route.
///
/// Times matter: samples are not evenly spaced, and a leg that took a long time
/// is a slow leg. Deliberately NOT an absolute speed limit — riders reach
/// 60+ km/h legitimately — and no minimum speed: the shape (a detour several
/// times longer than the direct line) is what identifies a stray.
class GpsOutlier {
  const GpsOutlier._();

  /// True if [b] looks like a spike between [a] and [c].
  ///
  /// [ab] and [bc] are the travel times A→B and B→C. For A→B that is the time
  /// from when the rider left A (A's timestamp plus any stationary duration)
  /// to B. A non-positive time means the speed can't be judged, so: not a spike.
  static bool isSpike(
    LatLng a,
    LatLng b,
    LatLng c, {
    required Duration ab,
    required Duration bc,
    double minLegMeters = AppConstants.outlierMinLegMeters,
    double speedRatio = AppConstants.outlierSpeedRatio,
  }) {
    final tAB = ab.inMilliseconds, tBC = bc.inMilliseconds;
    if (tAB <= 0 || tBC <= 0) return false;

    final dAB = AppUtils.haversineMeters(a, b);
    final dBC = AppUtils.haversineMeters(b, c);
    if (dAB <= minLegMeters || dBC <= minLegMeters) return false;
    final dAC = AppUtils.haversineMeters(a, c);

    // speed(A→B) > ratio × speed(A→C)  ⇔  dAB/tAB > ratio × dAC/(tAB+tBC),
    // written without division.
    final tAC = tAB + tBC;
    return dAB * tAC > speedRatio * dAC * tAB &&
        dBC * tAC > speedRatio * dAC * tBC;
  }
}
