import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../../core/constants/app_constants.dart';
import '../../core/utils/app_utils.dart';
import '../models/user_model.dart';
import '../models/attendance_model.dart';
import '../models/visit_model.dart';
import '../models/location_model.dart';

class FirestoreRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ─── Users ───────────────────────────────────────────────────────────────
  CollectionReference get _users => _db.collection(AppConstants.usersCollection);

  Future<List<UserModel>> getAllUsers() async {
    final snap = await _users.get();
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
  DocumentReference _attendanceDoc(String userId, String date) =>
      _users.doc(userId).collection(AppConstants.attendanceCollection).doc(date);

  Future<AttendanceModel?> getAttendance(String userId, String date) async {
    final doc = await _attendanceDoc(userId, date).get();
    if (!doc.exists) return null;
    return AttendanceModel.fromFirestore(doc);
  }

  Future<void> punchIn(String userId, String date, DateTime time, String imageUrl) async {
    await _attendanceDoc(userId, date).set({
      'punchInTimestamp': Timestamp.fromDate(time),
      'punchInImage': imageUrl,
      'distance': 0.0,
      'customerVisitCount': 0,
    }, SetOptions(merge: true));
  }

  Future<void> punchOut(String userId, String date, DateTime time, GeoPoint location) async {
    await _attendanceDoc(userId, date).update({
      'punchOutTimestamp': Timestamp.fromDate(time),
      'punchOutLocation': location,
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

  // ─── Locations ───────────────────────────────────────────────────────────
  DocumentReference _locationsDoc(String userId, String date) =>
      _users.doc(userId).collection(AppConstants.locationsCollection).doc(date);

  Future<void> appendLocations(String userId, String date, List<LocationPoint> points) async {
    final batch = points.map((p) => p.toFirestore()).toList();
    await _locationsDoc(userId, date).set({
      'locations': FieldValue.arrayUnion(batch),
    }, SetOptions(merge: true));
  }

  Future<DayLocations?> getDayLocations(String userId, String date) async {
    final doc = await _locationsDoc(userId, date).get();
    if (!doc.exists) return null;
    return DayLocations.fromFirestore(doc);
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

  // ─── Previous day punch out location ────────────────────────────────────
  Future<AttendanceModel?> getLastAttendance(String userId) async {
    final snap = await _users
        .doc(userId)
        .collection(AppConstants.attendanceCollection)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(2)
        .get();
    // Get second most recent (previous day, not today)
    final today = AppUtils.todayKey();
    for (final doc in snap.docs) {
      if (doc.id != today) return AttendanceModel.fromFirestore(doc);
    }
    return null;
  }

  Future<void> saveFcmToken(String userId, String token) async {
    await _users.doc(userId).update({'fcmToken': token});
  }
}
