/// Today's date in India as yyyy-MM-dd, the day key for credits and chat
/// resets. The same value Firestore rules compute (firestore.rules, istDate).
String istDateString(DateTime now) {
  final t = now.toUtc().add(const Duration(hours: 5, minutes: 30));
  return '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
}
