import '../../data/data_manager.dart';
import '../../data/models/shift_model.dart';
import '../../data/models/tracking_model.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/firestore_repository.dart';
import '../../data/repositories/shift_repository.dart';
import '../../core/utils/app_utils.dart';
import '../../services/shift_service.dart';
import 'place_search.dart';

class OrgMember {
  final String id;
  final String name;
  const OrgMember(this.id, this.name);
}

/// Everything the assistant's actions read and write. A seam so the actions
/// can be tested without Firebase.
abstract class AssistantData {
  Future<List<OrgMember>> members();
  Future<List<ShiftModel>> shifts();
  Future<String> saveShift(ShiftModel shift);
  Future<void> deleteShift(String id);
  Future<void> assignUsers(String shiftId, List<String> userIds);
  Future<void> removeUsers(String shiftId, List<String> userIds);
  Future<List<PlaceResult>> searchPlaces(String query);

  /// [{name, status}] for the owner's team today.
  Future<List<Map<String, dynamic>>> teamToday();

  /// Per-day summary of one member's sessions in a month (yyyy-MM).
  Future<List<Map<String, dynamic>>> memberHistory(String userId, String month);
}

class FirestoreAssistantData implements AssistantData {
  final UserModel owner;
  final ShiftRepository _shifts = ShiftRepository();
  final FirestoreRepository _repo = FirestoreRepository();
  final PlaceSearch _places = PlaceSearch();

  FirestoreAssistantData(this.owner);

  String get _code => owner.code ?? '';

  @override
  Future<List<OrgMember>> members() async {
    final list = await _repo.getOrgMembers(_code);
    return [for (final m in list) OrgMember(m.id, m.fullName.trim())];
  }

  @override
  Future<List<ShiftModel>> shifts() => _shifts.getShifts(_code);

  @override
  Future<String> saveShift(ShiftModel shift) => _shifts.saveShift(_code, shift);

  @override
  Future<void> deleteShift(String id) => _shifts.deleteShift(_code, id);

  @override
  Future<void> assignUsers(String shiftId, List<String> userIds) =>
      _shifts.assignUsers(_code, shiftId, userIds);

  @override
  Future<void> removeUsers(String shiftId, List<String> userIds) =>
      _shifts.removeUsers(_code, shiftId, userIds);

  @override
  Future<List<PlaceResult>> searchPlaces(String query) async {
    final near = await ShiftService.lastKnown(null);
    return _places.search(query, nearLat: near?.lat, nearLng: near?.lng);
  }

  List<MapEntry<String, String>> _flatten(Map<String, dynamic> reports) {
    final out = <MapEntry<String, String>>[];
    for (final e in reports.entries) {
      final data = Map<String, dynamic>.from(e.value as Map);
      out.add(MapEntry(e.key, data['name'] as String? ?? e.key));
      final sub = Map<String, dynamic>.from(data['reports'] as Map? ?? {});
      if (sub.isNotEmpty) out.addAll(_flatten(sub));
    }
    return out;
  }

  @override
  Future<List<Map<String, dynamic>>> teamToday() async {
    final fresh = await _repo.getUserById(owner.id) ?? owner;
    final today = AppUtils.todayKey();
    final team = _flatten(fresh.reports);
    final rows = await Future.wait(team.take(100).map((m) async {
      TrackingModel? t;
      try {
        t = await DataManager.getTrackingForToday(m.key, today);
      } catch (_) {}
      return <String, dynamic>{
        'name': m.value,
        'status': t == null
            ? 'not punched in'
            : t.isPunchedIn
                ? 'punched in at ${AppUtils.formatTime(t.startTime)}'
                : 'punched out at ${AppUtils.formatTime(t.stopTime!)}',
        if (t != null) 'distanceKm': double.parse(t.distance.toStringAsFixed(1)),
      };
    }));
    return rows;
  }

  @override
  Future<List<Map<String, dynamic>>> memberHistory(String userId, String month) async {
    final days = await _repo.getTrackingForMonth(userId, month);
    return [
      for (final t in days.take(31))
        {
          'date': t.date,
          'in': AppUtils.formatTime(t.startTime),
          'out': t.stopTime == null ? 'still open' : AppUtils.formatTime(t.stopTime!),
          'hours': double.parse((t.attendanceDuration.inMinutes / 60).toStringAsFixed(1)),
          'distanceKm': double.parse(t.distance.toStringAsFixed(1)),
          'visits': t.visitCount,
          if (t.wasAutoClosed) 'autoPunchedOut': true,
          if (t.punchInAnomaly != null) 'punchInAnomaly': t.punchInAnomaly,
          if (t.punchOutAnomaly != null) 'punchOutAnomaly': t.punchOutAnomaly,
        }
    ];
  }
}
