import 'package:package_info_plus/package_info_plus.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/app_utils.dart';
import 'local/local_storage_service.dart';
import 'models/tracking_model.dart';
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
  /// On version mismatch (reinstall / update / new device), seeds today's
  /// tracking session, visits, and locations from Firestore into Hive.
  static Future<void> seedTodayDataAsAppHasReinstalled(
      String userId, String date) async {
    final info = await PackageInfo.fromPlatform();
    final currentVersion = info.version;
    final cachedVersion =
        LocalStorageService.getSetting<String>(AppConstants.cacheVersionKey);

    if (cachedVersion == currentVersion) return;

    // Fetch the most recent tracking session (single-field orderBy — no index needed).
    try {
      final latest = await _repo.getLatestTracking(userId);
      if (latest != null && latest.date == date) {
        await LocalStorageService.saveTracking(latest);
        if (latest.isActive) {
          await LocalStorageService.saveActiveTrackingId(latest.id);
        }
        // Seed locations for this session.
        final points = await _repo.getTrackingLocations(userId, latest.id);
        if (points.isNotEmpty) {
          await LocalStorageService.saveFinalLocations(points);
          await LocalStorageService.saveFinalLocationsDistance(latest.distance);
        }
      }
    } catch (_) {}

    // Seed today's visits.
    try {
      final start = DateTime.parse(date);
      final visits = await _repo.getVisitsByDateRange(
          userId, start, start.add(const Duration(days: 1)));
      for (final v in visits) {
        await LocalStorageService.saveVisit(v);
      }
    } catch (_) {}

    await LocalStorageService.setSetting(
        AppConstants.cacheVersionKey, currentVersion);
  }

  // ─── Active Tracking (own user today) ─────────────────────────────────────

  static TrackingModel? getActiveTracking() {
    final id = LocalStorageService.getActiveTrackingId();
    if (id == null) return null;
    return LocalStorageService.getTracking(id);
  }

  // ─── Tracking (read) ──────────────────────────────────────────────────────

  /// Returns the current tracking session for the owner, or the most recent
  /// session for today for a manager's report view (from Firestore).
  static Future<TrackingModel?> getTrackingForToday(
      String userId, String date) async {
    if (isOwner(userId)) {
      return getActiveTracking();
    }

    // Manager view: always fetch fresh from Firestore for today.
    final sessions = await _repo.getTrackingForDate(userId, date);
    return sessions.isNotEmpty ? sessions.first : null;
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

  /// Returns locations for a specific tracking session.
  /// Own user today: finalLocations + currentBatch (live, not yet in Firestore).
  static Future<List<LocationPoint>> getLocationsForTracking(
      String userId, String trackingId) async {
    final tracking = LocalStorageService.getTracking(trackingId);
    final date = tracking?.date ?? TrackingModel.dateFromId(trackingId);
    final isToday = date == AppUtils.todayKey();

    if (isOwner(userId) && isToday) {
      return [
        ...LocalStorageService.getFinalLocations(),
        ...LocalStorageService.getCurrentBatch(),
      ];
    }

    // Past session only: Hive hit seals the data — no Firestore call needed.
    // For today's active session skip Hive so the manager always sees fresh data.
    if (_isPastDay(date)) {
      final cached =
          LocalStorageService.getLocationsForTracking(userId, trackingId);
      if (cached.isNotEmpty) return cached;
    }

    // Cache miss: fetch from Firestore.
    final points = await _repo.getTrackingLocations(userId, trackingId);
    if (points.isNotEmpty) {
      await LocalStorageService.saveLocationsForTracking(
          userId, trackingId, points);
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
  static double getDisplayDistance(String userId, TrackingModel? tracking) {
    if (isOwner(userId)) {
      return LocalStorageService.getFinalLocationsDistance() +
          LocalStorageService.getCurrentBatchDistance();
    }
    return tracking?.distance ?? 0.0;
  }

  /// Persists a new point into currentBatch + updates currentBatchDistance.
  static Future<void> saveCurrentBatch(
    List<LocationPoint> updatedBatch,
    double newBatchDistance,
  ) async {
    await LocalStorageService.saveCurrentBatch(updatedBatch);
    await LocalStorageService.saveCurrentBatchDistance(newBatchDistance);
  }

  static Future<void> saveFinalLocations(List<LocationPoint> points) =>
      LocalStorageService.saveFinalLocations(points);

  /// Writes the complete locations array to Firestore and saves to Hive.
  /// allLocations = finalLocations + snappedBatch, or just finalLocations on
  /// a stationary-only flush (empty batch, updated last-point durationSeconds).
  static Future<void> persistLocations({
    required String userId,
    required String trackingId,
    required List<LocationPoint> allLocations,
    required double distanceKm,
  }) async {
    await _repo.writeLocations(userId, trackingId, allLocations, distanceKm);
    await LocalStorageService.saveFinalLocations(allLocations);
    await LocalStorageService.saveFinalLocationsDistance(distanceKm);
  }

  // ─── Punch In ──────────────────────────────────────────────────────────────

  static Future<TrackingModel> punchIn(
    String userId,
    String date,
    DateTime timestamp,
    String imageUrl,
  ) async {
    final trackingId = TrackingModel.buildId(date, timestamp);
    final tracking = TrackingModel(
      id: trackingId,
      date: date,
      startTime: timestamp,
      punchInImage: imageUrl,
    );
    await _repo.createTracking(userId, tracking);
    await LocalStorageService.saveTracking(tracking);
    await LocalStorageService.saveActiveTrackingId(trackingId);
    await LocalStorageService.clearTodayTrackingState();
    // Re-save the active tracking ID (clearTodayTrackingState clears it).
    await LocalStorageService.saveActiveTrackingId(trackingId);
    return tracking;
  }

  // ─── Punch Out ─────────────────────────────────────────────────────────────

  static Future<TrackingModel> punchOut({
    required String userId,
    required TrackingModel currentTracking,
    required DateTime timestamp,
  }) async {
    await _repo.closeTracking(userId, currentTracking.id, timestamp);
    final updated = currentTracking.copyWith(stopTime: timestamp);
    // Keep the tracking ID in Hive so HomeBloc can see isPunchedOut = true
    // on the next init and offer the "Resume Session" option. The ID is
    // cleared only when the user starts a fresh punch-in.
    await LocalStorageService.saveTracking(updated);
    return updated;
  }

  // ─── Resume Session ────────────────────────────────────────────────────────

  static Future<TrackingModel> resumeSession(
    String userId,
    TrackingModel currentTracking,
  ) async {
    // Get latest tracking from Firestore to confirm it is still closed.
    // If it is already open (e.g. from another device), skip the write.
    final latest = await _repo.getLatestTracking(userId);
    final target = latest?.id == currentTracking.id ? latest! : currentTracking;
    if (target.isStopped) {
      await _repo.resumeTracking(userId, target.id);
    }
    final resumed = target.copyWith(clearStopTime: true);
    await LocalStorageService.saveTracking(resumed);
    await LocalStorageService.saveActiveTrackingId(target.id);
    return resumed;
  }

  // ─── Monthly Summary ───────────────────────────────────────────────────

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
    final trackings = await _repo.getTrackingForMonth(userId, monthKey);
    if (trackings.isEmpty) return null;

    final monthStart = DateTime.parse('$monthKey-01');
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 1);
    final visits =
        await _repo.getVisitsByDateRange(userId, monthStart, monthEnd);

    int punchCount = 0;
    int totalMinutes = 0;
    double totalDistance = 0;
    for (final t in trackings) {
      if (t.isActive) punchCount++;
      totalMinutes += t.attendanceDuration.inMinutes;
      totalDistance += t.distance;
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

  static Future<TrackingModel?> createVisit(
    String userId,
    VisitModel visit,
    TrackingModel? currentTracking,
  ) async {
    await _repo.createVisit(userId, visit);
    await LocalStorageService.saveVisit(visit);
    if (currentTracking == null) return null;
    await _repo.incrementTrackingVisitCount(userId, currentTracking.id);
    final updated = currentTracking.copyWith(
      visitCount: currentTracking.visitCount + 1,
    );
    await LocalStorageService.saveTracking(updated);
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

  // ─── Tracking History (paginated) ────────────────────────────────────────

  static Future<(List<TrackingModel>, String?)> getTrackingHistory(
    String userId, {
    int limit = 30,
    String? startAfterId,
  }) =>
      _repo.getTrackingHistory(userId, limit: limit, startAfterId: startAfterId);
}
