import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../models/user_model.dart';
import '../models/tracking_model.dart';
import '../models/visit_model.dart';
import '../models/location_model.dart';
import '../models/monthly_summary_model.dart';
import 'locations_box_lock.dart';

class LocalStorageService {
  static late Box _userBox;
  static late Box _trackingBox; // was _attendanceBox
  static late Box _visitsBox;
  static late Box _locationsBox;
  static late Box _reportsBox;
  static late Box _settingsBox;

  // Owned EXCLUSIVELY by the location-tracking background isolate — see
  // AppConstants.trackingCursorBox. Only ever assigned by [openCursorBoxOnly],
  // which only that isolate calls; the main isolate's [init] never opens it.
  static late Box _cursorBox;

  static Future<void> init() async {
    await Hive.initFlutter();
    // Hold this for the app's entire process lifetime, before opening
    // locationsBox/settingsBox — see LocationsBoxLock for the protocol this
    // implements. Bounded so a stuck lock can never block app startup.
    try {
      await LocationsBoxLock.acquireForSession()
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      print('[LocalStorageService] Could not acquire locations_box lock at '
          'startup within 10s ($e) — proceeding without it. The FCM sync '
          "path's cross-isolate guard will be weaker this session.");
    }
    _userBox = await Hive.openBox(AppConstants.userBox);
    _trackingBox = await Hive.openBox(AppConstants.attendanceBox); // same box, new purpose
    _visitsBox = await Hive.openBox(AppConstants.visitsBox);
    _locationsBox = await Hive.openBox(AppConstants.locationsBox);
    _reportsBox = await Hive.openBox(AppConstants.reportsBox);
    _settingsBox = await Hive.openBox(AppConstants.settingsBox);
  }

  /// Opens locationsBox + settingsBox fresh — for the FCM watchdog
  /// handler's isolate ONLY. The caller must already hold
  /// [LocationsBoxLock] before calling this (see
  /// LocationSyncService.ensureRunningAndSync) — the main isolate opens
  /// these boxes once in [init] and keeps them open for its whole lifetime,
  /// so this is never called from there.
  static Future<void> openLocationsBoxForSync() async {
    await Hive.initFlutter();
    _locationsBox = await Hive.openBox(AppConstants.locationsBox);
    _settingsBox = await Hive.openBox(AppConstants.settingsBox);
  }

  /// Opens the tracking-cursor box. Called ONLY by the location-tracking
  /// background isolate (`location_tracking_service.dart`) — never by the
  /// main isolate. Hive does not support one box being opened by two
  /// isolates concurrently (separate isolates get separate in-memory box
  /// instances over the same file, and concurrent writes can corrupt it) —
  /// keeping this box's ownership strictly single-isolate is what makes
  /// [getCurrentBatch]/[getPendingSampleCount]/[getLastConfirmedPoint]/etc.
  /// below safe to call without any reload/close-reopen dance.
  static Future<void> openCursorBoxOnly() async {
    await Hive.initFlutter();
    _cursorBox = await Hive.openBox(AppConstants.trackingCursorBox);
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

  // ─── Today's tracking state — HomeBloc/main isolate (locationsBox) ────────
  //
  // finalLocations — OSRM-snapped, exactly mirrors the Firestore locations doc.
  // finalLocationsDistance — OSRM total for all committed batches.
  //
  // currentBatch/pendingSampleCount/lastConfirmedPoint are NOT here — they
  // live in the isolate-owned cursor box below. HomeBloc reaches them only
  // via LocationTrackingService messages, never directly.

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

  static Future<void> saveFinalLocationsDistance(double km) async =>
      _settingsBox.put(AppConstants.finalLocationsDistanceKey, km);

  static double getFinalLocationsDistance() =>
      (_settingsBox.get(AppConstants.finalLocationsDistanceKey) as num?)
          ?.toDouble() ??
      0.0;

  static bool isLocationSizeLimitHit() =>
      _settingsBox.get(AppConstants.locationSizeLimitHitKey) == true;

  /// Records that today's Tracking doc hit Firestore's size limit —
  /// idempotent: only actually writes (and returns true) the first time.
  /// Returns false if it was already known, so callers can tell "this call
  /// is what just discovered it" (worth notifying the user) apart from
  /// "already knew, nothing new to say."
  static Future<bool> markLocationSizeLimitHitIfNew() async {
    if (isLocationSizeLimitHit()) return false;
    await _settingsBox.put(AppConstants.locationSizeLimitHitKey, true);
    return true;
  }

  /// Clears HomeBloc's own tracking-state keys. Called on fresh punch-in to
  /// start clean. Does NOT touch the isolate's cursor box — that's cleared
  /// by the isolate itself when it receives a `fresh: true` setParams (see
  /// LocationTrackingService.start).
  static Future<void> clearTodayTrackingState() async {
    await _locationsBox.delete(AppConstants.finalLocationsKey);
    await _settingsBox.delete(AppConstants.finalLocationsDistanceKey);
    await _settingsBox.delete(AppConstants.currentTrackingIdKey);
    await _settingsBox.delete(AppConstants.locationSizeLimitHitKey);
  }

  // ─── Tracking cursor state — background isolate ONLY (trackingCursorBox) ──
  // See AppConstants.trackingCursorBox for why this box is isolate-exclusive.

  static Future<void> saveCurrentBatch(List<LocationPoint> points) async {
    await _cursorBox.put(
        AppConstants.currentBatchKey,
        jsonEncode(points.map((p) => p.toJson()).toList()));
  }

  static List<LocationPoint> getCurrentBatch() {
    final raw = _cursorBox.get(AppConstants.currentBatchKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((e) => LocationPoint.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<void> savePendingSampleCount(int count) async {
    await _cursorBox.put(AppConstants.pendingSampleCountKey, count);
  }

  static int getPendingSampleCount() =>
      (_cursorBox.get(AppConstants.pendingSampleCountKey) as num?)
          ?.toInt() ??
      0;

  static Future<void> saveLastConfirmedPoint(LocationPoint? point) async {
    if (point == null) {
      await _cursorBox.delete(AppConstants.lastConfirmedPointKey);
    } else {
      await _cursorBox.put(
          AppConstants.lastConfirmedPointKey, jsonEncode(point.toJson()));
    }
  }

  static LocationPoint? getLastConfirmedPoint() {
    final raw = _cursorBox.get(AppConstants.lastConfirmedPointKey);
    if (raw == null) return null;
    return LocationPoint.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
  }

  /// Clears all cursor-box keys. Called by the isolate on a fresh punch-in
  /// (`fresh: true` setParams) so a new session starts with no leftover
  /// state from a previous day/session.
  static Future<void> clearCursorState() async {
    await _cursorBox.delete(AppConstants.currentBatchKey);
    await _cursorBox.delete(AppConstants.pendingSampleCountKey);
    await _cursorBox.delete(AppConstants.lastConfirmedPointKey);
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
