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

  static bool _isPastDay(String date) =>
      date.compareTo(AppUtils.todayKey()) < 0;

  static String get currentMonthKey {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  static bool _isPastMonth(String monthKey) =>
      monthKey.compareTo(currentMonthKey) < 0;

  // ─── Attendance ────────────────────────────────────────────────────────────

  static Future<AttendanceModel?> getAttendance(
      String userId, String date) async {
    // Own user: Hive is the source of truth for any day.
    if (isOwner(userId)) {
      final cached = LocalStorageService.getAttendance(date);
      if (cached != null) return cached;
    } else {
      // Manager: check namespaced cache.
      final cached = LocalStorageService.getAttendanceForUser(userId, date);
      if (cached != null && _isPastDay(date)) return cached; // sealed
      if (cached != null) {
        // Today — still return cached but also refresh from Firestore.
        _repo.getAttendance(userId, date).then((remote) async {
          if (remote != null) {
            await LocalStorageService.saveAttendanceForUser(userId, remote);
          }
        });
        return cached;
      }
    }

    // Cache miss → Firestore.
    final remote = await _repo.getAttendance(userId, date);
    if (remote != null) {
      if (isOwner(userId)) {
        await LocalStorageService.saveAttendance(remote);
      } else {
        await LocalStorageService.saveAttendanceForUser(userId, remote);
      }
    }
    return remote;
  }

  // ─── Visits ────────────────────────────────────────────────────────────────

  static Future<List<VisitModel>> getVisitsForDay(
      String userId, String date) async {
    // Own user, today → Hive visits box (updated live by the app).
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
    // Own user, today → live locations box.
    if (isOwner(userId) && date == AppUtils.todayKey()) {
      final cached = LocalStorageService.getTodayLocations();
      if (cached.isNotEmpty) return cached;
      // Cache empty (e.g. mid-day reinstall) — seed from Firestore once so
      // the map shows the last known position instead of "Acquiring GPS".
      final dayLocs = await _repo.getDayLocations(userId, date);
      final points = dayLocs?.points ?? [];
      if (points.isNotEmpty) {
        await LocalStorageService.saveTodayLocations(points);
      }
      return points;
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

  static Future<MonthlySummaryModel?> getMonthlySummary(
      String userId, String monthKey) async {
    // Current month is always recomputed (data is still changing).
    if (!_isPastMonth(monthKey)) {
      final summary = await computeMonthlySummary(userId, monthKey);
      await _repo.saveMonthlySummary(userId, summary);
      return summary;
    }

    // Past month — local cache first.
    final cached = LocalStorageService.getMonthlySummary(userId, monthKey);
    if (cached != null) return cached;

    // Firestore next.
    final fromDb = await _repo.getMonthlySummary(userId, monthKey);
    if (fromDb != null) {
      await LocalStorageService.saveMonthlySummary(userId, monthKey, fromDb);
      return fromDb;
    }

    // Compute from raw data, persist everywhere.
    final summary = await computeMonthlySummary(userId, monthKey);
    await _repo.saveMonthlySummary(userId, summary);
    await LocalStorageService.saveMonthlySummary(userId, monthKey, summary);
    return summary;
  }

  static Future<MonthlySummaryModel> computeMonthlySummary(
      String userId, String monthKey) async {
    final attendance =
        await _repo.getAttendanceForMonth(userId, monthKey);

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

  // ─── Attendance History (paginated) ────────────────────────────────────────

  static Future<(List<AttendanceModel>, String?)> getAttendanceHistory(
    String userId, {
    int limit = 30,
    String? startAfterDate,
  }) =>
      _repo.getAttendanceHistory(userId,
          limit: limit, startAfterDate: startAfterDate);
}
