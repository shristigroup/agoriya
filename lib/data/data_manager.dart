import 'package:package_info_plus/package_info_plus.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/app_utils.dart';
import 'local/local_storage_service.dart';
import 'models/attendance_model.dart';
import 'models/location_model.dart';
import 'models/monthly_summary_model.dart';
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

  /// Returns the distance to display in the UI for today's session.
  /// Own user → live dirty distance from Hive (includes unsnapped haversine).
  /// Manager view → last value written to the attendance doc on Firestore.
  static double getDisplayDistance(String userId, AttendanceModel? attendance) {
    if (isOwner(userId)) return LocalStorageService.getTotalDistanceDirty();
    return attendance?.distance ?? 0.0;
  }

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
  ///
  /// Compares the cached app version in Hive against the current build version.
  /// If they differ (reinstall, update, or new device), today's attendance,
  /// visits, and locations are fetched from Firestore and written into Hive,
  /// then the current version is saved so the next cold-start is a no-op.
  static Future<void> seedTodayDataAsAppHasReinstalled(
      String userId, String date) async {
    final info = await PackageInfo.fromPlatform();
    final currentVersion = info.version;
    final cachedVersion =
        LocalStorageService.getSetting<String>(AppConstants.cacheVersionKey);

    // Version matches → Hive is already seeded for this install; nothing to do.
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
        await LocalStorageService.saveTodayLocations(points);
      }
    } catch (_) {}

    // Write version last — only after seeding succeeds — so a partial failure
    // retries on the next cold-start rather than skipping the seed forever.
    await LocalStorageService.setSetting(
        AppConstants.cacheVersionKey, currentVersion);
  }

  // ─── Attendance ────────────────────────────────────────────────────────────

  static Future<AttendanceModel?> getAttendance(
      String userId, String date) async {
    // Own user: Hive is the sole source of truth — seeded at login.
    if (isOwner(userId)) {
      return LocalStorageService.getAttendance(date);
    }

    // Manager: check namespaced cache.
    final cached = LocalStorageService.getAttendanceForUser(userId, date);
    if (cached != null && _isPastDay(date)) return cached; // sealed
    if (cached != null) {
      // Today — return cached but refresh in background.
      _repo.getAttendance(userId, date).then((remote) async {
        if (remote != null) {
          await LocalStorageService.saveAttendanceForUser(userId, remote);
        }
      });
      return cached;
    }

    // Cache miss → Firestore.
    final remote = await _repo.getAttendance(userId, date);
    if (remote != null) {
      await LocalStorageService.saveAttendanceForUser(userId, remote);
    }
    return remote;
  }

  // ─── Visits ────────────────────────────────────────────────────────────────

  static Future<List<VisitModel>> getVisitsForDay(
      String userId, String date) async {
    // Own user, today → Hive only (seeded from Firestore at login).
    if (isOwner(userId) && !_isPastDay(date)) {
      return LocalStorageService.getOwnVisitsForDate(date);
    }

    // Past day for own user or any day for manager:
    // check the sealed flag to avoid redundant Firestore reads.
    if (LocalStorageService.isVisitsSealed(userId, date)) {
      return isOwner(userId)
          ? LocalStorageService.getOwnVisitsForDate(date)
          : (LocalStorageService.getReportVisitsForDay(userId, date) ?? []);
    }

    // Not sealed → fetch from Firestore, persist, then seal if past.
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
    // Own user, today → Hive only (seeded from Firestore at login).
    if (isOwner(userId) && date == AppUtils.todayKey()) {
      return LocalStorageService.getTodayLocations();
    }

    // Check persisted cache (works for both own past days and manager views).
    final cached = LocalStorageService.getLocations(userId, date);
    if (cached.isNotEmpty) return cached;

    // Cache miss → Firestore.
    final dayLocs = await _repo.getDayLocations(userId, date);
    final points = dayLocs?.points ?? [];
    if (points.isNotEmpty) {
      await LocalStorageService.saveLocations(userId, date, points);
    }
    return points;
  }

  // ─── Monthly Summary ───────────────────────────────────────────────────────

  /// Synchronous cache-only read — returns immediately with stale data (or null).
  static MonthlySummaryModel? getCachedMonthlySummary(
          String userId, String monthKey) =>
      LocalStorageService.getMonthlySummary(userId, monthKey);

  static Future<MonthlySummaryModel?> getMonthlySummary(
      String userId, String monthKey) async {
    if (!_isPastMonth(monthKey)) {
      // Current month: always recompute (data is still changing).
      final summary = await computeMonthlySummary(userId, monthKey);
      if (summary == null) return null; // no activity yet this month
      await _repo.saveMonthlySummary(userId, summary);
      await LocalStorageService.saveMonthlySummary(userId, monthKey, summary);
      return summary;
    }

    // Past month: empty sentinel → skip immediately, no Firestore call.
    if (LocalStorageService.isMonthEmpty(userId, monthKey)) return null;

    // Past month: Hive cache (sealed after first fetch).
    // If the cached summary has no data (stale zero from an older build),
    // treat it as empty — mark the sentinel so future loads are instant.
    final cached = LocalStorageService.getMonthlySummary(userId, monthKey);
    if (cached != null) {
      if (cached.punchCount == 0 && cached.totalVisits == 0) {
        await LocalStorageService.markMonthEmpty(userId, monthKey);
        return null;
      }
      return cached;
    }

    // Past month: Firestore (summary doc written by a previous install).
    final fromDb = await _repo.getMonthlySummary(userId, monthKey);
    if (fromDb != null) {
      await LocalStorageService.saveMonthlySummary(userId, monthKey, fromDb);
      return fromDb;
    }

    // Past month: compute from raw attendance. If empty, seal and return null
    // without creating any Firestore document for the month.
    final summary = await computeMonthlySummary(userId, monthKey);
    if (summary == null) {
      await LocalStorageService.markMonthEmpty(userId, monthKey);
      return null;
    }
    await _repo.saveMonthlySummary(userId, summary);
    await LocalStorageService.saveMonthlySummary(userId, monthKey, summary);
    return summary;
  }

  /// Returns null if the month has no attendance records at all — callers
  /// should treat null as "no data" and skip creating any Firestore entry.
  static Future<MonthlySummaryModel?> computeMonthlySummary(
      String userId, String monthKey) async {
    final attendance = await _repo.getAttendanceForMonth(userId, monthKey);
    if (attendance.isEmpty) return null;

    final monthStart = DateTime.parse('$monthKey-01');
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 1);
    final visits = await _repo.getVisitsByDateRange(
        userId, monthStart, monthEnd);

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

  // ─── Monthly Tab helpers ───────────────────────────────────────────────────

  /// Returns the last [count] month keys, newest first (e.g. ['2025-04', ...]).
  static List<String> lastMonthKeys({int count = 12}) {
    final now = DateTime.now();
    return List.generate(count, (i) {
      final dt = DateTime(now.year, now.month - i, 1);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
    });
  }

  /// Phase 1 — synchronous Hive read, zero network.
  /// Returns only months that have cached data with at least one punch or visit.
  static List<({String monthKey, MonthlySummaryModel summary})>
      getCachedActiveMonths(String userId) {
    final result = <({String monthKey, MonthlySummaryModel summary})>[];
    for (final key in lastMonthKeys()) {
      if (LocalStorageService.isMonthEmpty(userId, key)) continue;
      final cached = LocalStorageService.getMonthlySummary(userId, key);
      if (cached != null && (cached.punchCount > 0 || cached.totalVisits > 0)) {
        result.add((monthKey: key, summary: cached));
      }
    }
    return result;
  }

  /// Phase 2 — async, background. Hits Firestore only for:
  ///   • past months not yet in Hive (no cache, no sentinel)
  ///   • current month (always recomputed — data is still changing)
  ///
  /// [onMonthResolved] is called for each month as it completes so the UI can
  /// update incrementally rather than waiting for all months.
  static Future<void> fetchUncachedMonths(
    String userId,
    void Function(String monthKey, MonthlySummaryModel? summary) onMonthResolved,
  ) async {
    for (final key in lastMonthKeys()) {
      final isCurrent = key == currentMonthKey;

      // Past month already resolved — skip.
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
