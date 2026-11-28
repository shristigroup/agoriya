import 'package:flutter_test/flutter_test.dart';
import 'package:agoriya/core/utils/geofence.dart';
import 'package:agoriya/data/models/shift_model.dart';

void main() {
  // An office, and points a known distance north of it (0.001 degrees of
  // latitude is about 111 m).
  const office = ShiftLocation(lat: 21.2500, lng: 81.6300, name: 'HQ');
  const radius = 100;

  GeoResult at(double dLat, {double? accuracy, Duration? age}) => Geofence.check(
        target: office,
        radiusM: radius,
        lat: office.lat + dLat,
        lng: office.lng,
        accuracyM: accuracy,
        age: age,
      );

  test('distance maths: 0.001 degrees of latitude is about 111 m', () {
    final d = Geofence.distanceMeters(21.25, 81.63, 21.251, 81.63);
    expect(d, closeTo(111.2, 1));
    expect(Geofence.distanceMeters(21.25, 81.63, 21.25, 81.63), 0);
  });

  test('inside the radius is fine', () {
    final r = at(0.0004); // about 44 m
    expect(r.verdict, GeoVerdict.ok);
    expect(r.distanceM, closeTo(44.5, 1));
  });

  test('outside the radius warns, with the distance', () {
    final r = at(0.0015); // about 167 m
    expect(r.verdict, GeoVerdict.warn);
    expect(r.distanceM, closeTo(166.8, 1));
  });

  test('poor accuracy gives the benefit of the doubt', () {
    expect(at(0.0015, accuracy: 20).verdict, GeoVerdict.warn); // 167 - 20 > 100
    expect(at(0.0015, accuracy: 80).verdict, GeoVerdict.ok); // 167 - 80 < 100
  });

  test('a position older than 30 minutes is skipped, a fresh one is used', () {
    expect(at(0.0015, age: const Duration(minutes: 31)).verdict, GeoVerdict.skip);
    expect(at(0.0015, age: const Duration(minutes: 29)).verdict, GeoVerdict.warn);
  });

  test('no position, or no location on the shift, is skipped', () {
    expect(
        Geofence.check(
                target: office, radiusM: radius, lat: null, lng: null)
            .verdict,
        GeoVerdict.skip);
    expect(
        Geofence.check(target: null, radiusM: radius, lat: 1, lng: 1).verdict,
        GeoVerdict.skip);
  });
}
