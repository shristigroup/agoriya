import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../../core/constants/app_constants.dart';
import '../models/user_model.dart';
import '../models/attendance_model.dart';
import '../models/visit_model.dart';
import '../models/location_model.dart';
import '../models/monthly_summary_model.dart';

class FirestoreRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ─── Users ───────────────────────────────────────────────────────────────
  CollectionReference get _users => _db.collection(AppConstants.usersCollection);

  Future<List<UserModel>> getAllUsers() async {
    final snap = await _users.get();
    return snap.docs.map((d) => UserModel.fromFirestore(d)).toList();
  }

  Future<List<UserModel>> getUsersByManagerId(String managerId) async {
    final snap = await _users.where('managerId', isEqualTo: managerId).get();
    return snap.docs.map((d) => UserModel.fromFirestore(d)).toList();
  }

  Future<UserModel?> getUserByPhone(String phone) async {
    final snap = await _users.where('phoneNumber', isEqualTo: phone).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return UserModel.fromFirestore(snap.docs.first);
  }

  Future<UserModel?> getUserById(String userId) async {
    final doc = await _users.doc(userId).get();
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc);
  }

  Future<void> createOrUpdateUser(UserModel user) async {
    await _users.doc(user.id).set(user.toFirestore(), SetOptions(merge: true));
  }

  // ─── Attendance ──────────────────────────────────────────────────────────
  CollectionReference _attendanceCol(String userId) =>
      _users.doc(userId).collection(AppConstants.attendanceCollection);

  DocumentReference _attendanceDoc(String userId, String date) =>
      _attendanceCol(userId).doc(date);

  Future<AttendanceModel?> getAttendance(String userId, String date) async {
    final doc = await _attendanceDoc(userId, date).get();
    if (!doc.exists) return null;
    return AttendanceModel.fromFirestore(doc);
  }

  /// Always overwrites the document (no merge) so a "Fresh Punch In" clears
  /// any previous punchOut fields from the same day.
  Future<void> punchIn(String userId, String date, DateTime time, String imageUrl) async {
    await _attendanceDoc(userId, date).set({
      'punchInTimestamp': Timestamp.fromDate(time),
      'punchInImage': imageUrl,
      'distance': 0.0,
      'customerVisitCount': 0,
    });
  }

  Future<void> punchOut(String userId, String date, DateTime time, GeoPoint location) async {
    await _attendanceDoc(userId, date).update({
      'punchOutTimestamp': Timestamp.fromDate(time),
      'punchOutLocation': location,
    });
  }

  /// Clears punchOut fields — triggers Cloud Function to notify the manager.
  Future<void> resumeSession(String userId, String date) async {
    await _attendanceDoc(userId, date).update({
      'punchOutTimestamp': FieldValue.delete(),
      'punchOutLocation': FieldValue.delete(),
    });
  }

  Future<void> updateDistance(String userId, String date, double distanceKm) async {
    await _attendanceDoc(userId, date).update({'distance': distanceKm});
  }

  Future<void> incrementVisitCount(String userId, String date) async {
    await _attendanceDoc(userId, date).update({
      'customerVisitCount': FieldValue.increment(1),
    });
  }

  // ─── Attendance History (paginated, newest-first) ─────────────────────────
  /// Returns up to [limit] attendance records ordered by punch-in time descending.
  /// Pass [startAfterCursor] (an opaque ISO timestamp string) to get the next page.
  /// Returns a tuple of (records, cursor) — cursor is null when there are no more pages.
  Future<(List<AttendanceModel>, String?)> getAttendanceHistory(
    String userId, {
    int limit = 30,
    String? startAfterDate,
  }) async {
    Query query = _attendanceCol(userId)
        .orderBy('punchInTimestamp', descending: true)
        .limit(limit);

    if (startAfterDate != null) {
      final dt = DateTime.parse(startAfterDate);
      query = query.startAfter([Timestamp.fromDate(dt)]);
    }

    final snap = await query.get();
    final models = snap.docs.map((d) => AttendanceModel.fromFirestore(d)).toList();
    String? cursor;
    if (snap.docs.length == limit) {
      final data = snap.docs.last.data() as Map<String, dynamic>;
      final ts = data['punchInTimestamp'] as Timestamp?;
      cursor = ts?.toDate().toIso8601String();
    }
    return (models, cursor);
  }

  /// All attendance docs for a given month ('YYYY-MM'). Used to compute
  /// monthly summaries. Doc IDs are 'YYYY-MM-DD' so lexicographic range works.
  Future<List<AttendanceModel>> getAttendanceForMonth(
      String userId, String monthKey) async {
    final snap = await _attendanceCol(userId)
        .orderBy(FieldPath.documentId)
        .startAt(['$monthKey-01'])
        .endAt(['$monthKey-31'])
        .get();
    return snap.docs.map((d) => AttendanceModel.fromFirestore(d)).toList();
  }

  // ─── Locations ───────────────────────────────────────────────────────────
  DocumentReference _locationsDoc(String userId, String date) =>
      _users.doc(userId).collection(AppConstants.locationsCollection).doc(date);

  Future<DayLocations?> getDayLocations(String userId, String date) async {
    final doc = await _locationsDoc(userId, date).get();
    if (!doc.exists) return null;
    return DayLocations.fromFirestore(doc);
  }

  /// Appends [snapped] points to the locations doc via arrayUnion.
  /// Only ever called with OSRM-snapped points — raw GPS is never written to Firestore.
  Future<void> appendSnappedBatch(
    String userId,
    String date,
    List<LocationPoint> snapped,
  ) async {
    await _locationsDoc(userId, date).set({
      'locations':
          FieldValue.arrayUnion(snapped.map((p) => p.toFirestore()).toList()),
    }, SetOptions(merge: true));
  }

  // ─── Visits ──────────────────────────────────────────────────────────────
  CollectionReference _visitsCol(String userId) =>
      _users.doc(userId).collection(AppConstants.visitsCollection);

  DocumentReference _visitDoc(String userId, String visitId) =>
      _visitsCol(userId).doc(visitId);

  Future<void> createVisit(String userId, VisitModel visit) async {
    await _visitDoc(userId, visit.id).set(visit.toFirestore());
  }

  Future<void> updateVisit(String userId, VisitModel visit) async {
    await _visitDoc(userId, visit.id).update(visit.toFirestore());
  }

  Future<List<VisitModel>> getVisits(String userId) async {
    final snap = await _visitsCol(userId)
        .orderBy('checkinTimestamp', descending: true)
        .get();
    return snap.docs.map((d) => VisitModel.fromFirestore(d)).toList();
  }

  /// Visits within [start, end) — used for per-day and per-month history.
  /// Requires no composite index (range + orderBy on the same field).
  Future<List<VisitModel>> getVisitsByDateRange(
      String userId, DateTime start, DateTime end) async {
    final snap = await _visitsCol(userId)
        .where('checkinTimestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('checkinTimestamp', isLessThan: Timestamp.fromDate(end))
        .orderBy('checkinTimestamp', descending: true)
        .get();
    return snap.docs.map((d) => VisitModel.fromFirestore(d)).toList();
  }

  // ─── Comments ────────────────────────────────────────────────────────────
  CollectionReference _commentsCol(String userId, String visitId) =>
      _visitDoc(userId, visitId).collection(AppConstants.commentsCollection);

  Future<void> addComment(String userId, String visitId, VisitComment comment) async {
    await _commentsCol(userId, visitId).add(comment.toFirestore());
  }

  Future<List<VisitComment>> getComments(String userId, String visitId) async {
    final snap = await _commentsCol(userId, visitId)
        .orderBy('timestamp')
        .get();
    return snap.docs.map((d) => VisitComment.fromFirestore(d)).toList();
  }

  // ─── Monthly Summary ──────────────────────────────────────────────────────
  CollectionReference _monthlyCol(String userId) =>
      _users.doc(userId).collection(AppConstants.monthlyCollection);

  Future<MonthlySummaryModel?> getMonthlySummary(
      String userId, String monthKey) async {
    final doc = await _monthlyCol(userId).doc(monthKey).get();
    if (!doc.exists) return null;
    return MonthlySummaryModel.fromFirestore(doc);
  }

  Future<void> saveMonthlySummary(
      String userId, MonthlySummaryModel summary) async {
    await _monthlyCol(userId).doc(summary.monthKey).set(summary.toFirestore());
  }

  // ─── Storage ─────────────────────────────────────────────────────────────
  Future<String> uploadPunchInImage(String userId, String date, File file) async {
    final ext = file.path.split('.').last;
    final path = AppConstants.punchInImagePath(userId, date, ext);
    final ref = _storage.ref().child(path);
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  Future<String> uploadBillCopy(String userId, String visitId, File file) async {
    final ext = file.path.split('.').last;
    final path = AppConstants.billCopyPath(userId, visitId, ext);
    final ref = _storage.ref().child(path);
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  Future<void> saveFcmToken(String userId, String token) async {
    await _users.doc(userId).update({'fcmToken': token});
  }
}
