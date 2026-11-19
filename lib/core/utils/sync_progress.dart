/// The "about 1 min left" line on the punch-out sync screen.
String syncTimeLeftLabel({
  required int done,
  required int total,
  required Duration elapsed,
}) {
  // Nothing finished yet, so there is nothing to base an estimate on.
  if (done <= 0 || total <= 0) return 'Estimating time left…';
  if (done >= total) return 'Almost done…';
  final perPoint = elapsed.inMilliseconds / done;
  final seconds = (perPoint * (total - done) / 1000).ceil();
  if (seconds < 10) return 'Less than 10 sec left';
  if (seconds < 60) return 'About ${(seconds / 5).round() * 5} sec left';
  final minutes = (seconds / 60).ceil();
  return 'About $minutes min left';
}
