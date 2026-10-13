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
  const _Case(this.spike, this.ab, this.bc, this.ac, this.a, this.b, this.c);
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
  // Near the threshold: a turn / partial return — must be kept.
    _Case(false, 480, 315, 170, [0.0, 0.0], [230.9, 421.8], [106.7, 132.0]),
    _Case(false, 770, 1190, 419, [0.0, 0.0], [715.9, 286.9], [-393.8, -145.5]),
    _Case(false, 391, 501, 138, [0.0, 0.0], [390.7, -20.4], [-106.6, -88.0]),
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
        expect(GpsOutlier.isSpike(a, b, cc), c.spike);
      });
    }
  });
}
