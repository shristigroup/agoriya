import 'dart:async';
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
import '../../../services/location_sync_service.dart';

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
      if (data == null) return;
      final batch = ((data['currentBatch'] as List?) ?? const [])
          .map((e) => LocationPoint.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final anchorJson = data['lastConfirmedPoint'] as Map?;
      final anchor = anchorJson != null
          ? LocationPoint.fromJson(Map<String, dynamic>.from(anchorJson))
          : null;
      add(NewLocationPointEvent(
        processBatch: (data['processBatch'] as bool?) ?? false,
        currentBatch: batch,
        lastConfirmedPoint: anchor,
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

    final finalLocations = DataManager.getFinalLocations();
    final finalDistance = DataManager.getFinalLocationsDistance();

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

    // The isolate is the sole owner of currentBatch/lastConfirmedPoint —
    // request its state instead of ever reading its Hive box directly.
    List<LocationPoint> currentBatch = [];
    LocationPoint? lastConfirmedPoint;
    int pendingSampleCount = 0;
    if (tracking?.isPunchedIn == true) {
      final snap = await LocationTrackingService.requestSnapshot();
      if (snap != null) {
        currentBatch = snap.currentBatch;
        lastConfirmedPoint = snap.lastConfirmedPoint;
        pendingSampleCount = snap.pendingSampleCount;
      }
    }

    // Seed lastKnownLocation from the last tracked point.
    final LatLng? lastKnownLocation = finalLocations.isNotEmpty
        ? finalLocations.last.position
        : currentBatch.isNotEmpty
            ? currentBatch.last.position
            : lastConfirmedPoint?.position;

    emit(HomeLoaded(
      tracking: tracking,
      finalLocations: finalLocations,
      currentBatch: currentBatch,
      visits: visits,
      lastKnownLocation: lastKnownLocation,
      finalLocationsDistance: finalDistance,
      currentBatchDistance:
          _currentBatchDistanceKm(currentBatch, finalLocations),
    ));

    // Covers the case where a flush signal was missed while the app was
    // dead. pendingSampleCount (not currentBatch.length) is the right check
    // here — a pure stationary run never grows currentBatch, but samples
    // still accumulate toward it, so this is the only reliable signal that
    // a sync is owed. Threshold at locationBatchSize, not >0: a small
    // pending count isn't overdue yet — it'll flush naturally via the
    // normal live path once it reaches this same threshold, same as any
    // other in-session count. Only >= means a flush was actually due and
    // never got confirmed.
    if (pendingSampleCount >= AppConstants.locationBatchSize) {
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
      // fresh: true — a genuine new session, so the isolate wipes any
      // leftover cursor state (currentBatch/pendingSampleCount/
      // lastConfirmedPoint) from a previous day/session before sampling.
      await LocationTrackingService.start(userId, today, fresh: true);
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

      // Request the final cursor state BEFORE stopping — the isolate must
      // still be alive to respond to this.
      final snap = await LocationTrackingService.requestSnapshot();
      final currentBatch = snap?.currentBatch ?? <LocationPoint>[];

      LocationTrackingService.stop();
      await Future.delayed(const Duration(seconds: 1));

      final finalLocations = DataManager.getFinalLocations();

      final snapResult = await LocationSyncService.snapBatch(
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
      print('[HomeBloc] punchOut error: $e');
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
      // Not fresh — continuing the same day's session, cursor state (if any
      // survived) should be kept.
      await LocationTrackingService.start(userId, today);
      emit(current.copyWith(tracking: resumed));
    } catch (e) {
      print('[HomeBloc] resumeSession error: $e');
      emit(HomeError(e.toString()));
    }
  }

  // ── App Resumed (foreground) ──────────────────────────────────────────────

  Future<void> _onAppResumed(
      AppResumedEvent event, Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    final current = state as HomeLoaded;
    if (current.tracking?.isPunchedIn != true) return;

    // The isolate may have been killed by the OS while backgrounded —
    // restart it (not fresh: continuing the same session) before asking
    // for its state.
    if (!await LocationTrackingService.isRunning) {
      final permission = await Geolocator.checkPermission();
      final hasPermission = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      if (!hasPermission) return;
      await LocationTrackingService.start(userId, AppUtils.todayKey());
    }

    final snap = await LocationTrackingService.requestSnapshot();
    if (snap == null) return;

    final lastPoint = snap.currentBatch.isNotEmpty
        ? snap.currentBatch.last
        : snap.lastConfirmedPoint;

    emit(current.copyWith(
      currentBatch: snap.currentBatch,
      currentBatchDistance:
          _currentBatchDistanceKm(snap.currentBatch, current.finalLocations),
      lastKnownLocation: lastPoint?.position ?? current.lastKnownLocation,
    ));

    // Covers the case where a flush signal was missed while the app was
    // backgrounded — pendingSampleCount catches a pure stationary run too,
    // where currentBatch never grows (see _onInit for the same reasoning
    // on the >= threshold vs. >0).
    if (snap.pendingSampleCount >= AppConstants.locationBatchSize) {
      await _processBatch(emit);
    }
  }

  // ── New Location Point ────────────────────────────────────────────────────
  // The background isolate is the sole owner of currentBatch/
  // lastConfirmedPoint and pushes their current values with every sample —
  // this handler just applies them to live UI state and, on a flush
  // signal, drives the OSRM+Firestore sync.

  Future<void> _onNewLocationPoint(
      NewLocationPointEvent event, Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    final current = state as HomeLoaded;
    if (current.tracking?.isPunchedIn != true) return;

    final lastPoint = event.currentBatch.isNotEmpty
        ? event.currentBatch.last
        : event.lastConfirmedPoint;

    emit(current.copyWith(
      currentBatch: event.currentBatch,
      currentBatchDistance:
          _currentBatchDistanceKm(event.currentBatch, current.finalLocations),
      lastKnownLocation: lastPoint?.position ?? current.lastKnownLocation,
      lastGpsUpdateTime: DateTime.now(),
    ));

    if (event.processBatch) await _processBatch(emit);
  }

  // ── Process Current Batch ─────────────────────────────────────────────────
  // Requests currentBatch fresh from the isolate (never trusts stale
  // in-memory state), snaps it via OSRM, and syncs to Firestore. The
  // isolate's cursor state is left untouched until the sync succeeds — on
  // failure, nothing is confirmed, so the batch is naturally retried on the
  // next signal/resume instead of being lost.

  Future<void> _processBatch(Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    if (_snapping) return;

    final current = state as HomeLoaded;
    if (current.tracking == null) return;

    _snapping = true;
    emit(current.copyWith(isSnapping: true));

    try {
      final result = await LocationSyncService.syncCore(
        userId: userId,
        trackingId: current.tracking!.id,
        finalLocations: DataManager.getFinalLocations(),
        finalLocationsDistance: DataManager.getFinalLocationsDistance(),
      );

      if (result == null) {
        if (state is HomeLoaded) {
          emit((state as HomeLoaded).copyWith(isSnapping: false));
        }
        return;
      }

      if (state is! HomeLoaded) return;
      final freshSnap = await LocationTrackingService.requestSnapshot();
      final freshBatch = freshSnap?.currentBatch ?? <LocationPoint>[];
      emit((state as HomeLoaded).copyWith(
        isSnapping: false,
        finalLocations: result.finalLocations,
        finalLocationsDistance: result.finalLocationsDistance,
        currentBatch: freshBatch,
        currentBatchDistance:
            _currentBatchDistanceKm(freshBatch, result.finalLocations),
      ));
    } catch (e) {
      // syncCore already catches its own errors and returns null — this is
      // a backstop for anything outside it (e.g. the fresh snapshot re-read
      // above), so isSnapping never gets stuck true.
      print('[HomeBloc] processCurrentBatch error: $e');
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

  /// Live haversine estimate for the unsynced currentBatch, anchored to the
  /// last committed point — mirrors how the batch's OSRM distance is
  /// anchored in [LocationSyncService.snapBatch] once it's synced.
  double _currentBatchDistanceKm(
      List<LocationPoint> batch, List<LocationPoint> finalLocations) {
    if (batch.isEmpty) return 0.0;
    final points = [if (finalLocations.isNotEmpty) finalLocations.last, ...batch];
    double sum = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      sum += AppUtils.haversineMeters(points[i].position, points[i + 1].position) /
          1000.0;
    }
    return sum;
  }
}
