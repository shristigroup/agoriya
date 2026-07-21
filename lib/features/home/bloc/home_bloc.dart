import 'dart:async';
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
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_utils.dart';
import '../../../services/location_tracking_service.dart';
import '../../../services/osrm_service.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final String userId;

  bool _snapping = false;
  bool _punchingOut = false;

  StreamSubscription? _newPointSub;

  HomeBloc({required this.userId}) : super(HomeInitial()) {
    on<HomeInitEvent>(_onInit);
    on<PunchInEvent>(_onPunchIn);
    on<PunchOutEvent>(_onPunchOut);
    on<ResumeSessionEvent>(_onResumeSession);
    on<AppResumedEvent>(_onAppResumed);
    on<NewLocationPointEvent>(_onNewLocationPoint);
    on<CreateVisitEvent>(_onCreateVisit);
    on<UpdateVisitEvent>(_onUpdateVisit);
    on<CheckOutVisitEvent>(_onCheckOutVisit);
    on<AddCommentEvent>(_onAddComment);

    final bgService = FlutterBackgroundService();

    _newPointSub = bgService.on('newPoint').listen((data) {
      add(NewLocationPointEvent(
        processBatch: (data?['processBatch'] as bool?) ?? false,
      ));
    });
  }

  @override
  Future<void> close() {
    _newPointSub?.cancel();
    return super.close();
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> _onInit(HomeInitEvent event, Emitter<HomeState> emit) async {
    emit(HomeLoading());

    final today = AppUtils.todayKey();

    await DataManager.seedTodayDataAsAppHasReinstalled(userId, today);

    final tracking = DataManager.getActiveTracking();
    final visits = await DataManager.getVisitsForDay(userId, today);

    // The background isolate may have written points while the app was
    // dead — reload before reading currentBatch/finalLocations.
    await DataManager.reloadLocationsBox();
    final finalLocations = DataManager.getFinalLocations();
    final currentBatch = DataManager.getCurrentBatch();
    final finalDistance = DataManager.getFinalLocationsDistance();
    final batchDistance = DataManager.getCurrentBatchDistance();

    // Seed lastKnownLocation from the last tracked point.
    final LatLng? lastKnownLocation = finalLocations.isNotEmpty
        ? finalLocations.last.position
        : currentBatch.isNotEmpty
            ? currentBatch.last.position
            : null;

    // Reconcile service state with tracking on every app start.
    final serviceRunning = await LocationTrackingService.isRunning;
    if (tracking?.isPunchedIn == true) {
      if (!serviceRunning) {
        final permission = await Geolocator.checkPermission();
        final hasPermission = permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse;
        if (hasPermission) await LocationTrackingService.start(userId, today);
      }
    } else {
      if (serviceRunning) LocationTrackingService.stop();
    }

    emit(HomeLoaded(
      tracking: tracking,
      finalLocations: finalLocations,
      currentBatch: currentBatch,
      visits: visits,
      lastKnownLocation: lastKnownLocation,
      finalLocationsDistance: finalDistance,
      currentBatchDistance: batchDistance,
    ));

    // Covers the case where a processBatch signal was missed while the app
    // was dead — catch up immediately rather than waiting for the next one.
    if (currentBatch.length >= AppConstants.locationBatchSize) {
      await _processBatch(emit);
    }
  }

  // ── Punch In ──────────────────────────────────────────────────────────────

  Future<void> _onPunchIn(
      PunchInEvent event, Emitter<HomeState> emit) async {
    try {
      final today = AppUtils.todayKey();
      final tracking = await DataManager.punchIn(
          userId, today, DateTime.now(), event.imageUrl);
      await LocationTrackingService.start(userId, today);
      emit(PunchInSuccess(tracking));
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
    if (current.tracking == null) {
      _punchingOut = false;
      return;
    }

    emit(current.copyWith(isPunchingOut: true));

    try {
      final now = DateTime.now();

      LocationTrackingService.stop();
      await Future.delayed(const Duration(seconds: 1));

      // Read fresh — the background isolate may have written points right
      // up until it received stopTracking.
      await DataManager.reloadLocationsBox();
      final finalLocations = DataManager.getFinalLocations();
      final currentBatch = DataManager.getCurrentBatch();

      final snapResult = await _snapBatch(
        batch: currentBatch,
        finalLocations: finalLocations,
      );

      double osrmDistance = 0.0;
      List<LocationPoint> snappedBatch = [];
      if (snapResult != null) {
        (snappedBatch, osrmDistance) = snapResult;
      }

      final newFinalDistance =
          DataManager.getFinalLocationsDistance() + osrmDistance;
      var allLocations = [...finalLocations, ...snappedBatch];

      if (allLocations.isNotEmpty) {
        allLocations = [
          ...allLocations.take(allLocations.length - 1),
          allLocations.last.copyWith(
            cumulativeDistanceKm: newFinalDistance,
            batchDistanceKm: osrmDistance,
          ),
        ];
        await DataManager.persistLocations(
          userId: userId,
          trackingId: current.tracking!.id,
          allLocations: allLocations,
          distanceKm: newFinalDistance,
        );
      }

      final updatedTracking = await DataManager.punchOut(
        userId: userId,
        currentTracking: current.tracking!,
        timestamp: now,
      );

      emit(PunchOutSuccess(
        tracking: updatedTracking,
        totalTime: updatedTracking.attendanceDuration,
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
    if (current.tracking?.isPunchedOut != true) return;

    try {
      final today = AppUtils.todayKey();
      final resumed =
          await DataManager.resumeSession(userId, current.tracking!);
      await LocationTrackingService.start(userId, today);
      emit(current.copyWith(tracking: resumed));
    } catch (e) {
      debugPrint('[HomeBloc] resumeSession error: $e');
      emit(HomeError(e.toString()));
    }
  }

  // ── App Resumed (foreground) ──────────────────────────────────────────────

  Future<void> _onAppResumed(
      AppResumedEvent event, Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    final current = state as HomeLoaded;
    if (current.tracking?.isPunchedIn != true) return;

    // The background isolate is the sole writer of currentBatch/finalLocations
    // — reload before reading so we see whatever it wrote while backgrounded.
    await DataManager.reloadLocationsBox();
    final currentBatch = DataManager.getCurrentBatch();
    final finalLocations = DataManager.getFinalLocations();
    final lastPoint = currentBatch.isNotEmpty
        ? currentBatch.last
        : (finalLocations.isNotEmpty ? finalLocations.last : null);

    emit(current.copyWith(
      currentBatch: currentBatch,
      finalLocations: finalLocations,
      currentBatchDistance: DataManager.getCurrentBatchDistance(),
      lastKnownLocation: lastPoint?.position ?? current.lastKnownLocation,
    ));

    // Covers the case where a processBatch signal was missed while the app
    // was dead — catch up immediately rather than waiting for the next sample.
    if (currentBatch.length >= AppConstants.locationBatchSize) {
      await _processBatch(emit);
    }
  }

  // ── New Location Point ────────────────────────────────────────────────────
  // The background isolate is the sole writer of currentBatch/finalLocations
  // (stationary detection, distance accumulation, and Hive writes all happen
  // there — see location_tracking_service.dart). This handler just re-reads
  // what it wrote and, on a flush signal, drives the OSRM+Firestore sync.

  Future<void> _onNewLocationPoint(
      NewLocationPointEvent event, Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    final current = state as HomeLoaded;
    if (current.tracking?.isPunchedIn != true) return;

    await DataManager.reloadLocationsBox();
    final currentBatch = DataManager.getCurrentBatch();
    final finalLocations = DataManager.getFinalLocations();
    final lastPoint = currentBatch.isNotEmpty
        ? currentBatch.last
        : (finalLocations.isNotEmpty ? finalLocations.last : null);

    emit(current.copyWith(
      currentBatch: currentBatch,
      finalLocations: finalLocations,
      currentBatchDistance: DataManager.getCurrentBatchDistance(),
      lastKnownLocation: lastPoint?.position ?? current.lastKnownLocation,
      lastGpsUpdateTime: DateTime.now(),
    ));

    if (event.processBatch) await _processBatch(emit);
  }

  // ── Process Current Batch ─────────────────────────────────────────────────
  // Reads currentBatch fresh (never trusts in-memory state, since the
  // background isolate is the sole writer), snaps it via OSRM, and syncs to
  // Firestore. currentBatch in Hive is left untouched until the sync
  // succeeds — on failure, nothing is cleared, so the batch is naturally
  // retried on the next signal/resume instead of being lost.

  Future<void> _processBatch(Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    if (_snapping) return;

    final current = state as HomeLoaded;
    if (current.tracking == null) return;

    await DataManager.reloadLocationsBox();
    final batchToProcess = DataManager.getCurrentBatch();
    final finalLocations = DataManager.getFinalLocations();
    if (batchToProcess.isEmpty && finalLocations.isEmpty) return;

    _snapping = true;
    emit(current.copyWith(isSnapping: true));

    try {
      double osrmDistance = 0.0;
      List<LocationPoint> snappedBatch = [];

      if (batchToProcess.isNotEmpty) {
        final snapResult = await _snapBatch(
          batch: batchToProcess,
          finalLocations: finalLocations,
        );
        if (snapResult != null) {
          (snappedBatch, osrmDistance) = snapResult;
        }
      }

      final newFinalDistance =
          DataManager.getFinalLocationsDistance() + osrmDistance;
      var allLocations = [...finalLocations, ...snappedBatch];

      if (allLocations.isEmpty) {
        if (state is HomeLoaded) {
          emit((state as HomeLoaded).copyWith(isSnapping: false));
        }
        return;
      }

      allLocations = [
        ...allLocations.take(allLocations.length - 1),
        allLocations.last.copyWith(
          cumulativeDistanceKm: newFinalDistance,
          batchDistanceKm: osrmDistance,
        ),
      ];

      debugPrint(
          '[HomeBloc] Syncing ${allLocations.length} total points to Firestore '
          '(+${snappedBatch.length} new, distance: ${newFinalDistance.toStringAsFixed(3)} km)'
          ' | last.ts=${allLocations.last.timestamp.toIso8601String()}'
          ' | last.durationSeconds=${allLocations.last.durationSeconds}');
      await DataManager.persistLocations(
        userId: userId,
        trackingId: current.tracking!.id,
        allLocations: allLocations,
        distanceKm: newFinalDistance,
      );

      // Confirm success so the background isolate (sole writer of
      // currentBatch) can trim entries up to this point — anything it
      // appended concurrently during the sync is left intact.
      if (batchToProcess.isNotEmpty) {
        LocationTrackingService.confirmBatchSynced(batchToProcess.last.timestamp);
      }

      if (state is! HomeLoaded) return;
      await DataManager.reloadLocationsBox();
      emit((state as HomeLoaded).copyWith(
        isSnapping: false,
        finalLocations: allLocations,
        finalLocationsDistance: newFinalDistance,
        currentBatch: DataManager.getCurrentBatch(),
        currentBatchDistance: DataManager.getCurrentBatchDistance(),
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

      final updatedTracking =
          await DataManager.createVisit(userId, visit, current.tracking);
      final allVisits = await DataManager.getVisitsForDay(userId, today);

      emit(VisitCreated(visit));
      emit(current.copyWith(
        tracking: updatedTracking ?? current.tracking,
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

  Future<(List<LocationPoint>, double)?> _snapBatch({
    required List<LocationPoint> batch,
    required List<LocationPoint> finalLocations,
  }) async {
    if (batch.isEmpty) return null;

    final sorted = List<LocationPoint>.from(batch)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final lastSyncedTs =
        finalLocations.isNotEmpty ? finalLocations.last.timestamp : null;
    final valid = lastSyncedTs != null
        ? sorted
            .where((p) => p.timestamp.isAfter(lastSyncedTs))
            .toList()
        : sorted;

    if (valid.isEmpty) return null;

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
        durationSeconds: valid[i].durationSeconds,
      ));
    }

    double distance = 0.0;
    final prevPoint =
        finalLocations.isNotEmpty ? finalLocations.last : null;
    final distInput = [if (prevPoint != null) prevPoint, ...snapped];
    for (int i = 0; i < distInput.length - 1; i++) {
      distance += AppUtils.haversineMeters(
              distInput[i].position, distInput[i + 1].position) /
          1000.0;
    }

    return (snapped, distance);
  }
}
