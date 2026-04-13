import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../models/user_model.dart';
import '../models/attendance_model.dart';
import '../models/visit_model.dart';
import '../models/location_model.dart';

class LocalStorageService {
  static late Box _userBox;
  static late Box _attendanceBox;
  static late Box _visitsBox;
  static late Box _locationsBox;
  static late Box _reportsBox;
  static late Box _settingsBox;

  static Future<void> init() async {
    await Hive.initFlutter();
    _userBox = await Hive.openBox(AppConstants.userBox);
    _attendanceBox = await Hive.openBox(AppConstants.attendanceBox);
    _visitsBox = await Hive.openBox(AppConstants.visitsBox);
    _locationsBox = await Hive.openBox(AppConstants.locationsBox);
    _reportsBox = await Hive.openBox(AppConstants.reportsBox);
    _settingsBox = await Hive.openBox(AppConstants.settingsBox);
  }

  // ─── User ────────────────────────────────────────────────────────────────
  static Future<void> saveUser(UserModel user) async {
    await _userBox.put(AppConstants.currentUserKey, jsonEncode(user.toJson()));
  }

  static UserModel? getUser() {
    final raw = _userBox.get(AppConstants.currentUserKey);
    if (raw == null) return null;
    return UserModel.fromJson(jsonDecode(raw));
  }

  static Future<void> clearUser() async {
    await _userBox.delete(AppConstants.currentUserKey);
  }

  // ─── Attendance ──────────────────────────────────────────────────────────
  static Future<void> saveAttendance(AttendanceModel attendance) async {
    await _attendanceBox.put(attendance.date, jsonEncode(attendance.toJson()));
  }

  static AttendanceModel? getAttendance(String date) {
    final raw = _attendanceBox.get(date);
    if (raw == null) return null;
    return AttendanceModel.fromJson(jsonDecode(raw));
  }

  static List<AttendanceModel> getAllAttendance() {
    return _attendanceBox.values
        .map((raw) => AttendanceModel.fromJson(jsonDecode(raw)))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  // ─── Visits ──────────────────────────────────────────────────────────────
  static Future<void> saveVisit(VisitModel visit) async {
    await _visitsBox.put(visit.id, jsonEncode(visit.toJson()));
  }

  static Future<void> deleteVisit(String visitId) async {
    await _visitsBox.delete(visitId);
  }

  static VisitModel? getVisit(String visitId) {
    final raw = _visitsBox.get(visitId);
    if (raw == null) return null;
    return VisitModel.fromJson(jsonDecode(raw));
  }

  static List<VisitModel> getAllVisits() {
    return _visitsBox.values
        .map((raw) => VisitModel.fromJson(jsonDecode(raw)))
        .toList()
      ..sort((a, b) => b.checkinTimestamp.compareTo(a.checkinTimestamp));
  }

  static List<String> getDistinctClientNames() {
    return getAllVisits().map((v) => v.clientName).toSet().toList()..sort();
  }

  // ─── Today's Locations (only stored for current day) ────────────────────
  static Future<void> saveTodayLocations(List<LocationPoint> points) async {
    final json = points.map((p) => p.toJson()).toList();
    await _locationsBox.put(AppConstants.todayLocationsKey, jsonEncode(json));
  }

  static List<LocationPoint> getTodayLocations() {
    final raw = _locationsBox.get(AppConstants.todayLocationsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => LocationPoint.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  static Future<void> clearTodayLocations() async {
    await _locationsBox.delete(AppConstants.todayLocationsKey);
  }

  // ─── Reports cache (per reportUserId) ───────────────────────────────────
  static Future<void> saveReportData(String reportUserId, Map<String, dynamic> data) async {
    await _reportsBox.put(reportUserId, jsonEncode(data));
  }

  static Map<String, dynamic>? getReportData(String reportUserId) {
    final raw = _reportsBox.get(reportUserId);
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw));
  }

  // Save report locations separately (merged into existing)
  static Future<void> mergeReportLocations(
      String reportUserId, String date, List<LocationPoint> points) async {
    final existing = getReportData(reportUserId) ?? {};
    final locations = Map<String, dynamic>.from(existing['locations'] ?? {});
    locations[date] = points.map((p) => p.toJson()).toList();
    existing['locations'] = locations;
    await saveReportData(reportUserId, existing);
  }

  static List<LocationPoint> getReportLocations(String reportUserId, String date) {
    final data = getReportData(reportUserId);
    if (data == null) return [];
    final locations = data['locations'] as Map<String, dynamic>?;
    if (locations == null || !locations.containsKey(date)) return [];
    return (locations[date] as List<dynamic>)
        .map((e) => LocationPoint.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ─── Distance tracking ───────────────────────────────────────────────────────
  /// OSRM-accurate road distance up to the last snapped batch.
  static Future<void> saveTotalDistance(double km) async =>
      _settingsBox.put(AppConstants.totalDistanceKey, km);

  static double getTotalDistance() =>
      (_settingsBox.get(AppConstants.totalDistanceKey) as num?)?.toDouble() ?? 0.0;

  /// OSRM total + haversine estimate for dirty (unsnapped) points.
  /// This is what the UI shows as the current distance.
  static Future<void> saveTotalDistanceDirty(double km) async =>
      _settingsBox.put(AppConstants.totalDistanceDirtyKey, km);

  static double getTotalDistanceDirty() =>
      (_settingsBox.get(AppConstants.totalDistanceDirtyKey) as num?)?.toDouble() ?? 0.0;

  static Future<void> clearDistances() async {
    await _settingsBox.delete(AppConstants.totalDistanceKey);
    await _settingsBox.delete(AppConstants.totalDistanceDirtyKey);
  }

  // ─── Settings ────────────────────────────────────────────────────────────
  static Future<void> setSetting(String key, dynamic value) async {
    await _settingsBox.put(key, value);
  }

  static T? getSetting<T>(String key) {
    return _settingsBox.get(key) as T?;
  }

  static Future<void> clearAll() async {
    await _userBox.clear();
    await _attendanceBox.clear();
    await _visitsBox.clear();
    await _locationsBox.clear();
    await _reportsBox.clear();
    await _settingsBox.clear();
  }
}
