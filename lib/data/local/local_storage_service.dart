import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../models/user_model.dart';
import '../models/tracking_model.dart';
import '../models/visit_model.dart';
import '../models/location_model.dart';
import '../models/monthly_summary_model.dart';

class LocalStorageService {
  static late Box _userBox;
  static late Box _trackingBox; // was _attendanceBox
  static late Box _visitsBox;
  static late Box _locationsBox;
  static late Box _reportsBox;
  static late Box _settingsBox;

  static Future<void> init() async {
    await Hive.initFlutter();
    _userBox = await Hive.openBox(AppConstants.userBox);
    _trackingBox = await Hive.openBox(AppConstants.attendanceBox); // same box, new purpose
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

  // ─── Tracking (own user) ──────────────────────────────────────────────────

  /// Saves a TrackingModel keyed by its doc ID ('{date}_{HHmmss}').
  static Future<void> saveTracking(TrackingModel tracking) async {
    await _trackingBox.put(tracking.id, jsonEncode(tracking.toJson()));
  }

  static TrackingModel? getTracking(String trackingId) {
    final raw = _trackingBox.get(trackingId);
    if (raw == null) return null;
    return TrackingModel.fromJson(jsonDecode(raw));
  }

  /// Stores the doc ID of the currently active session so HomeBloc can look it
  /// up without a Firestore round-trip on app restart.
  static Future<void> saveActiveTrackingId(String? trackingId) async {
    if (trackingId == null) {
      await _settingsBox.delete(AppConstants.currentTrackingIdKey);
    } else {
      await _settingsBox.put(AppConstants.currentTrackingIdKey, trackingId);
    }
  }

  static String? getActiveTrackingId() =>
      _settingsBox.get(AppConstants.currentTrackingIdKey) as String?;

  /// For manager/report views: each userId+date stores a JSON array of sessions.
  static Future<void> saveTrackingsForUser(
      String userId, String date, List<TrackingModel> trackings) async {
    final key = '${userId}_trks_$date';
    await _reportsBox.put(
        key, jsonEncode(trackings.map((t) => t.toJson()).toList()));
  }

  static List<TrackingModel>? getTrackingsForUser(String userId, String date) {
    final raw = _reportsBox.get('${userId}_trks_$date');
    if (raw == null) return null;
    return (jsonDecode(raw) as List<dynamic>)
        .map((e) => TrackingModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
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
          final key =
              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          return key == date;
        })
        .toList()
      ..sort((a, b) => a.checkinTimestamp.compareTo(b.checkinTimestamp));
  }

  /// Report (manager-view) visits for a specific user+date, stored as a JSON array.
  static Future<void> saveReportVisitsForDay(
      String userId, String date, List<VisitModel> visits) async {
    final key = 'visits_${userId}_$date';
    await _reportsBox.put(
        key, jsonEncode(visits.map((v) => v.toJson()).toList()));
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

  // ─── Today's tracking state ───────────────────────────────────────────────
  //
  // Two arrays:
  //   finalLocations  — OSRM-snapped, exactly mirrors the Firestore locations doc
  //   currentBatch    — raw GPS since the last committed batch, not yet in Firestore
  //
  // Two distances:
  //   finalLocationsDistance  — OSRM total for all committed batches
  //   currentBatchDistance    — live haversine estimate for currentBatch points

  static Future<void> saveFinalLocations(List<LocationPoint> points) async {
    await _locationsBox.put(
        AppConstants.finalLocationsKey,
        jsonEncode(points.map((p) => p.toJson()).toList()));
  }

  static List<LocationPoint> getFinalLocations() {
    final raw = _locationsBox.get(AppConstants.finalLocationsKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((e) => LocationPoint.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<void> saveCurrentBatch(List<LocationPoint> points) async {
    await _locationsBox.put(
        AppConstants.currentBatchKey,
        jsonEncode(points.map((p) => p.toJson()).toList()));
  }

  static List<LocationPoint> getCurrentBatch() {
    final raw = _locationsBox.get(AppConstants.currentBatchKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((e) => LocationPoint.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<void> saveFinalLocationsDistance(double km) async =>
      _settingsBox.put(AppConstants.finalLocationsDistanceKey, km);

  static double getFinalLocationsDistance() =>
      (_settingsBox.get(AppConstants.finalLocationsDistanceKey) as num?)
          ?.toDouble() ??
      0.0;

  static Future<void> saveCurrentBatchDistance(double km) async =>
      _settingsBox.put(AppConstants.currentBatchDistanceKey, km);

  static double getCurrentBatchDistance() =>
      (_settingsBox.get(AppConstants.currentBatchDistanceKey) as num?)
          ?.toDouble() ??
      0.0;

  /// Clears all tracking-state keys. Called on fresh punch-in to start clean.
  static Future<void> clearTodayTrackingState() async {
    await _locationsBox.delete(AppConstants.finalLocationsKey);
    await _locationsBox.delete(AppConstants.currentBatchKey);
    await _settingsBox.delete(AppConstants.finalLocationsDistanceKey);
    await _settingsBox.delete(AppConstants.currentBatchDistanceKey);
    await _settingsBox.delete(AppConstants.currentTrackingIdKey);
  }

  // ─── Persisted locations for any user+date ────────────────────────────────
  // Used for past days and manager views (keyed by userId+trackingId).

  static Future<void> saveLocationsForTracking(
      String userId, String trackingId, List<LocationPoint> points) async {
    await _locationsBox.put(
        '${userId}_locs_$trackingId',
        jsonEncode(points.map((p) => p.toJson()).toList()));
  }

  static List<LocationPoint> getLocationsForTracking(
      String userId, String trackingId) {
    final raw = _locationsBox.get('${userId}_locs_$trackingId');
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((e) => LocationPoint.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ─── Reports cache (per reportUserId) ────────────────────────────────────
  static Future<void> saveReportData(
      String reportUserId, Map<String, dynamic> data) async {
    await _reportsBox.put(reportUserId, jsonEncode(data));
  }

  static Map<String, dynamic>? getReportData(String reportUserId) {
    final raw = _reportsBox.get(reportUserId);
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw));
  }

  // ─── Monthly Summary Cache ────────────────────────────────────────────────
  static String _monthlyKey(String userId, String monthKey) =>
      '${AppConstants.monthlyCachePrefix}${userId}_$monthKey';

  static Future<void> saveMonthlySummary(
      String userId, String monthKey, MonthlySummaryModel summary) async {
    await _settingsBox.put(
        _monthlyKey(userId, monthKey), jsonEncode(summary.toJson()));
  }

  static MonthlySummaryModel? getMonthlySummary(
      String userId, String monthKey) {
    final raw = _settingsBox.get(_monthlyKey(userId, monthKey));
    if (raw == null) return null;
    return MonthlySummaryModel.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw)));
  }

  static bool isMonthEmpty(String userId, String monthKey) =>
      _settingsBox.get('monthly_empty_${userId}_$monthKey') == true;

  static Future<void> markMonthEmpty(String userId, String monthKey) async =>
      _settingsBox.put('monthly_empty_${userId}_$monthKey', true);

  // ─── Settings ─────────────────────────────────────────────────────────────
  static Future<void> setSetting(String key, dynamic value) async {
    await _settingsBox.put(key, value);
  }

  static T? getSetting<T>(String key) {
    return _settingsBox.get(key) as T?;
  }

  static Future<void> clearAll() async {
    await _userBox.clear();
    await _trackingBox.clear();
    await _visitsBox.clear();
    await _locationsBox.clear();
    await _reportsBox.clear();
    await _settingsBox.clear();
  }
}
