import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../models/user_model.dart';
import '../models/attendance_model.dart';
import '../models/visit_model.dart';
import '../models/location_model.dart';
import '../models/monthly_summary_model.dart';

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

  /// For manager/report views: namespaced by userId so they don't collide with own attendance.
  static Future<void> saveAttendanceForUser(String userId, AttendanceModel att) async {
    await _attendanceBox.put('${userId}_att_${att.date}', jsonEncode(att.toJson()));
  }

  static AttendanceModel? getAttendanceForUser(String userId, String date) {
    final raw = _attendanceBox.get('${userId}_att_$date');
    if (raw == null) return null;
    return AttendanceModel.fromJson(jsonDecode(raw));
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

  /// Own-user visits for a specific date (already in _visitsBox keyed by visitId).
  static List<VisitModel> getOwnVisitsForDate(String date) {
    return _visitsBox.values
        .map((raw) => VisitModel.fromJson(jsonDecode(raw)))
        .where((v) {
          final d = v.checkinTimestamp;
          final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          return key == date;
        })
        .toList()
      ..sort((a, b) => a.checkinTimestamp.compareTo(b.checkinTimestamp));
  }

  /// Report (manager-view) visits for a specific user+date, stored as a JSON array.
  static Future<void> saveReportVisitsForDay(
      String userId, String date, List<VisitModel> visits) async {
    final key = 'visits_${userId}_$date';
    await _reportsBox.put(key, jsonEncode(visits.map((v) => v.toJson()).toList()));
  }

  static List<VisitModel>? getReportVisitsForDay(String userId, String date) {
    final raw = _reportsBox.get('visits_${userId}_$date');
    if (raw == null) return null;
    return (jsonDecode(raw) as List<dynamic>)
        .map((e) => VisitModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Sealed flag — marks that all visits for a past day have been fetched from Firestore.
  static bool isVisitsSealed(String userId, String date) =>
      _settingsBox.get('vseal_${userId}_$date') == true;

  static Future<void> sealVisits(String userId, String date) async =>
      _settingsBox.put('vseal_${userId}_$date', true);

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

  /// Persisted locations for any user+date (used for past days and manager views).
  static Future<void> saveLocations(
      String userId, String date, List<LocationPoint> points) async {
    final json = points.map((p) => p.toJson()).toList();
    await _locationsBox.put('${userId}_locs_$date', jsonEncode(json));
  }

  static List<LocationPoint> getLocations(String userId, String date) {
    final raw = _locationsBox.get('${userId}_locs_$date');
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((e) => LocationPoint.fromJson(Map<String, dynamic>.from(e)))
        .toList();
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

  // ─── Monthly Summary Cache ────────────────────────────────────────────────
  /// Key: 'monthly_{userId}_{monthKey}' — works for both own user and manager
  /// viewing a report, since the key is namespaced by userId.
  static String _monthlyKey(String userId, String monthKey) =>
      '${AppConstants.monthlyCachePrefix}${userId}_$monthKey';

  static Future<void> saveMonthlySummary(
      String userId, String monthKey, MonthlySummaryModel summary) async {
    await _settingsBox.put(
        _monthlyKey(userId, monthKey), jsonEncode(summary.toJson()));
  }

  static MonthlySummaryModel? getMonthlySummary(String userId, String monthKey) {
    final raw = _settingsBox.get(_monthlyKey(userId, monthKey));
    if (raw == null) return null;
    return MonthlySummaryModel.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw)));
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
