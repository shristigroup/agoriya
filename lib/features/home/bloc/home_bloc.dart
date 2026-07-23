import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'home_event.dart';
import 'home_state.dart';
import '../../../data/data_manager.dart';
import '../../../data/local/local_storage_service.dart';
import '../../../data/models/visit_model.dart';
import '../../../data/models/location_model.dart';
import '../../../core/utils/app_utils.dart';
import '../../../services/location_tracking_service.dart';
import '../../../services/location_sync_service.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final String userId;

  bool _snapping = false;
  bool _punchingOut = false;

  static const String _sizeLimitMessage =
      "We're unable to save any more of your location updates for today — "
      "the storage limit for today's tracking has been reached. Please "
      'contact the app administrator.';

  StreamSubscription? _newPointSub;

  HomeBloc({required this.userId}) : super(HomeInitial()) {
    on<HomeInitEvent>(_onInit);
    on<PunchInEvent>(_onPunchIn);
    on<PunchOutEvent>(_onPunchOut);
    on<ResumeSessionEvent>(_onResumeSession);
    on<AppResumedEvent>(_onAppResumed);
    on<AppPausedEvent>(_onAppPaused);
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

    emit(HomeLoaded(tracking: tracking, visits: visits));

    await _processBatch(emit);
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

      // Force a final sync of whatever's pending before stopping — the
      // isolate must still be alive to respond to it, so this must happen
      // before LocationTrackingService.stop() below.
      await _processBatch(emit, forceSync: true);

      LocationTrackingService.stop();

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

    // Reopen locationsBox/settingsBox + reacquire the lock released in
    // _onAppPaused — must happen before _processBatch reads finalLocations,
    // since the FCM watchdog may have synced a batch to disk while we were
    // backgrounded and not holding the lock.
    await LocalStorageService.reopenLocationsBoxForForeground();

    // The isolate may have been killed by the OS while backgrounded —
    // restart it (not fresh: continuing the same session) before syncing.
    if (!await LocationTrackingService.isRunning) {
      final permission = await Geolocator.checkPermission();
      final hasPermission = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      if (!hasPermission) return;
      await LocationTrackingService.start(userId, AppUtils.todayKey());
    }

    await _processBatch(emit);
  }

  // ── App Paused (backgrounded) ─────────────────────────────────────────────

  Future<void> _onAppPaused(
      AppPausedEvent event, Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    final current = state as HomeLoaded;
    if (current.tracking?.isPunchedIn != true) return;

    // Release locationsBox/settingsBox + the cross-isolate lock so the FCM
    // watchdog (and, once added, a boot/update-triggered recovery) can
    // safely sync while we're backgrounded — see LocationsBoxLock. Safe to
    // do while still punched in: the isolate's own newPoint signals keep
    // arriving and _processBatch keeps working regardless, since it routes
    // through LocationSyncService.processBatchAndEmitLatestLocationData,
    // which checks the lock's actual state and transiently reacquires it
    // itself per call rather than assuming the box is already open.
    // Reacquired for the whole foreground session again in _onAppResumed.
    await LocalStorageService.closeLocationsBoxForBackground();
  }

  // ── New Location Point ────────────────────────────────────────────────────
  // The background isolate is the sole owner of currentBatch/
  // lastConfirmedPoint and pushes their current values with every sample.
  // Every sample gets a cheap, purely in-memory UI update straight from the
  // event payload — no Hive/isolate round-trip. Only on a flush signal does
  // this go on to drive the OSRM+Firestore sync via _processBatch.

  Future<void> _onNewLocationPoint(
      NewLocationPointEvent event, Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    final current = state as HomeLoaded;
    if (current.tracking?.isPunchedIn != true) return;

    emit(current.copyWith(
      currentBatch: event.currentBatch,
      currentBatchDistance: LocationSyncService.batchDistanceKm(
          event.currentBatch, current.finalLocations),
      lastKnownLocation: LocationSyncService.resolveLastKnownLocation(
            currentBatch: event.currentBatch,
            lastConfirmedPoint: event.lastConfirmedPoint,
            finalLocations: current.finalLocations,
          ) ??
          current.lastKnownLocation,
      lastGpsUpdateTime: DateTime.now(),
    ));

    if (event.processBatch) await _processBatch(emit);
  }

  // ── Process Batch ─────────────────────────────────────────────────────────
  // Thin Bloc-side wrapper around LocationSyncService.
  // processBatchAndEmitLatestLocationData — the shared entry point also
  // used by the FCM watchdog. This just adds what only a Bloc can do:
  // re-entrancy guard, isSnapping UI state, applying the result via emit,
  // and the one-time size-limit toast. [forceSync] is used by punch-out to
  // flush whatever's pending regardless of the normal batch-size threshold.

  Future<void> _processBatch(Emitter<HomeState> emit,
      {bool forceSync = false}) async {
    if (state is! HomeLoaded) return;
    if (_snapping) return;

    final current = state as HomeLoaded;
    if (current.tracking == null) return;

    _snapping = true;
    emit(current.copyWith(isSnapping: true));

    final wasLimitKnown = LocalStorageService.isLocationSizeLimitHit();

    try {
      final result =
          await LocationSyncService.processBatchAndEmitLatestLocationData(
        userId: userId,
        trackingId: current.tracking!.id,
        forceSync: forceSync,
      );

      if (state is HomeLoaded) {
        final latest = state as HomeLoaded;
        emit(result == null
            ? latest.copyWith(isSnapping: false)
            : latest.copyWith(
                isSnapping: false,
                finalLocations: result.finalLocations,
                finalLocationsDistance: result.finalLocationsDistance,
                currentBatch: result.currentBatch,
                currentBatchDistance: result.currentBatchDistance,
                lastKnownLocation: result.lastKnownLocation,
              ));
      }
    } catch (e) {
      // The service already catches its own errors and returns null — this
      // is a backstop for anything else, so isSnapping never gets stuck true.
      print('[HomeBloc] processBatch error: $e');
      if (state is HomeLoaded) {
        emit((state as HomeLoaded).copyWith(isSnapping: false));
      }
    } finally {
      _snapping = false;
    }

    // DataManager.persistLocations marks the size-limit flag internally on
    // the relevant failure — this just decides whether to show the
    // one-time toast, then restores the tracking UI (HomeError isn't a
    // HomeLoaded subtype, so the map/tracking view would otherwise
    // disappear until the next event).
    if (!wasLimitKnown && LocalStorageService.isLocationSizeLimitHit()) {
      final latestLoaded = state is HomeLoaded ? state as HomeLoaded : current;
      emit(HomeError(_sizeLimitMessage));
      emit(latestLoaded.copyWith());
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
}
