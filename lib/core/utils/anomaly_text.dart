/// One line describing a punch-in / punch-out anomaly, for History:
/// "Punched in 12 min late, 350 m from HQ". Same wording as the manager's
/// notification (functions/shifts.js anomalyText).
String anomalyLine(Map<String, dynamic>? a, {required bool punchIn}) {
  if (a == null) return '';
  final parts = <String>[];
  final late = (a['lateMinutes'] as num?)?.toInt() ?? 0;
  final early = (a['earlyMinutes'] as num?)?.toInt() ?? 0;
  final dist = (a['distanceM'] as num?)?.toInt() ?? 0;
  if (late > 0) parts.add('$late min late');
  if (early > 0) parts.add('$early min early');
  if (dist > 0) {
    final d = dist >= 1000 ? '${(dist / 1000).toStringAsFixed(1)} km' : '$dist m';
    final place = (a['locationName'] as String?)?.isNotEmpty == true
        ? a['locationName']
        : 'the location';
    parts.add('$d from $place');
  }
  if (parts.isEmpty) return '';
  return '${punchIn ? 'Punched in' : 'Punched out'} ${parts.join(', ')}';
}
