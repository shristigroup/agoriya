import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:agoriya/data/models/location_model.dart';
import 'package:agoriya/services/osrm_service.dart';
import 'package:agoriya/services/route_builder.dart';

LocationPoint pt(double lat, int seconds, {bool snapped = false}) => LocationPoint(
      position: LatLng(lat, 77.0),
      timestamp: DateTime.utc(2026, 11, 10, 10, 0, seconds),
      isSnapped: snapped,
    );

void main() {
  test('the dropped flag survives JSON (Hive) and Firestore, and copies', () {
    final p = LocationPoint(
      position: const LatLng(12.9, 77.6),
      timestamp: DateTime.utc(2026, 1, 1),
      durationSeconds: 30,
      dropped: true,
    );
    expect(LocationPoint.fromJson(p.toJson()).dropped, isTrue);
    expect(LocationPoint.fromFirestore(p.toFirestore()).dropped, isTrue);
    expect(p.copyWith(durationSeconds: 5).dropped, isTrue);
    expect(p.copyWithPosition(isSnapped: false).dropped, isTrue);

    final kept = LocationPoint(position: const LatLng(12.9, 77.6), timestamp: DateTime.utc(2026, 1, 1, 0, 1));
    expect(kept.toFirestore().containsKey('dropped'), isFalse); // nothing extra for kept points
    expect([p, kept].visible, [kept]);
  });

  test('a dropped point does not change the distance', () {
    final carry = pt(12.0, 0, snapped: true);
    final stray = pt(12.036, 60); // ~4 km off
    final next = pt(12.0045, 120);

    final withDropped = RouteBuilder.build(
      carry: carry,
      raw: [stray, next],
      trace: OsrmTrace.failed('http_400:NoMatch', 3),
      droppedMs: {stray.timestamp.millisecondsSinceEpoch},
    );
    final withoutIt = RouteBuilder.build(
      carry: carry,
      raw: [next],
      trace: OsrmTrace.failed('http_400:NoMatch', 2),
    );

    expect(withDropped.stored.first.dropped, isTrue); // still stored, flagged
    expect(withDropped.distanceKm, closeTo(withoutIt.distanceKm, 1e-9));
  });
}
