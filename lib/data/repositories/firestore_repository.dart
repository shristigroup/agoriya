import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../../core/constants/app_constants.dart';
import '../models/user_model.dart';
import '../models/tracking_model.dart';
import '../models/visit_model.dart';
import '../models/location_model.dart';
import '../models/monthly_summary_model.dart';

class FirestoreRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ─── Users ───────────────────────────────────────────────────────────────
  CollectionReference get _users =>
      _db.collection(AppConstants.usersCollection);

  Future<List<UserModel>> getAllUsers() async {
    final snap = await _users.get();
    return snap.docs.map((d) => UserModel.fromFirestore(d)).toList();
  }

  Future<List<UserModel>> getUsersByManagerId(String managerId) async {
    final snap =
        await _users.where('managerId', isEqualTo: managerId).get();
    return snap.docs.map((d) => UserModel.fromFirestore(d)).toList();
  }

  Future<UserModel?> getUserByPhone(String phone) async {
    final snap = await _users
        .where('phoneNumber', isEqualTo: phone)
        .limit(1)
        .get();
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

  // ─── Tracking ─────────────────────────────────────────────────────────────
  CollectionReference _trackingCol(String userId) =>
      _users.doc(userId).collection(AppConstants.trackingCollection);

  DocumentReference _trackingDoc(String userId, String trackingId) =>
      _trackingCol(userId).doc(trackingId);

  /// Returns the most recent open (no stopTime) Tracking doc, or null.
  Future<TrackingModel?> getActiveTracking(String userId) async {
    final snap = await _trackingCol(userId)
        .where('stopTime', isNull: true)
        .orderBy('startTime', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return TrackingModel.fromFirestore(snap.docs.first);
  }

  /// Returns the latest Tracking doc regardless of active state.
  Future<TrackingModel?> getLatestTracking(String userId) async {
    final snap = await _trackingCol(userId)
        .orderBy('startTime', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return TrackingModel.fromFirestore(snap.docs.first);
  }

  Future<TrackingModel?> getTrackingById(
      String userId, String trackingId) async {
    final doc = await _trackingDoc(userId, trackingId).get();
    if (!doc.exists) return null;
    return TrackingModel.fromFirestore(doc);
  }

  /// Creates a new Tracking doc. Fetches the most recent doc (no composite
  /// index needed — single-field orderBy) and closes it if still open, ensuring
  /// there is never more than one active session.
  Future<void> createTracking(String userId, TrackingModel tracking) async {
    final latest = await getLatestTracking(userId);
    if (latest != null && latest.isActive && latest.id != tracking.id) {
      await _trackingDoc(userId, latest.id).update({
        'stopTime': Timestamp.fromDate(DateTime.now()),
      });
    }
    await _trackingDoc(userId, tracking.id).set(tracking.toFirestore());
  }

  /// Sets stopTime on the Tracking doc (punch-out).
  Future<void> closeTracking(
      String userId, String trackingId, DateTime stopTime) async {
    await _trackingDoc(userId, trackingId).update({
      'stopTime': Timestamp.fromDate(stopTime),
    });
  }

  /// Clears stopTime (resume session).
  Future<void> resumeTracking(String userId, String trackingId) async {
    await _trackingDoc(userId, trackingId).update({
      'stopTime': FieldValue.delete(),
    });
  }

  /// Overwrites the full locations array and distance on the Tracking doc.
  /// Used for both movement batches and stationary-only flushes (where
  /// allLocations == finalLocations with an updated last-point durationSeconds).
  Future<void> writeLocations(
    String userId,
    String trackingId,
    List<LocationPoint> allLocations,
    double distanceKm,
  ) async {
    await _trackingDoc(userId, trackingId).update({
      'locations': allLocations.map((p) => p.toFirestore()).toList(),
      'distance': distanceKm,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Increments visitCount on the active Tracking doc.
  Future<void> incrementTrackingVisitCount(
      String userId, String trackingId) async {
    await _trackingDoc(userId, trackingId)
        .update({'visitCount': FieldValue.increment(1)});
  }

  /// Paginated history — newest first, up to [limit] docs.
  Future<(List<TrackingModel>, String?)> getTrackingHistory(
    String userId, {
    int limit = 30,
    String? startAfterId,
  }) async {
    Query query = _trackingCol(userId)
        .orderBy('startTime', descending: true)
        .limit(limit);

    if (startAfterId != null) {
      final cursor = await _trackingDoc(userId, startAfterId).get();
      if (cursor.exists) query = query.startAfterDocument(cursor);
    }

    final snap = await query.get();
    final models =
        snap.docs.map((d) => TrackingModel.fromFirestore(d)).toList();
    final cursor =
        snap.docs.length == limit ? snap.docs.last.id : null;
    return (models, cursor);
  }

  /// All Tracking docs for a specific date (YYYY-MM-DD), newest first.
  Future<List<TrackingModel>> getTrackingForDate(
      String userId, String date) async {
    final start = DateTime.parse(date);
    final end = start.add(const Duration(days: 1));
    final snap = await _trackingCol(userId)
        .where('startTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('startTime', isLessThan: Timestamp.fromDate(end))
        .orderBy('startTime', descending: true)
        .get();
    return snap.docs.map((d) => TrackingModel.fromFirestore(d)).toList();
  }

  /// All Tracking docs whose startTime falls within the given month.
  Future<List<TrackingModel>> getTrackingForMonth(
      String userId, String monthKey) async {
    final start = DateTime.parse('$monthKey-01');
    final end = DateTime(start.year, start.month + 1, 1);
    final snap = await _trackingCol(userId)
        .where('startTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('startTime', isLessThan: Timestamp.fromDate(end))
        .orderBy('startTime', descending: true)
        .get();
    return snap.docs.map((d) => TrackingModel.fromFirestore(d)).toList();
  }

  /// Returns locations embedded in a Tracking doc.
  Future<List<LocationPoint>> getTrackingLocations(
      String userId, String trackingId) async {
    final doc = await _trackingDoc(userId, trackingId).get();
    if (!doc.exists) return [];
    final data = doc.data() as Map<String, dynamic>;
    final raw = List<Map<String, dynamic>>.from(data['locations'] ?? []);
    final points = raw.map((e) => LocationPoint.fromFirestore(e)).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return points;
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

  Future<void> addComment(
      String userId, String visitId, VisitComment comment) async {
    await _commentsCol(userId, visitId).add(comment.toFirestore());
  }

  Future<List<VisitComment>> getComments(
      String userId, String visitId) async {
    final snap =
        await _commentsCol(userId, visitId).orderBy('timestamp').get();
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
    await _monthlyCol(userId)
        .doc(summary.monthKey)
        .set(summary.toFirestore());
  }

  // ─── Storage ─────────────────────────────────────────────────────────────
  Future<String> uploadPunchInImage(
      String userId, String date, File file) async {
    final ext = file.path.split('.').last;
    final path = AppConstants.punchInImagePath(userId, date, ext);
    final ref = _storage.ref().child(path);
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  Future<String> uploadBillCopy(
      String userId, String visitId, File file) async {
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
