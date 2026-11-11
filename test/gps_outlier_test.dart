import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:agoriya/core/utils/gps_outlier.dart';

// ~111 m per 0.001° of latitude.
LatLng p(double northMeters, [double eastMeters = 0]) =>
    LatLng(12.9 + northMeters / 111000.0, 77.6 + eastMeters / 108000.0);

const _min = Duration(seconds: 60);

bool spike(LatLng a, LatLng b, LatLng c,
        {Duration ab = _min, Duration bc = _min}) =>
    GpsOutlier.isSpike(a, b, c, ab: ab, bc: bc);

void main() {
  group('GpsOutlier.isSpike', () {
    test('stray fix far away between two nearby points is a spike', () {
      expect(spike(p(0), p(1000), p(10)), isTrue);
    });

    test('person who starts moving in a line is not a spike', () {
      expect(spike(p(0), p(400), p(800)), isFalse);
    });

    test('stationary jitter is not a spike', () {
      expect(spike(p(0), p(40), p(5)), isFalse);
    });

    test('small detour under the leg threshold is not a spike', () {
      expect(spike(p(0), p(200), p(10)), isFalse);
    });

    test('a short return leg is never a spike, however sharp', () {
      // out 500 m, then back only 200 m — the 200 m leg is under the threshold.
      expect(spike(p(0), p(500), p(300)), isFalse);
    });

    test('one long leg only is not a spike', () {
      expect(spike(p(0), p(1000), p(1100)), isFalse);
    });

    test('works in the east-west direction too', () {
      expect(spike(p(0, 0), p(0, 900), p(0, 20)), isTrue);
    });

    test('stray that sits off the path while the rider keeps moving', () {
      // Neighbours are 530 m apart (the rider really moved), but the path
      // through the stray is 2.6 km — the speed rule catches what a
      // "came straight back" rule cannot.
      expect(spike(p(0), p(1000, 400), p(-460, -260)), isTrue);
    });

    test('a slow return leg means the detour was real, not a stray', () {
      // 500 m out in 1 min, then 500 m back over 30 min, ending 300 m from
      // the start: the second leg is slow, so the path is not abnormally fast.
      expect(
          spike(p(0), p(500), p(300),
              ab: const Duration(minutes: 1), bc: const Duration(minutes: 30)),
          isFalse);
    });

    test('non-positive travel time cannot be judged', () {
      expect(spike(p(0), p(1000), p(10), ab: Duration.zero), isFalse);
      expect(spike(p(0), p(1000), p(10), bc: const Duration(seconds: -5)),
          isFalse);
    });
  });
}
