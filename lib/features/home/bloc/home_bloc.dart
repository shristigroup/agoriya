import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'home_event.dart';
import 'home_state.dart';
import '../../../data/data_manager.dart';
import '../../../data/models/visit_model.dart';
import '../../../data/models/location_model.dart';
import '../../../core/utils/app_utils.dart';
import '../../../services/location_tracking_service.dart';
import '../../../services/osrm_service.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final String userId;

  bool _snapping = false;
  bool _punchingOut = false;

  StreamSubscription? _newPointSub;
  StreamSubscription? _batchFlushedSub;

  HomeBloc({required this.userId}) : super(HomeInitial()) {
    on<HomeInitEvent>(_onInit);
    on<PunchInEvent>(_onPunchIn);
    on<PunchOutEvent>(_onPunchOut);
    on<ResumeSessionEvent>(_onResumeSession);
    on<NewLocationPointEvent>(_onNewLocationPoint);
    on<ProcessCurrentBatchEvent>(_onProcessCurrentBatch);
    on<CreateVisitEvent>(_onCreateVisit);
    on<UpdateVisitEvent>(_onUpdateVisit);
    on<CheckOutVisitEvent>(_onCheckOutVisit);
    on<AddCommentEvent>(_onAddComment);

    final bgService = FlutterBackgroundService();

    _newPointSub = bgService.on('newPoint').listen((data) {
      if (data == null) return;
      add(NewLocationPointEvent(
        lat: (data['lat'] as num).toDouble(),
        lng: (data['lng'] as num).toDouble(),
        timestamp: DateTime.parse(data['timestamp'] as String),
      ));
    });

    _batchFlushedSub = bgService.on('batchFlushed').listen((_) {
      add(ProcessCurrentBatchEvent());
    });
  }

  @override
  Future<void> close() {
    _newPointSub?.cancel();
    _batchFlushedSub?.cancel();
    return super.close();
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> _onInit(HomeInitEvent event, Emitter<HomeState> emit) async {
    emit(HomeLoading());

    final today = AppUtils.todayKey();

    await DataManager.seedTodayDataAsAppHasReinstalled(userId, today);

    final attendance = await DataManager.getAttendance(userId, today);
    final visits = await DataManager.getVisitsForDay(userId, today);

    final finalLocations = DataManager.getFinalLocations();
    final currentBatch = DataManager.getCurrentBatch();
    final finalDistance = DataManager.getFinalLocationsDistance();
    final batchDistance = DataManager.getCurrentBatchDistance();

    LatLng? lastKnownLocation;
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        lastKnownLocation = LatLng(pos.latitude, pos.longitude);
      }
    } catch (_) {}

    // Stop any lingering background service if the user is not punched in.
    // This can happen when the service survives an app restart but setParams
    // was never re-sent because no punch-in occurred this session.
    if (attendance?.isPunchedIn != true) {
      final running = await LocationTrackingService.isRunning;
      if (running) LocationTrackingService.stop();
    }

    emit(HomeLoaded(
      attendance: attendance,
      finalLocations: finalLocations,
      currentBatch: currentBatch,
      visits: visits,
      lastKnownLocation: lastKnownLocation,
      finalLocationsDistance: finalDistance,
      currentBatchDistance: batchDistance,
    ));

    // If the app was killed while a batch was accumulating, process it now.
    if (currentBatch.isNotEmpty) add(ProcessCurrentBatchEvent());
  }

  // ── Punch In ──────────────────────────────────────────────────────────────

  Future<void> _onPunchIn(
      PunchInEvent event, Emitter<HomeState> emit) async {
    try {
      final today = AppUtils.todayKey();
      final attendance = await DataManager.punchIn(
          userId, today, DateTime.now(), event.imageUrl);
      await LocationTrackingService.start(userId, today);
      emit(PunchInSuccess(attendance));
    } catch (e) {
      emit(HomeError(e.toString()));
    }
  }

  // ── Punch Out ─────────────────────────────────────────────────────────────

  Future<void> _onPunchOut(
      PunchOutEvent event, Emitter<HomeState> emit) async {
    if (_punchingOut) return;
    _punchingOut = true;

    final current = state;
    if (current is! HomeLoaded) {
      _punchingOut = false;
      return;
    }

    emit(current.copyWith(isPunchingOut: true));

    try {
      final today = AppUtils.todayKey();
      final now = DateTime.now();

      LocationTrackingService.stop();
      await Future.delayed(const Duration(seconds: 1));

      // Snap the final currentBatch inline (same logic as _onProcessCurrentBatch
      // but without the state-clear step — we're about to shut down anyway).
      final snapResult = await _snapBatch(
        batch: List<LocationPoint>.from(current.currentBatch),
        finalLocations: current.finalLocations,
      );

      List<LocationPoint> freshFinalLocations = current.finalLocations;
      double newFinalDistance = current.finalLocationsDistance;

      if (snapResult != null) {
        final (markedBatch, osrmDistance) = snapResult;
        newFinalDistance = current.finalLocationsDistance + osrmDistance;

        // Mark last point with cumulative + batch distances.
        final committedBatch =
            _markLastPoint(markedBatch, newFinalDistance, osrmDistance);

        freshFinalLocations = await DataManager.persistSnappedBatch(
          userId: userId,
          date: today,
          snapped: committedBatch,
          newFinalDistance: newFinalDistance,
          fallbackFinalLocations: [
            ...current.finalLocations,
            ...committedBatch,
          ],
        );
      }

      // Determine last known position from the full merged path.
      final allLocs = [
        ...freshFinalLocations,
        // currentBatch was already snapped into freshFinalLocations, so skip it.
      ];
      LatLng? lastLoc =
          allLocs.isNotEmpty ? allLocs.last.position : null;
      if (lastLoc == null) {
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high),
          );
          lastLoc = LatLng(pos.latitude, pos.longitude);
        } catch (_) {}
      }

      final updatedAttendance = await DataManager.punchOut(
        userId: userId,
        date: today,
        currentAttendance: current.attendance!,
        timestamp: now,
        lastLocation: lastLoc,
        finalLocations: freshFinalLocations,
        finalDistance: newFinalDistance,
      );

      emit(PunchOutSuccess(
        attendance: updatedAttendance,
        totalTime: updatedAttendance.attendanceDuration,
      ));
    } catch (e) {
      debugPrint('[HomeBloc] punchOut error: $e');
      try {
        emit(current.copyWith(isPunchingOut: false));
      } catch (_) {}
      emit(HomeError(e.toString()));
    } finally {
      _punchingOut = false;
    }
  }

  // ── Resume Session ────────────────────────────────────────────────────────

  Future<void> _onResumeSession(
      ResumeSessionEvent event, Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    final current = state as HomeLoaded;
    if (current.attendance?.isPunchedOut != true) return;

    try {
      final today = AppUtils.todayKey();
      final resumed =
          await DataManager.resumeSession(userId, today, current.attendance!);
      await LocationTrackingService.start(userId, today);
      emit(current.copyWith(attendance: resumed));
    } catch (e) {
      debugPrint('[HomeBloc] resumeSession error: $e');
      emit(HomeError(e.toString()));
    }
  }

  // ── New Location Point ────────────────────────────────────────────────────

  Future<void> _onNewLocationPoint(
      NewLocationPointEvent event, Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    final current = state as HomeLoaded;

    final newPoint = LocationPoint(
      position: LatLng(event.lat, event.lng),
      timestamp: event.timestamp,
      isSnapped: false,
    );

    // Haversine delta anchored to the last point in either array.
    double delta = 0;
    if (current.currentBatch.isNotEmpty) {
      delta =
          _haversine(current.currentBatch.last.position, newPoint.position);
    } else if (current.finalLocations.isNotEmpty) {
      delta =
          _haversine(current.finalLocations.last.position, newPoint.position);
    }

    final updatedBatch = [...current.currentBatch, newPoint];
    final newBatchDistance = current.currentBatchDistance + delta;

    await DataManager.appendToCurrentBatch(updatedBatch, newBatchDistance);

    emit(current.copyWith(
      currentBatch: updatedBatch,
      currentBatchDistance: newBatchDistance,
    ));
  }

  // ── Process Current Batch ─────────────────────────────────────────────────

  Future<void> _onProcessCurrentBatch(
      ProcessCurrentBatchEvent event, Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    if (_snapping) return;

    final current = state as HomeLoaded;
    final batchToProcess = List<LocationPoint>.from(current.currentBatch);
    if (batchToProcess.isEmpty) return;

    _snapping = true;

    // ── Step 1: clear currentBatch in state FIRST (synchronous emit), then
    // persist to Hive. New NewLocationPointEvents arriving after the emit will
    // see an empty currentBatch and start accumulating a fresh batch, ensuring
    // nothing is double-processed or lost during the OSRM await below.
    emit(current.copyWith(
      currentBatch: [],
      currentBatchDistance: 0.0,
      isSnapping: true,
    ));
    await DataManager.appendToCurrentBatch([], 0.0);

    try {
      final today = AppUtils.todayKey();

      // ── Step 2: sort, filter, OSRM snap.
      final snapResult = await _snapBatch(
        batch: batchToProcess,
        finalLocations: current.finalLocations,
      );

      if (snapResult == null) {
        // Nothing valid to commit (all points were older than last synced).
        if (state is HomeLoaded) {
          emit((state as HomeLoaded).copyWith(isSnapping: false));
        }
        return;
      }

      final (snappedBatch, osrmDistance) = snapResult;

      // ── Step 3: compute new cumulative distance and mark last point.
      // Use the LATEST state's finalLocationsDistance — new points may have
      // arrived during the OSRM await but they only affect currentBatch, not
      // finalLocationsDistance, so this value is still correct.
      final latestState =
          state is HomeLoaded ? state as HomeLoaded : current;
      final newFinalDistance =
          latestState.finalLocationsDistance + osrmDistance;
      final committedBatch =
          _markLastPoint(snappedBatch, newFinalDistance, osrmDistance);

      // ── Step 4: persist to Firestore, read back, save to Hive.
      final freshFinalLocations = await DataManager.persistSnappedBatch(
        userId: userId,
        date: today,
        snapped: committedBatch,
        newFinalDistance: newFinalDistance,
        fallbackFinalLocations: [
          ...latestState.finalLocations,
          ...committedBatch,
        ],
      );

      // ── Step 5: merge with the LATEST state — currentBatch may have new
      // points that accumulated while OSRM was in flight (step 1 cleared it,
      // so these are genuinely new). We must NOT discard them.
      if (state is! HomeLoaded) return;
      final finalState = state as HomeLoaded;
      emit(finalState.copyWith(
        isSnapping: false,
        finalLocations: freshFinalLocations,
        finalLocationsDistance: newFinalDistance,
        // currentBatch and currentBatchDistance are taken from finalState
        // (already up-to-date from NewLocationPointEvent handlers).
      ));
    } catch (e) {
      debugPrint('[HomeBloc] processCurrentBatch error: $e');
      if (state is HomeLoaded) {
        emit((state as HomeLoaded).copyWith(isSnapping: false));
      }
    } finally {
      _snapping = false;
    }
  }

  // ── Visits ────────────────────────────────────────────────────────────────

  Future<void> _onCreateVisit(
      CreateVisitEvent event, Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    final current = state as HomeLoaded;
    try {
      final today = AppUtils.todayKey();
      final now = DateTime.now();
      final visitId =
          AppUtils.visitDocId(event.clientName, event.location, now);
      final visit = VisitModel(
        id: visitId,
        clientName: event.clientName,
        location: event.location,
        checkinTimestamp: now,
      );

      final updatedAttendance =
          await DataManager.createVisit(userId, visit, today, current.attendance);
      final allVisits = await DataManager.getVisitsForDay(userId, today);

      emit(VisitCreated(visit));
      emit(current.copyWith(
        attendance: updatedAttendance ?? current.attendance,
        visits: allVisits,
      ));
    } catch (e) {
      emit(HomeError(e.toString()));
    }
  }

  Future<void> _onUpdateVisit(
      UpdateVisitEvent event, Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    final current = state as HomeLoaded;
    try {
      await DataManager.updateVisit(userId, event.visit);
      final allVisits =
          await DataManager.getVisitsForDay(userId, AppUtils.todayKey());
      emit(VisitUpdated(event.visit));
      emit(current.copyWith(visits: allVisits));
    } catch (e) {
      emit(HomeError(e.toString()));
    }
  }

  Future<void> _onCheckOutVisit(
      CheckOutVisitEvent event, Emitter<HomeState> emit) async {
    add(UpdateVisitEvent(
        event.visit.copyWith(checkoutTimestamp: DateTime.now())));
  }

  Future<void> _onAddComment(
      AddCommentEvent event, Emitter<HomeState> emit) async {
    try {
      await DataManager.addComment(
          event.targetUserId, event.visitId, event.text);
    } catch (e) {
      emit(HomeError(e.toString()));
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Sorts [batch] by timestamp, filters out points at or before the last
  /// synced timestamp, OSRM-snaps the remainder, and returns
  /// (snappedPoints, osrmDistance) — or null if nothing valid remains.
  Future<(List<LocationPoint>, double)?> _snapBatch({
    required List<LocationPoint> batch,
    required List<LocationPoint> finalLocations,
  }) async {
    if (batch.isEmpty) return null;

    // Sort chronologically — OSRM match requires ordered input.
    final sorted = List<LocationPoint>.from(batch)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Drop points that predate the last committed point to prevent
    // out-of-order entries in the Firestore array.
    final lastSyncedTs =
        finalLocations.isNotEmpty ? finalLocations.last.timestamp : null;
    final valid = lastSyncedTs != null
        ? sorted
            .where((p) => p.timestamp.isAfter(lastSyncedTs))
            .toList()
        : sorted;

    if (valid.isEmpty) return null;

    // OSRM snap — falls back to original positions on network error.
    final tracepoints = await OsrmService.snapTracepoints(
      valid.map((p) => p.position).toList(),
    );

    final snapped = <LocationPoint>[];
    for (int i = 0; i < valid.length; i++) {
      final pos = tracepoints[i] ?? valid[i].position;
      snapped.add(LocationPoint(
        position: pos,
        timestamp: valid[i].timestamp,
        isSnapped: true,
      ));
    }

    // Haversine distance from anchor (last committed point) through snapped.
    double distance = 0.0;
    final anchor =
        finalLocations.isNotEmpty ? finalLocations.last : null;
    final distInput = [if (anchor != null) anchor, ...snapped];
    for (int i = 0; i < distInput.length - 1; i++) {
      distance += _haversine(distInput[i].position, distInput[i + 1].position);
    }

    return (snapped, distance);
  }

  /// Returns a copy of [batch] with [cumulativeDistanceKm] and [batchDistanceKm]
  /// set on the last point. Both fields are written to Firestore for debugging:
  /// cumulativeDistanceKm = running total for the whole day,
  /// batchDistanceKm      = OSRM distance for just this batch.
  List<LocationPoint> _markLastPoint(
    List<LocationPoint> batch,
    double cumulativeDistanceKm,
    double batchDistanceKm,
  ) {
    if (batch.isEmpty) return batch;
    return [
      ...batch.take(batch.length - 1),
      batch.last.copyWith(
        cumulativeDistanceKm: cumulativeDistanceKm,
        batchDistanceKm: batchDistanceKm,
      ),
    ];
  }

  double _haversine(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(a.latitude)) *
            math.cos(_rad(b.latitude)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  double _rad(double deg) => deg * math.pi / 180;
}
