import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:agoriya/core/utils/app_utils.dart';
import 'package:agoriya/core/utils/gps_outlier.dart';

/// Real GPS triples (A, B, C) taken from production tracking data (raw,
/// unsnapped points only), anonymised: each is stored as east/north metre
/// offsets from its own first point, so the geometry is exact but the place is
/// not recoverable. [ab]/[bc]/[ac] are the leg lengths measured at extraction
/// time and are re-checked below so a bad fixture can't pass silently.
class _Case {
  final bool spike;
  final int ab, bc, ac;
  final List<double> a, b, c; // [east m, north m]

  /// Seconds from A to B and from B to C. The older fixtures were extracted
  /// without times, so they carry the 60 s sampling interval as a stand-in;
  /// the newer ones carry the real gaps.
  final int dtAb, dtBc;
  const _Case(this.spike, this.ab, this.bc, this.ac, this.a, this.b, this.c,
      {this.dtAb = 60, this.dtBc = 60});
}

const _lat0 = 12.9, _lon0 = 77.6;
LatLng _p(List<double> o) => LatLng(
      _lat0 + o[1] / 111320.0,
      _lon0 + o[0] / (111320.0 * math.cos(_lat0 * math.pi / 180)),
    );

const _cases = <_Case>[
  // Flagged by the extraction rule: far from both neighbours that sit close
  // together (production strays).
    _Case(true, 728, 746, 166, [0.0, 0.0], [-710.8, -161.5], [35.5, -162.7]),
    _Case(true, 366, 369, 9, [0.0, 0.0], [366.4, 17.1], [-2.4, -8.2]),
    _Case(true, 710, 695, 27, [0.0, 0.0], [431.4, 564.9], [27.2, -1.8]),
    _Case(true, 461, 457, 5, [0.0, 0.0], [459.6, -41.1], [4.5, 1.7]),
    _Case(true, 937, 1236, 307, [0.0, 0.0], [926.4, -145.7], [-305.8, -29.7]),
    _Case(true, 923, 964, 123, [0.0, 0.0], [888.5, 253.3], [0.0, -123.5]),
    _Case(true, 413, 358, 79, [0.0, 0.0], [-274.6, -309.4], [0.4, -79.1]),
    _Case(true, 581, 581, 0, [0.0, 0.0], [220.7, 538.5], [0.0, 0.0]),
    _Case(true, 658, 658, 0, [0.0, 0.0], [-562.0, 342.9], [0.0, 0.0]),
    _Case(true, 461, 464, 3, [0.0, 0.0], [459.8, -44.8], [-2.8, -1.5]),
  // Moving straight on: both legs long but A and C far apart — must be kept.
    _Case(false, 608, 541, 1142, [0.0, 0.0], [516.2, 321.8], [903.5, 701.1]),
    _Case(false, 392, 341, 724, [0.0, 0.0], [-168.8, 354.2], [-402.7, 602.7]),
    _Case(false, 463, 369, 797, [0.0, 0.0], [-135.8, -443.1], [-420.8, -677.6]),
  // Partial returns (a turn / loop that ends part-way back). Kept by the old
  // "came straight back" rule, but dropped by the speed rule: the path through
  // B is several times longer than the route A→C. Accepted trade-off — one
  // stray left in costs kilometres of false distance, one real turn dropped
  // costs a few hundred metres.
    _Case(true, 480, 315, 170, [0.0, 0.0], [230.9, 421.8], [106.7, 132.0]),
    _Case(true, 770, 1190, 419, [0.0, 0.0], [715.9, 286.9], [-393.8, -145.5]),
    _Case(true, 391, 501, 138, [0.0, 0.0], [390.7, -20.4], [-106.6, -88.0]),
  // Nov 2026 session (Android, rider). Raw/unsnapped points, real timestamps.
  // The stray is a stale fix that repeated a position from 20 minutes earlier;
  // because the rider was moving, A and C are 531 m apart (not "straight
  // back"), which the distance-only rule does not catch.
    _Case(true, 1065, 1589, 531, [0.0, 0.0], [698.9, 805.7], [-257.8, -464.8], dtAb: 60, dtBc: 61),
  // Same session: genuine movement around the stray — must be kept.
    _Case(false, 340, 711, 771, [0.0, 0.0], [338.7, -35.1], [226.7, -737.6], dtAb: 60, dtBc: 122),
    _Case(false, 408, 387, 794, [0.0, 0.0], [-20.8, -408.1], [-77.1, -791.5], dtAb: 60, dtBc: 60),
  // The point right after the stray, judged against the last good point.
    _Case(false, 531, 192, 723, [0.0, 0.0], [-257.8, -464.8], [-345.4, -635.8], dtAb: 121, dtBc: 59),
];

void main() {
  group('GpsOutlier on real production triples', () {
    for (var i = 0; i < _cases.length; i++) {
      final c = _cases[i];
      final a = _p(c.a), b = _p(c.b), cc = _p(c.c);

      test('#${i + 1} fixture geometry matches the measured legs', () {
        double near(double got, int want) => (got - want).abs() / want;
        expect(near(AppUtils.haversineMeters(a, b), c.ab), lessThan(0.03));
        expect(near(AppUtils.haversineMeters(b, cc), c.bc), lessThan(0.03));
        if (c.ac > 20) {
          expect(near(AppUtils.haversineMeters(a, cc), c.ac), lessThan(0.05));
        }
      });

      test('#${i + 1} ${c.spike ? 'is flagged as a spike' : 'is kept'} '
          '(${c.ab} m / ${c.bc} m / A–C ${c.ac} m)', () {
        expect(
            GpsOutlier.isSpike(a, b, cc,
                ab: Duration(seconds: c.dtAb), bc: Duration(seconds: c.dtBc)),
            c.spike);
      });
    }
  });
}
