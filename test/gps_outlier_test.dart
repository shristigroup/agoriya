import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:agoriya/core/utils/gps_outlier.dart';

// ~111 m per 0.001° of latitude.
LatLng p(double northMeters, [double eastMeters = 0]) =>
    LatLng(12.9 + northMeters / 111000.0, 77.6 + eastMeters / 108000.0);

void main() {
  group('GpsOutlier.isSpike', () {
    test('stray fix far away between two nearby points is a spike', () {
      expect(GpsOutlier.isSpike(p(0), p(1000), p(10)), isTrue);
    });

    test('person who starts moving in a line is not a spike', () {
      expect(GpsOutlier.isSpike(p(0), p(400), p(800)), isFalse);
    });

    test('stationary jitter is not a spike', () {
      expect(GpsOutlier.isSpike(p(0), p(40), p(5)), isFalse);
    });

    test('small detour under the leg threshold is not a spike', () {
      expect(GpsOutlier.isSpike(p(0), p(200), p(10)), isFalse);
    });

    test('a real turnaround that ends well away from the start is kept', () {
      // out 500 m, then back only 200 m: A and C stay 300 m apart.
      expect(GpsOutlier.isSpike(p(0), p(500), p(300)), isFalse);
    });

    test('one long leg only is not a spike', () {
      expect(GpsOutlier.isSpike(p(0), p(1000), p(1100)), isFalse);
    });

    test('works in the east-west direction too', () {
      expect(GpsOutlier.isSpike(p(0, 0), p(0, 900), p(0, 20)), isTrue);
    });
  });

  group('GpsOutlier.isJump', () {
    test('long hop is a jump, short one is not', () {
      expect(GpsOutlier.isJump(p(0), p(1000)), isTrue);
      expect(GpsOutlier.isJump(p(0), p(100)), isFalse);
    });
  });
}
