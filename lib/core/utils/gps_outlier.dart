import 'package:latlong2/latlong.dart';
import '../constants/app_constants.dart';
import 'app_utils.dart';

/// Simple stray-GPS-fix detection.
///
/// A fix B is a *spike* when the track jumps far out to B and comes straight
/// back: B is far from both neighbours (A before it, C after it) while A and C
/// are close to each other. Deliberately NOT a speed rule — someone who has
/// been stationary and starts moving produces A, B, C in a line (A and C far
/// apart), so it is never flagged.
class GpsOutlier {
  const GpsOutlier._();

  /// True if [b] looks like a spike between [a] and [c].
  static bool isSpike(
    LatLng a,
    LatLng b,
    LatLng c, {
    double minLegMeters = AppConstants.outlierMinLegMeters,
    double returnRatio = AppConstants.outlierReturnRatio,
  }) {
    final ab = AppUtils.haversineMeters(a, b);
    final bc = AppUtils.haversineMeters(b, c);
    if (ab <= minLegMeters || bc <= minLegMeters) return false;
    final ac = AppUtils.haversineMeters(a, c);
    return ac < returnRatio * (ab < bc ? ab : bc);
  }

  /// True if getting from [from] to [to] is a jump big enough that [to] can't
  /// be trusted until a following sample confirms it (used to hold the last
  /// point of a batch back from syncing).
  static bool isJump(
    LatLng from,
    LatLng to, {
    double minLegMeters = AppConstants.outlierMinLegMeters,
  }) =>
      AppUtils.haversineMeters(from, to) > minLegMeters;
}
