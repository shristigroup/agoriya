import 'package:flutter_test/flutter_test.dart';
import 'package:agoriya/core/utils/shift_check.dart';
import 'package:agoriya/data/models/shift_model.dart';

void main() {
  const hq = ShiftLocation(lat: 21.25, lng: 81.63, name: 'HQ');
  const shift = ShiftModel(
      id: 's',
      name: 'Day',
      startMinute: 9 * 60,
      endMinute: 18 * 60,
      inLocation: hq);
  DateTime t(int h, int m) => DateTime(2026, 11, 28, h, m);
  const near = KnownPosition(lat: 21.2501, lng: 81.63, age: Duration(minutes: 1));
  const far = KnownPosition(lat: 21.2535, lng: 81.63, age: Duration(minutes: 1));

  test('on time and at the place: nothing to record', () {
    final c = evaluateShift(shift: shift, isPunchIn: true, now: t(9, 0), position: near);
    expect(c.needsWarning, false);
    expect(c.anomaly(warnedAndContinued: false), isNull);
  });

  test('late but at the place: records only the lateness', () {
    final c = evaluateShift(shift: shift, isPunchIn: true, now: t(9, 45), position: near);
    expect(c.anomaly(warnedAndContinued: false), {'lateMinutes': 45});
  });

  test('far from the place: warns, and records the distance only if they carry on', () {
    final c = evaluateShift(shift: shift, isPunchIn: true, now: t(9, 0), position: far);
    expect(c.needsWarning, true);
    expect(c.anomaly(warnedAndContinued: false), isNull);
    final a = c.anomaly(warnedAndContinued: true)!;
    expect(a['locationName'], 'HQ');
    expect(a['distanceM'], inInclusiveRange(380, 400));
  });

  test('punch-out: early leaving, and the place defaults to the punch-in place', () {
    final c = evaluateShift(shift: shift, isPunchIn: false, now: t(16, 0), position: far);
    expect(c.earlyMinutes, 120);
    expect(c.target, hq);
    expect(c.needsWarning, true);
  });

  test('a punch-out location of its own is used for punch-out', () {
    const other = ShiftLocation(lat: 21.30, lng: 81.70, name: 'Depot');
    final s = shift.copyWith(outLocation: other);
    final c = evaluateShift(shift: s, isPunchIn: false, now: t(18, 0), position: near);
    expect(c.target, other);
    expect(c.needsWarning, true);
  });

  test('no recent position: no warning', () {
    final c = evaluateShift(
        shift: shift,
        isPunchIn: true,
        now: t(9, 0),
        position: const KnownPosition(lat: 22, lng: 82, age: Duration(hours: 3)));
    expect(c.needsWarning, false);
    expect(evaluateShift(shift: shift, isPunchIn: true, now: t(9, 0)).needsWarning, false);
  });
}
