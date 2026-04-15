import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/app_utils.dart';
import 'local/local_storage_service.dart';
import 'models/attendance_model.dart';
import 'models/location_model.dart';
import 'models/monthly_summary_model.dart';
import 'models/user_model.dart';
import 'models/visit_model.dart';
import 'repositories/firestore_repository.dart';

/// Centralises all cache-policy decisions so that BLoC/UI code never has to
/// reason about "where" data comes from.
///
/// Policy summary:
///  - Own user, today      → Hive is authoritative (user is the data creator).
///  - Any user, past day   → Hive hit = sealed; no Firestore call needed.
///  - Manager, any day     → Hive where possible, Firestore as fallback.
///  - Login / new device   → Hive empty → Firestore fetch → Hive written.
class DataManager {
  static late String _ownerId;
  static final _repo = FirestoreRepository();

  /// Call once, right after the authenticated user is known (in AuthBloc).
  static void init(String ownerId) => _ownerId = ownerId;

  static bool isOwner(String userId) => userId == _ownerId;

  static bool _isPastDay(String date) =>
      date.compareTo(AppUtils.todayKey()) < 0;

  static String get currentMonthKey {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  static bool _isPastMonth(String monthKey) =>
      monthKey.compareTo(currentMonthKey) < 0;

  // ─── Seeding ───────────────────────────────────────────────────────────────

  /// Called on every app start from HomeBloc._onInit.
  /// Compares the cached app version against the current build.
  /// On mismatch (reinstall / update / new device), today's attendance,
  /// visits, and locations are fetched from Firestore and written into Hive.
  static Future<void> seedTodayDataAsAppHasReinstalled(
      String userId, String date) async {
    final info = await PackageInfo.fromPlatform();
    final currentVersion = info.version;
    final cachedVersion =
        LocalStorageService.getSetting<String>(AppConstants.cacheVersionKey);

    if (cachedVersion == currentVersion) return;

    try {
      final attendance = await _repo.getAttendance(userId, date);
      if (attendance != null) {
        await LocalStorageService.saveAttendance(attendance);
      }
    } catch (_) {}

    try {
      final start = DateTime.parse(date);
      final visits = await _repo.getVisitsByDateRange(
          userId, start, start.add(const Duration(days: 1)));
      for (final v in visits) {
        await LocalStorageService.saveVisit(v);
      }
    } catch (_) {}

    try {
      final dayLocs = await _repo.getDayLocations(userId, date);
      final points = dayLocs?.points ?? [];
      if (points.isNotEmpty) {
        // Firestore only ever contains snapped points, so seed into finalLocations.
        await LocalStorageService.saveFinalLocations(points);
      }
    } catch (_) {}

    await LocalStorageService.setSetting(
        AppConstants.cacheVersionKey, currentVersion);
  }

  // ─── Attendance ────────────────────────────────────────────────────────────

  static Future<AttendanceModel?> getAttendance(
      String userId, String date) async {
    if (isOwner(userId)) {
      return LocalStorageService.getAttendance(date);
    }

    // Past day: Hive is sealed after first fetch — no Firestore call needed.
    if (_isPastDay(date)) {
      final cached = LocalStorageService.getAttendanceForUser(userId, date);
      if (cached != null) return cached;
    }

    // Today (or past-day cache miss): always fetch fresh from Firestore.
    final remote = await _repo.getAttendance(userId, date);
    if (remote != null) {
      await LocalStorageService.saveAttendanceForUser(userId, remote);
    }
    return remote;
  }

  // ─── Visits ────────────────────────────────────────────────────────────────

  static Future<List<VisitModel>> getVisitsForDay(
      String userId, String date) async {
    if (isOwner(userId) && !_isPastDay(date)) {
      return LocalStorageService.getOwnVisitsForDate(date);
    }

    if (LocalStorageService.isVisitsSealed(userId, date)) {
      return isOwner(userId)
          ? LocalStorageService.getOwnVisitsForDate(date)
          : (LocalStorageService.getReportVisitsForDay(userId, date) ?? []);
    }

    final start = DateTime.parse(date);
    final visits = await _repo.getVisitsByDateRange(
        userId, start, start.add(const Duration(days: 1)));

    if (isOwner(userId)) {
      for (final v in visits) {
        await LocalStorageService.saveVisit(v);
      }
    } else {
      await LocalStorageService.saveReportVisitsForDay(userId, date, visits);
    }

    if (_isPastDay(date)) {
      await LocalStorageService.sealVisits(userId, date);
    }

    return visits;
  }

  // ─── Locations ─────────────────────────────────────────────────────────────

  static Future<List<LocationPoint>> getLocations(
      String userId, String date) async {
    // Own user today: merge finalLocations (Firestore truth) + currentBatch
    // (unsynced live points). Both arrays are maintained in order so no sort needed.
    if (isOwner(userId) && date == AppUtils.todayKey()) {
      return [
        ...LocalStorageService.getFinalLocations(),
        ...LocalStorageService.getCurrentBatch(),
      ];
    }

    // Past day: Hive is sealed after first fetch — no Firestore call needed.
    if (_isPastDay(date)) {
      final cached = LocalStorageService.getLocations(userId, date);
      if (cached.isNotEmpty) return cached;
    }

    // Today (or past-day cache miss): always fetch fresh from Firestore.
    final dayLocs = await _repo.getDayLocations(userId, date);
    final points = dayLocs?.points ?? [];
    if (points.isNotEmpty) {
      await LocalStorageService.saveLocations(userId, date, points);
    }
    return points;
  }

  // ─── Today's tracking state (own user only) ────────────────────────────────

  static List<LocationPoint> getFinalLocations() =>
      LocalStorageService.getFinalLocations();

  static List<LocationPoint> getCurrentBatch() =>
      LocalStorageService.getCurrentBatch();

  static double getFinalLocationsDistance() =>
      LocalStorageService.getFinalLocationsDistance();

  static double getCurrentBatchDistance() =>
      LocalStorageService.getCurrentBatchDistance();

  /// Returns the display distance: OSRM total + live haversine for currentBatch.
  static double getDisplayDistance(
      String userId, AttendanceModel? attendance) {
    if (isOwner(userId)) {
      return LocalStorageService.getFinalLocationsDistance() +
          LocalStorageService.getCurrentBatchDistance();
    }
    return attendance?.distance ?? 0.0;
  }

  /// Persists a new point into currentBatch + updates currentBatchDistance.
  static Future<void> appendToCurrentBatch(
    List<LocationPoint> updatedBatch,
    double newBatchDistance,
  ) async {
    await LocalStorageService.saveCurrentBatch(updatedBatch);
    await LocalStorageService.saveCurrentBatchDistance(newBatchDistance);
  }

  /// After OSRM snap: writes fresh Firestore read + updated distances to Hive.
  /// Returns the fresh finalLocations (already sorted by DayLocations.fromFirestore).
  static Future<List<LocationPoint>> persistSnappedBatch({
    required String userId,
    required String date,
    required List<LocationPoint> snapped,
    required double newFinalDistance,
    required List<LocationPoint> fallbackFinalLocations,
  }) async {
    await _repo.appendSnappedBatch(userId, date, snapped);
    await _repo.updateDistance(userId, date, newFinalDistance);
    // Read back the full doc so finalLocations exactly mirrors Firestore.
    final freshDayLocs = await _repo.getDayLocations(userId, date);
    final freshFinal = freshDayLocs?.points ?? fallbackFinalLocations;
    await LocalStorageService.saveFinalLocations(freshFinal);
    await LocalStorageService.saveFinalLocationsDistance(newFinalDistance);
    return freshFinal;
  }

  // ─── Punch In ──────────────────────────────────────────────────────────────

  static Future<AttendanceModel> punchIn(
    String userId,
    String date,
    DateTime timestamp,
    String imageUrl,
  ) async {
    final attendance = AttendanceModel(
      date: date,
      punchInTimestamp: timestamp,
      punchInImage: imageUrl,
    );
    await _repo.punchIn(userId, date, timestamp, imageUrl);
    await LocalStorageService.saveAttendance(attendance);
    await LocalStorageService.clearTodayTrackingState();
    return attendance;
  }

  // ─── Punch Out ─────────────────────────────────────────────────────────────

  /// Writes punch-out to Firestore and persists updated attendance + final
  /// locations to Hive. Snapping and distance calculation are done by HomeBloc
  /// before this is called — this method only persists the results.
  static Future<AttendanceModel> punchOut({
    required String userId,
    required String date,
    required AttendanceModel currentAttendance,
    required DateTime timestamp,
    required LatLng? lastLocation,
    required List<LocationPoint> finalLocations,
    required double finalDistance,
  }) async {
    final geoPoint = lastLocation != null
        ? GeoPoint(lastLocation.latitude, lastLocation.longitude)
        : const GeoPoint(0, 0);
    await _repo.punchOut(userId, date, timestamp, geoPoint);
    final updated = currentAttendance.copyWith(
      punchOutTimestamp: timestamp,
      punchOutLocation: lastLocation,
      distance: finalDistance,
    );
    await LocalStorageService.saveAttendance(updated);
    // Persist the final locations under the namespaced past-day key so
    // history screens can read them without a Firestore round-trip.
    await LocalStorageService.saveLocations(userId, date, finalLocations);
    return updated;
  }

  // ─── Resume Session ────────────────────────────────────────────────────────

  static Future<AttendanceModel> resumeSession(
    String userId,
    String date,
    AttendanceModel currentAttendance,
  ) async {
    await _repo.resumeSession(userId, date);
    final resumed = AttendanceModel(
      date: currentAttendance.date,
      punchInTimestamp: currentAttendance.punchInTimestamp,
      punchOutTimestamp: null,
      punchInImage: currentAttendance.punchInImage,
      distance: currentAttendance.distance,
      punchOutLocation: null,
      customerVisitCount: currentAttendance.customerVisitCount,
    );
    await LocalStorageService.saveAttendance(resumed);
    return resumed;
  }

  // ─── Monthly Summary ───────────────────────────────────────────────────────

  static MonthlySummaryModel? getCachedMonthlySummary(
          String userId, String monthKey) =>
      LocalStorageService.getMonthlySummary(userId, monthKey);

  static Future<MonthlySummaryModel?> getMonthlySummary(
      String userId, String monthKey) async {
    if (!_isPastMonth(monthKey)) {
      final summary = await computeMonthlySummary(userId, monthKey);
      if (summary == null) return null;
      await _repo.saveMonthlySummary(userId, summary);
      await LocalStorageService.saveMonthlySummary(userId, monthKey, summary);
      return summary;
    }

    if (LocalStorageService.isMonthEmpty(userId, monthKey)) return null;

    final cached = LocalStorageService.getMonthlySummary(userId, monthKey);
    if (cached != null) {
      if (cached.punchCount == 0 && cached.totalVisits == 0) {
        await LocalStorageService.markMonthEmpty(userId, monthKey);
        return null;
      }
      return cached;
    }

    final fromDb = await _repo.getMonthlySummary(userId, monthKey);
    if (fromDb != null) {
      await LocalStorageService.saveMonthlySummary(userId, monthKey, fromDb);
      return fromDb;
    }

    final summary = await computeMonthlySummary(userId, monthKey);
    if (summary == null) {
      await LocalStorageService.markMonthEmpty(userId, monthKey);
      return null;
    }
    await _repo.saveMonthlySummary(userId, summary);
    await LocalStorageService.saveMonthlySummary(userId, monthKey, summary);
    return summary;
  }

  static Future<MonthlySummaryModel?> computeMonthlySummary(
      String userId, String monthKey) async {
    final attendance = await _repo.getAttendanceForMonth(userId, monthKey);
    if (attendance.isEmpty) return null;

    final monthStart = DateTime.parse('$monthKey-01');
    final monthEnd =
        DateTime(monthStart.year, monthStart.month + 1, 1);
    final visits =
        await _repo.getVisitsByDateRange(userId, monthStart, monthEnd);

    int punchCount = 0;
    int totalMinutes = 0;
    double totalDistance = 0;
    for (final att in attendance) {
      if (att.isPunchedIn) punchCount++;
      totalMinutes += att.attendanceDuration.inMinutes;
      totalDistance += att.distance;
    }

    final totalExpense =
        visits.fold<double>(0, (s, v) => s + (v.expenseAmount ?? 0));

    return MonthlySummaryModel(
      monthKey: monthKey,
      punchCount: punchCount,
      totalHours: totalMinutes ~/ 60,
      totalMinutes: totalMinutes % 60,
      totalDistanceKm: totalDistance.round(),
      totalVisits: visits.length,
      totalExpense: totalExpense.round(),
      computedAt: DateTime.now(),
    );
  }

  // ─── Visits (write path) ──────────────────────────────────────────────────

  static Future<AttendanceModel?> createVisit(
    String userId,
    VisitModel visit,
    String date,
    AttendanceModel? currentAttendance,
  ) async {
    await _repo.createVisit(userId, visit);
    await LocalStorageService.saveVisit(visit);
    await _repo.incrementVisitCount(userId, date);
    if (currentAttendance == null) return null;
    final updated = currentAttendance.copyWith(
      customerVisitCount: currentAttendance.customerVisitCount + 1,
    );
    await LocalStorageService.saveAttendance(updated);
    return updated;
  }

  static Future<void> updateVisit(String userId, VisitModel visit) async {
    await _repo.updateVisit(userId, visit);
    await LocalStorageService.saveVisit(visit);
  }

  static Future<void> addComment(
    String targetUserId,
    String visitId,
    String text,
  ) async {
    final UserModel? user = LocalStorageService.getUser();
    if (user == null) return;
    await _repo.addComment(
      targetUserId,
      visitId,
      VisitComment(
        id: '',
        userId: user.id,
        userName: user.fullName,
        text: text,
        timestamp: DateTime.now(),
      ),
    );
  }

  // ─── Monthly Tab helpers ───────────────────────────────────────────────────

  static List<String> lastMonthKeys({int count = 12}) {
    final now = DateTime.now();
    return List.generate(count, (i) {
      final dt = DateTime(now.year, now.month - i, 1);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
    });
  }

  static List<({String monthKey, MonthlySummaryModel summary})>
      getCachedActiveMonths(String userId) {
    final result = <({String monthKey, MonthlySummaryModel summary})>[];
    for (final key in lastMonthKeys()) {
      if (LocalStorageService.isMonthEmpty(userId, key)) continue;
      final cached = LocalStorageService.getMonthlySummary(userId, key);
      if (cached != null &&
          (cached.punchCount > 0 || cached.totalVisits > 0)) {
        result.add((monthKey: key, summary: cached));
      }
    }
    return result;
  }

  static Future<void> fetchUncachedMonths(
    String userId,
    void Function(String monthKey, MonthlySummaryModel? summary)
        onMonthResolved,
  ) async {
    for (final key in lastMonthKeys()) {
      final isCurrent = key == currentMonthKey;

      if (!isCurrent &&
          (LocalStorageService.isMonthEmpty(userId, key) ||
              LocalStorageService.getMonthlySummary(userId, key) != null)) {
        continue;
      }

      final summary = await getMonthlySummary(userId, key);
      onMonthResolved(key, summary);
    }
  }

  // ─── Attendance History (paginated) ────────────────────────────────────────

  static Future<(List<AttendanceModel>, String?)> getAttendanceHistory(
    String userId, {
    int limit = 30,
    String? startAfterDate,
  }) =>
      _repo.getAttendanceHistory(userId,
          limit: limit, startAfterDate: startAfterDate);
}
