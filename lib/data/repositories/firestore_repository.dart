import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../../core/constants/app_constants.dart';
import '../models/user_model.dart';
import '../models/org_code_model.dart';
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
    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (idToken == null) return null;
    final uri = Uri.parse(
      'https://asia-south1-agoriya-app.cloudfunctions.net/getUserByPhone',
    );
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({'phoneNumber': phone}),
    );
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['user'] == null) return null;
    final data = body['user'] as Map<String, dynamic>;
    return UserModel(
      id: data['id'] as String,
      uid: data['uid'] as String? ?? '',
      firstName: data['firstName'] as String? ?? '',
      lastName: data['lastName'] as String? ?? '',
      phoneNumber: data['phoneNumber'] as String? ?? '',
      managerId: data['managerId'] as String?,
      reports: Map<String, dynamic>.from(data['reports'] ?? {}),
      code: data['code'] as String?,
    );
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
  // ─── Org Codes ───────────────────────────────────────────────────────────
  CollectionReference get _codes =>
      _db.collection(AppConstants.codesCollection);

  Future<OrgCodeModel?> getOrgCode(String code) async {
    final doc = await _codes.doc(code).get();
    if (!doc.exists) return null;
    return OrgCodeModel.fromFirestore(doc);
  }

  /// Generates a unique 6-char alphanumeric code and creates the Codes doc.
  Future<String> createOrgCode(String ownerId) async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no O/0/1/I ambiguity
    final rand = Random.secure();
    for (int attempts = 0; attempts < 10; attempts++) {
      final code = List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
      final doc = await _codes.doc(code).get();
      if (!doc.exists) {
        await _codes.doc(code).set({
          'userId': ownerId,
          'totalUserCount': 5,
          'currentUserCount': 1,
        });
        return code;
      }
    }
    throw Exception('Could not generate unique org code');
  }

  Future<void> incrementOrgUserCount(String code) async {
    await _codes.doc(code).update({'currentUserCount': FieldValue.increment(1)});
  }

  Future<void> decrementOrgUserCount(String code) async {
    await _codes.doc(code).update({'currentUserCount': FieldValue.increment(-1)});
  }

  /// All users who share this org code.
  /// Calls the unauthenticated Cloud Function — needed before login when
  /// Firestore rules would otherwise block the query.
  Future<List<UserModel>> getOrgMembers(String code) async {
    final uri = Uri.parse(
      'https://asia-south1-agoriya-app.cloudfunctions.net/getOrgMembers?code=$code',
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to load org members');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final members = (body['members'] as List).map((m) {
      return UserModel(
        id: m['id'] as String,
        uid: m['uid'] as String? ?? '',
        firstName: m['firstName'] as String? ?? '',
        lastName: m['lastName'] as String? ?? '',
        phoneNumber: '',
      );
    }).toList();
    return members;
  }

  /// Removes [userId] from the org:
  ///  - clears their managerId and code
  ///  - removes them from their manager's reports map
  ///  - decrements currentUserCount in Codes
  Future<void> removeUserFromOrg(String userId) async {
    final user = await getUserById(userId);
    if (user == null) return;
    if (user.reports.isNotEmpty) {
      throw Exception('cannot_remove_has_reports');
    }
    final batch = _db.batch();

    batch.update(_users.doc(userId), {'managerId': null, 'code': null});

    if (user.managerId != null) {
      final manager = await getUserById(user.managerId!);
      if (manager != null) {
        final updatedReports = _removeFromReportsMap(manager.reports, userId);
        batch.update(_users.doc(manager.id), {'reports': updatedReports});
      }
    }

    if (user.code != null && user.code!.isNotEmpty) {
      batch.update(_codes.doc(user.code!), {
        'currentUserCount': FieldValue.increment(-1),
      });
    }

    await batch.commit();
  }

  /// Recursively removes [userId] from any level of the reports map.
  Map<String, dynamic> _removeFromReportsMap(
      Map<String, dynamic> reports, String userId) {
    if (reports.containsKey(userId)) {
      return Map.from(reports)..remove(userId);
    }
    return reports.map((k, v) {
      final entry = Map<String, dynamic>.from(v as Map);
      final sub = Map<String, dynamic>.from(entry['reports'] as Map? ?? {});
      return MapEntry(k, {...entry, 'reports': _removeFromReportsMap(sub, userId)});
    });
  }
}
