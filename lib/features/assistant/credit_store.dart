import 'package:cloud_firestore/cloud_firestore.dart';
import 'ist_date.dart';

/// Today's AI credits (one per model call) and the log of requests the
/// assistant could not handle. Stored at AssistantLog/{userId}/Dates/{day};
/// Firestore rules enforce the limit, so this is only the friendly layer.
abstract class CreditStore {
  Future<int> usedToday();

  /// Uses one credit if fewer than [limit] are used; false if the day's
  /// credits are all gone.
  Future<bool> tryUse(int limit);

  /// Adds a log entry (kind: declined | error | too_many_steps).
  Future<void> log(Map<String, dynamic> entry);
}

class FirestoreCreditStore implements CreditStore {
  final String userId;
  final FirebaseFirestore _db;
  final DateTime Function() _now;

  FirestoreCreditStore(this.userId,
      {FirebaseFirestore? db, DateTime Function()? now})
      : _db = db ?? FirebaseFirestore.instance,
        _now = now ?? DateTime.now;

  DocumentReference<Map<String, dynamic>> get _doc => _db
      .collection('AssistantLog')
      .doc(userId)
      .collection('Dates')
      .doc(istDateString(_now()));

  @override
  Future<int> usedToday() async {
    final snap = await _doc.get();
    return (snap.data()?['credits'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<bool> tryUse(int limit) => _db.runTransaction((tx) async {
        final snap = await tx.get(_doc);
        final used = (snap.data()?['credits'] as num?)?.toInt() ?? 0;
        if (used >= limit) return false;
        if (snap.exists) {
          tx.update(_doc, {'credits': used + 1});
        } else {
          tx.set(_doc, {'credits': 1, 'entries': <Object>[]});
        }
        return true;
      });

  @override
  Future<void> log(Map<String, dynamic> entry) async {
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(_doc);
        if (snap.exists) {
          tx.update(_doc, {'entries': FieldValue.arrayUnion([entry])});
        } else {
          tx.set(_doc, {'credits': 0, 'entries': [entry]});
        }
      });
    } catch (_) {
      // Logging is best effort and must never break the chat.
    }
  }
}
