import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:agoriya/data/models/location_model.dart';
import 'package:agoriya/services/route_cleaner.dart';

/// Real batches taken from production tracking data, anonymised: each point is
/// stored as east/north metre offsets from the first point of its chain and as
/// seconds from that point, so the geometry and speeds are exact but the place
/// and the person are not recoverable. Each chain is the saved points before the
/// batch (history, at most 50), the batch itself (unit) and the point after it
/// (next). The first five are known strays the old live rule could not remove;
/// the last two must be left alone.
const _lat0 = 12.9, _lon0 = 77.6;
final _t0 = DateTime.utc(2026, 1, 1);

LocationPoint _point(Map<String, dynamic> p) => LocationPoint(
      position: LatLng(
        _lat0 + (p['n'] as num) / 111320.0,
        _lon0 + (p['e'] as num) / (111320.0 * math.cos(_lat0 * math.pi / 180)),
      ),
      timestamp:
          _t0.add(Duration(milliseconds: ((p['t'] as num) * 1000).round())),
      isSnapped: p['snapped'] as bool,
      durationSeconds: (p['dur'] as num).toInt(),
    );

void main() {
  final cases = jsonDecode(
          File('test/fixtures/route_cleaner_cases.json').readAsStringSync())
      as List;

  group('RouteCleaner on real production batches', () {
    for (final c in cases) {
      test(c['name'] as String, () {
        final points = (c['points'] as List).cast<Map<String, dynamic>>();
        List<LocationPoint> role(String r) =>
            points.where((p) => p['role'] == r).map(_point).toList();
        final next = role('next');

        final dropped = RouteCleaner.clean(
          history: role('history'),
          unit: role('unit'),
          next: next.isEmpty ? null : next.first,
        );

        final expected = (c['expectedDroppedT'] as List)
            .map((t) => _t0
                .add(Duration(milliseconds: ((t as num) * 1000).round()))
                .millisecondsSinceEpoch)
            .toSet();
        expect(dropped, expected, reason: c['why'] as String);
      });
    }
  });
}
