import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:agoriya/core/utils/app_utils.dart';
import 'package:agoriya/core/utils/polyline_codec.dart';
import 'package:agoriya/core/utils/route_path.dart';
import 'package:agoriya/data/models/location_model.dart';
import 'package:agoriya/services/osrm_service.dart';
import 'package:agoriya/services/route_builder.dart';

LocationPoint pt(double lat, double lng, int tMs,
        {int? dur, String? road, int? roadEnd}) =>
    LocationPoint(
        position: LatLng(lat, lng),
        timestamp: DateTime.fromMillisecondsSinceEpoch(tMs),
        durationSeconds: dur,
        road: road,
        roadEndMs: roadEnd);

void main() {
  group('PolylineCodec', () {
    test('matches the reference example of the format', () {
      final pts = [LatLng(38.5, -120.2), LatLng(40.7, -120.95), LatLng(43.252, -126.453)];
      expect(PolylineCodec.encode(pts), '_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      final back = PolylineCodec.decode('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(back.length, 3);
      expect(back[2].latitude, closeTo(43.252, 1e-9));
      expect(back[2].longitude, closeTo(-126.453, 1e-9));
    });

    test('round-trips a route within the format precision (~1 m)', () {
      final pts = [
        for (var i = 0; i < 40; i++) LatLng(12.9 + i * 0.00137, 77.58 - i * 0.0009),
      ];
      final back = PolylineCodec.decode(PolylineCodec.encode(pts));
      expect(back.length, pts.length);
      for (var i = 0; i < pts.length; i++) {
        expect((back[i].latitude - pts[i].latitude).abs(), lessThan(1e-5));
        expect((back[i].longitude - pts[i].longitude).abs(), lessThan(1e-5));
      }
    });

    test('empty string decodes to nothing', () {
      expect(PolylineCodec.decode(''), isEmpty);
    });
  });

  group('RoutePath.build', () {
    final road = PolylineCodec.encode(
        [LatLng(1.0, 1.0), LatLng(1.0, 1.01), LatLng(1.01, 1.01)]);

    test('no road paths: straight lines through the points, as before', () {
      final path = RoutePath.build([pt(1, 1, 0), pt(2, 2, 1000), pt(3, 3, 2000)]);
      expect(path, [LatLng(1, 1), LatLng(2, 2), LatLng(3, 3)]);
    });

    test('a road path replaces the straight lines up to its end point', () {
      final points = [
        pt(1.0, 1.0, 0, road: road, roadEnd: 2000), // starts the road path
        pt(1.0, 1.01, 1000), // on the road — not added separately
        pt(1.01, 1.01, 2000), // end
        pt(1.02, 1.02, 3000), // unmatched stretch after: straight
      ];
      final path = RoutePath.build(points);
      expect(path.first, LatLng(1.0, 1.0));
      expect(path.length, 1 + 3 + 1 + 1); // start, 3 road vertices, end, last
      expect(path.last, LatLng(1.02, 1.02));
      expect(path.contains(LatLng(1.0, 1.01)), isTrue); // road vertex
    });

    test('a missing end point falls back to straight lines', () {
      final points = [pt(1.0, 1.0, 0, road: road, roadEnd: 99999), pt(2, 2, 1000)];
      expect(RoutePath.build(points), [LatLng(1.0, 1.0), LatLng(2, 2)]);
    });

    test('point that ends one road path can start the next', () {
      final r2 = PolylineCodec.encode([LatLng(2.0, 2.0), LatLng(2.0, 2.01)]);
      final points = [
        pt(1.0, 1.0, 0, road: road, roadEnd: 1000),
        pt(1.01, 1.01, 1000, road: r2, roadEnd: 2000),
        pt(2.0, 2.01, 2000),
      ];
      final path = RoutePath.build(points);
      expect(path.length, 1 + 3 + 1 + 2 + 1); // p0, road 1, p1, road 2, p2
      expect(path.last, LatLng(2.0, 2.01));
    });
  });

  group('LocationPoint road fields', () {
    test('survive the local-cache and Firestore map round trips', () {
      final p = pt(1, 2, 5000, road: 'abc', roadEnd: 9000);
      expect(LocationPoint.fromJson(p.toJson()).road, 'abc');
      expect(LocationPoint.fromJson(p.toJson()).roadEndMs, 9000);
      expect(p.toFirestore()['road'], 'abc');
      expect(p.toFirestore()['roadEnd'], 9000);
    });

    test('points without a road path stay exactly as small as before', () {
      final m = pt(1, 2, 5000).toFirestore();
      expect(m.containsKey('road'), isFalse);
      expect(m.containsKey('roadEnd'), isFalse);
    });
  });

  group('OsrmService.parseTraceResponse', () {
    final ok = jsonEncode({
      'code': 'Ok',
      'matchings': [
        {
          'geometry': '_p~iF~ps|U_ulLnnqC',
          'distance': 900.0,
          'confidence': 0.8,
          'legs': [
            {'distance': 400.0},
            {'distance': 500.0}
          ],
        }
      ],
      'tracepoints': [
        {'location': [77.5, 12.9], 'matchings_index': 0, 'waypoint_index': 0},
        null,
        {'location': [77.51, 12.91], 'matchings_index': 0, 'waypoint_index': 1},
      ],
    });

    test('keeps per-point placement, nulls and leg distances', () {
      final t = OsrmService.parseTraceResponse(200, ok, 3);
      expect(t.ok, isTrue);
      expect(t.tracepoints[1], isNull);
      expect(t.tracepoints[2]!.waypointIndex, 1);
      expect(t.matchings.single.legDistancesM, [400.0, 500.0]);
      expect(t.matchings.single.polyline, '_p~iF~ps|U_ulLnnqC');
    });

    test('HTTP 400 keeps OSRM\'s own error code in the reason', () {
      final t = OsrmService.parseTraceResponse(
          400, '{"code":"TooBig","message":"Too many trace coordinates"}', 11);
      expect(t.reason, 'http_400:TooBig');
      expect(t.tracepoints.length, 11);
      expect(t.tracepoints.every((e) => e == null), isTrue);
    });

    test('unparseable error body still yields a reason', () {
      expect(OsrmService.parseTraceResponse(502, '<html>', 4).reason, 'http_502');
    });

    test('200 with a non-Ok code is no_match', () {
      expect(OsrmService.parseTraceResponse(200, '{"code":"NoMatch"}', 4).reason,
          'no_match');
    });
  });

  group('RouteBuilder.build', () {
    // carry + 4 new points. OSRM matches carry,#1,#2 (matching 0) and #4
    // (matching 1, alone); skips #3.
    final carry = pt(12.9000, 77.5000, 0);
    final raw = [
      pt(12.9010, 77.5010, 60000),
      pt(12.9020, 77.5020, 120000),
      pt(12.9030, 77.5030, 180000, dur: 30),
      pt(12.9040, 77.5040, 240000),
    ];
    final trace = OsrmTrace([
      const OsrmMatching('POLY0', 300.0, 0.9, [100.0, 200.0]),
      const OsrmMatching('POLY1', 0.0, 0.1, []),
    ], [
      const OsrmTracepoint(LatLng(12.90001, 77.50001), 0, 0), // carry
      const OsrmTracepoint(LatLng(12.90101, 77.50101), 0, 1),
      const OsrmTracepoint(LatLng(12.90201, 77.50201), 0, 2),
      null, // #3 unmatched
      const OsrmTracepoint(LatLng(12.90401, 77.50401), 1, 0),
    ], 'ok');

    final out = RouteBuilder.build(carry: carry, raw: raw, trace: trace);

    test('one stored point per new point, real timestamps kept', () {
      expect(out.stored.length, 4);
      for (var i = 0; i < 4; i++) {
        expect(out.stored[i].timestamp, raw[i].timestamp);
      }
      expect(out.stored[2].durationSeconds, 30);
    });

    test('matched points move onto the road, unmatched stay raw', () {
      expect(out.stored[0].position, const LatLng(12.90101, 77.50101));
      expect(out.stored[0].isSnapped, isTrue);
      expect(out.stored[2].position, raw[2].position); // #3, unmatched
      expect(out.stored[2].isSnapped, isFalse);
    });

    test('the road path goes on the point where the matching starts (the carry)', () {
      expect(out.carry!.road, 'POLY0');
      expect(out.carry!.roadEndMs, 120000); // ends at stored point #2
      // matching 1 has a single point → no path at all.
      expect(out.stored.every((p) => p.road == null), isTrue);
    });

    test('distance = OSRM legs inside a matching + straight lines elsewhere', () {
      // legs 100 + 200, then #2 → (unmatched #3) → #4 straight.
      final p2 = out.stored[1].position, p3 = out.stored[2].position, p4 = out.stored[3].position;
      double d(LatLng a, LatLng b) => AppUtils.haversineMeters(a, b);
      final straight = d(p2, p3) + d(p3, p4);
      expect(out.distanceKm * 1000, closeTo(300 + straight, 0.5));
    });

    test('a failed request keeps every point raw and measures straight lines', () {
      final failed = OsrmTrace.failed('http_400:NoMatch', 5);
      final r = RouteBuilder.build(carry: carry, raw: raw, trace: failed);
      expect(r.carry, isNull);
      expect(r.stored.map((p) => p.position).toList(), raw.map((p) => p.position).toList());
      expect(r.stored.any((p) => p.isSnapped), isFalse);
      double d(LatLng a, LatLng b) => AppUtils.haversineMeters(a, b);
      var want = d(carry.position, raw[0].position);
      for (var i = 0; i < 3; i++) {
        want += d(raw[i].position, raw[i + 1].position);
      }
      expect(r.distanceKm * 1000, closeTo(want, 0.5));
    });

    test('no carry (first batch of a session) works too', () {
      final t = OsrmTrace([
        const OsrmMatching('P', 100.0, 0.9, [100.0]),
      ], [
        const OsrmTracepoint(LatLng(12.90101, 77.50101), 0, 0),
        const OsrmTracepoint(LatLng(12.90201, 77.50201), 0, 1),
      ], 'ok');
      final r = RouteBuilder.build(raw: raw.sublist(0, 2), trace: t);
      expect(r.carry, isNull);
      expect(r.stored[0].road, 'P');
      expect(r.stored[0].roadEndMs, raw[1].timestamp.millisecondsSinceEpoch);
      expect(r.distanceKm * 1000, closeTo(100, 0.01));
    });
  });
}
