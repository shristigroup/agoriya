import '../../data/models/shift_model.dart';

/// Late / early arithmetic for punch-in and punch-out against a shift.
/// All times are the phone's local time (India), the same clock the shift's
/// minutes are expressed in.
class ShiftTime {
  /// Within this many minutes of the shift's start or end is not anomalous.
  static const int graceMinutes = 10;

  static DateTime _at(DateTime day, int minute) =>
      DateTime(day.year, day.month, day.day).add(Duration(minutes: minute));

  /// The shift's start on [day] (local), or null if it has no start time.
  static DateTime? startOn(ShiftModel s, DateTime day) =>
      s.startMinute == null ? null : _at(day, s.startMinute!);

  /// The shift's end for the shift day that starts on [day]. A night shift
  /// ends the next morning.
  static DateTime? endOn(ShiftModel s, DateTime day) {
    if (s.endMinute == null) return null;
    final end = _at(day, s.endMinute!);
    return s.endNextDay ? end.add(const Duration(days: 1)) : end;
  }

  static DateTime _closest(Iterable<DateTime> candidates, DateTime t) =>
      candidates.reduce((a, b) =>
          a.difference(t).abs() <= b.difference(t).abs() ? a : b);

  /// Minutes late (0 if on time, early, or the shift has no start time). A
  /// punch-in at 00:30 for a 22:00 night shift counts against yesterday's start.
  static int lateMinutes(ShiftModel s, DateTime punchIn) {
    if (s.startMinute == null) return 0;
    final day = DateTime(punchIn.year, punchIn.month, punchIn.day);
    final start = _closest([
      for (final d in [-1, 0, 1]) _at(day.add(Duration(days: d)), s.startMinute!)
    ], punchIn);
    final late = punchIn.difference(start).inMinutes;
    return late > graceMinutes ? late : 0;
  }

  /// Minutes before the shift's end the user punched out (0 if on time or
  /// after, or the shift has no end time).
  static int earlyMinutes(ShiftModel s, DateTime punchOut) {
    if (s.endMinute == null) return 0;
    final day = DateTime(punchOut.year, punchOut.month, punchOut.day);
    final end = _closest([
      for (final d in [-1, 0, 1])
        endOn(s, day.add(Duration(days: d)))!
    ], punchOut);
    final early = end.difference(punchOut).inMinutes;
    return early > graceMinutes ? early : 0;
  }
}
