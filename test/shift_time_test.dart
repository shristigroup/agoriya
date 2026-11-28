import 'package:flutter_test/flutter_test.dart';
import 'package:agoriya/core/utils/shift_time.dart';
import 'package:agoriya/data/models/shift_model.dart';

void main() {
  const day = ShiftModel(
      id: 'd', name: 'Day', startMinute: 9 * 60 + 30, endMinute: 18 * 60);
  const night = ShiftModel(
      id: 'n',
      name: 'Night',
      startMinute: 22 * 60,
      endMinute: 6 * 60,
      endNextDay: true);

  DateTime t(int d, int h, int m) => DateTime(2026, 11, d, h, m);

  group('day shift', () {
    test('on time, within the grace, and early are not late', () {
      expect(ShiftTime.lateMinutes(day, t(28, 9, 25)), 0);
      expect(ShiftTime.lateMinutes(day, t(28, 9, 30)), 0);
      expect(ShiftTime.lateMinutes(day, t(28, 9, 40)), 0); // exactly the grace
    });

    test('late beyond the grace reports the minutes', () {
      expect(ShiftTime.lateMinutes(day, t(28, 9, 55)), 25);
      expect(ShiftTime.lateMinutes(day, t(28, 12, 30)), 180);
    });

    test('leaving early beyond the grace reports the minutes', () {
      expect(ShiftTime.earlyMinutes(day, t(28, 17, 55)), 0); // within grace
      expect(ShiftTime.earlyMinutes(day, t(28, 17, 45)), 15);
      expect(ShiftTime.earlyMinutes(day, t(28, 17, 0)), 60);
      expect(ShiftTime.earlyMinutes(day, t(28, 18, 20)), 0); // after the end
    });
  });

  group('night shift (22:00 to 06:00 next day)', () {
    test('lateness is measured from the evening start', () {
      expect(ShiftTime.lateMinutes(night, t(28, 21, 50)), 0);
      expect(ShiftTime.lateMinutes(night, t(28, 22, 20)), 20);
    });

    test('a punch-in after midnight counts against the previous evening', () {
      expect(ShiftTime.lateMinutes(night, t(29, 0, 30)), 150);
    });

    test('the end is the next morning', () {
      expect(ShiftTime.endOn(night, DateTime(2026, 11, 28)), t(29, 6, 0));
      expect(ShiftTime.earlyMinutes(night, t(29, 5, 0)), 60);
      expect(ShiftTime.earlyMinutes(night, t(29, 6, 5)), 0);
    });

    test('a punch-out the same evening, before the end, is early', () {
      // 23:30 is 6.5 hours before the 06:00 end of the shift that began at 22:00.
      expect(ShiftTime.earlyMinutes(night, t(28, 23, 30)), 390);
    });
  });

  group('shifts without times', () {
    const placeOnly = ShiftModel(id: 'p', name: 'Office');
    test('are never late or early', () {
      expect(ShiftTime.lateMinutes(placeOnly, t(28, 15, 0)), 0);
      expect(ShiftTime.earlyMinutes(placeOnly, t(28, 15, 0)), 0);
      expect(placeOnly.timeLabel, '');
    });
  });

  test('time label', () {
    expect(day.timeLabel, '09:30 - 18:00');
    expect(night.timeLabel, '22:00 - 06:00 (next day)');
  });
}
