import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/shift_model.dart';

/// Shifts live at Codes/{code}/Shifts/{id}. Members read them; only the code's
/// owner writes (see firestore.rules). Who is on a shift is the shift's
/// `userIds` list, and a person is on at most one shift.
class ShiftRepository {
  final FirebaseFirestore _db;
  ShiftRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _shifts(String code) =>
      _db.collection('Codes').doc(code).collection('Shifts');

  Future<List<ShiftModel>> getShifts(String code) async {
    final snap = await _shifts(code).get();
    final list = snap.docs.map(ShiftModel.fromDoc).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// The shift this user is on, or null.
  Future<ShiftModel?> getShiftForUser(String code, String userId) async {
    final shifts = await getShifts(code);
    for (final s in shifts) {
      if (s.userIds.contains(userId)) return s;
    }
    return null;
  }

  /// Creates (empty [ShiftModel.id]) or replaces a shift; returns its id.
  Future<String> saveShift(String code, ShiftModel shift) async {
    final ref = shift.id.isEmpty ? _shifts(code).doc() : _shifts(code).doc(shift.id);
    await ref.set({...shift.toMap(), 'updatedAt': FieldValue.serverTimestamp()});
    return ref.id;
  }

  Future<void> deleteShift(String code, String shiftId) =>
      _shifts(code).doc(shiftId).delete();

  /// Puts [userIds] on [shiftId], taking them off any other shift, in one batch.
  Future<void> assignUsers(String code, String shiftId, List<String> userIds) async {
    if (userIds.isEmpty) return;
    final all = await getShifts(code);
    final batch = _db.batch();
    for (final s in all) {
      if (s.id == shiftId) continue;
      final here = userIds.where(s.userIds.contains).toList();
      if (here.isNotEmpty) {
        batch.update(_shifts(code).doc(s.id), {'userIds': FieldValue.arrayRemove(here)});
      }
    }
    batch.update(_shifts(code).doc(shiftId), {'userIds': FieldValue.arrayUnion(userIds)});
    await batch.commit();
  }

  Future<void> removeUsers(String code, String shiftId, List<String> userIds) =>
      _shifts(code).doc(shiftId).update({'userIds': FieldValue.arrayRemove(userIds)});
}
