import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:agoriya/core/utils/app_utils.dart';
import 'package:agoriya/data/models/location_model.dart';
import 'package:agoriya/services/location_sync_service.dart';
import 'package:agoriya/services/osrm_service.dart';

final _t0 = DateTime.utc(2026, 11, 10, 10, 0, 0);

LocationPoint pt(double lat, int seconds, {bool snapped = false, int? stay}) =>
    LocationPoint(
      position: LatLng(lat, 77.0),
      timestamp: _t0.add(Duration(seconds: seconds)),
      isSnapped: snapped,
      durationSeconds: stay,
    );

/// [n] points a minute apart heading north, 400-600 m apart (24-36 km/h).
List<LocationPoint> steady(int n, {int startSeconds = 0, double startLat = 12.0, bool snapped = false}) {
  final out = <LocationPoint>[];
  var lat = startLat;
  for (var i = 0; i < n; i++) {
    out.add(pt(lat, startSeconds + i * 60, snapped: snapped));
    lat += 0.0036 + (i % 3) * 0.0009;
  }
  return out;
}

/// What the sync did: every list it wrote, every confirmation it sent.
class _Run {
  final written = <List<LocationPoint>>[];
  final confirms = <({LocationPoint anchor, DateTime trimUpTo})>[];
  final progress = <(int, int)>[];
  var matchCalls = 0;
  (List<LocationPoint>, double)? result;
}

Future<_Run> runSync({
  required List<LocationPoint> pending,
  required OsrmTrace Function(int pointCount) osrm,
  List<LocationPoint> finalLocations = const [],
  double distance = 0,
  bool holdBackTail = false,
  bool punchOut = false,
}) async {
  final run = _Run();
  run.result = await LocationSyncService.syncPending(
    pending: pending,
    anchorStay: null,
    finalLocations: finalLocations,
    finalLocationsDistance: distance,
    holdBackTail: holdBackTail,
    punchOut: punchOut,
    onProgress: (done, total) => run.progress.add((done, total)),
    match: (points, times) async {
      run.matchCalls++;
      return osrm(points.length);
    },
    persist: (all, km) async => run.written.add(List.of(all)),
    confirm: (anchor, km, trimUpTo) =>
        run.confirms.add((anchor: anchor, trimUpTo: trimUpTo)),
  );
  return run;
}

void main() {
  test('regular sync: OSRM does not answer, so nothing is written and the points stay pending', () async {
    final run = await runSync(
      pending: steady(12),
      holdBackTail: true,
      osrm: (n) => OsrmTrace.failed('error', n),
    );
    expect(run.result, isNull);
    expect(run.written, isEmpty);
    expect(run.confirms, isEmpty); // nothing trimmed from the pending list
  });

  test('OSRM answers "no match": the unit is written and trimmed, newest point held back', () async {
    final pending = steady(12);
    final run = await runSync(
      pending: pending,
      holdBackTail: true,
      osrm: (n) => OsrmTrace.failed('http_400:NoMatch', n),
    );
    expect(run.written.length, 2); // units of 10 and 1
    expect(run.confirms.length, 2);
    expect(run.written.last.length, 11); // the 12th, newest point is held back
    expect(run.written.last.last.snapReason, 'http_400:NoMatch');
    expect(run.confirms.last.trimUpTo, pending[10].timestamp);
  });

  test('punch-out sync: OSRM does not answer, yet every point is written, asking OSRM only once', () async {
    final run = await runSync(
      pending: steady(12),
      punchOut: true,
      osrm: (n) => OsrmTrace.failed('error', n),
    );
    expect(run.matchCalls, 1); // after the first no-answer OSRM is not asked again
    expect(run.written.length, 2);
    expect(run.written.last.length, 12); // nothing held back
    expect(run.written.first.last.snapReason, 'error');
    expect(run.written.last.last.snapReason, 'skipped');
    expect(run.progress, [(0, 12), (10, 12), (12, 12)]);
  });

  test('carry dropped: it is flagged, and the distance is re-measured from the point before it', () async {
    // 10 saved snapped points, then an unmatched 2-hour stay (the carry), then a
    // real fix 12.5 km away only minutes after the stay ends.
    final saved = steady(10, snapped: true);
    final carry = pt(saved.last.position.latitude + 0.0045, 10 * 60, stay: 7200);
    final history = [...saved, carry];
    final unit = <LocationPoint>[];
    var lat = carry.position.latitude + 0.1125;
    for (var i = 0; i < 9; i++) {
      unit.add(pt(lat, 10 * 60 + 7200 + 250 + i * 60));
      lat += 0.0036 + (i % 3) * 0.0009;
    }

    final run = await runSync(
      pending: unit,
      finalLocations: history,
      distance: 5.0,
      osrm: (n) => OsrmTrace.failed('http_400:NoMatch', n),
    );

    final written = run.written.single;
    expect(written[10].dropped, isTrue); // the carry
    expect(written.where((p) => p.dropped).length, 1);

    double km(LatLng a, LatLng b) => AppUtils.haversineMeters(a, b) / 1000.0;
    final p8 = saved.last.position;
    var expected = 5.0 - km(p8, carry.position) + km(p8, unit.first.position);
    for (var i = 0; i < unit.length - 1; i++) {
      expected += km(unit[i].position, unit[i + 1].position);
    }
    expect(run.result!.$2, closeTo(expected, 1e-6));
    // the anchor handed to the tracking isolate is a kept point, not the dropped carry
    expect(run.confirms.single.anchor.dropped, isFalse);
  });
}
