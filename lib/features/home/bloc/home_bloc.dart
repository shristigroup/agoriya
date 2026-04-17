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
      if (data == null) return;
      add(NewLocationPointEvent(
        lat: (data['lat'] as num).toDouble(),
        lng: (data['lng'] as num).toDouble(),
        timestamp: DateTime.parse(data['timestamp'] as String),
        processBatch: (data['processBatch'] as bool?) ?? false,
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

      // Snap the final currentBatch inline.
      final snapResult = await _snapBatch(
        batch: List<LocationPoint>.from(current.currentBatch),
        finalLocations: current.finalLocations,
      );

      double osrmDistance = 0.0;
      List<LocationPoint> snappedBatch = [];
      if (snapResult != null) {
        (snappedBatch, osrmDistance) = snapResult;
      }

      final newFinalDistance = current.finalLocationsDistance + osrmDistance;
      var allLocations = [...current.finalLocations, ...snappedBatch];

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
    if (current.currentBatch.isEmpty) return;
    if (_snapping) return;

    _snapping = true;
    emit(current.copyWith(isSnapping: true));

    try {
      final snapResult = await _snapBatch(
        batch: List<LocationPoint>.from(current.currentBatch),
        finalLocations: current.finalLocations,
      );

      if (snapResult == null) {
        if (state is HomeLoaded) {
          emit((state as HomeLoaded).copyWith(isSnapping: false));
        }
        return;
      }

      final (snappedBatch, _) = snapResult;

      // Persist snapped batch to Hive so a subsequent relaunch also shows a
      // clean path. Distance estimate is unchanged — accurate value comes from
      // OSRM when ProcessCurrentBatchEvent fires on batchFlushed.
      await DataManager.saveCurrentBatch(
          snappedBatch, current.currentBatchDistance);

      if (state is HomeLoaded) {
        emit((state as HomeLoaded).copyWith(
          currentBatch: snappedBatch,
          isSnapping: false,
        ));
      }
    } catch (e) {
      debugPrint('[HomeBloc] appResumed snap error: $e');
      if (state is HomeLoaded) {
        emit((state as HomeLoaded).copyWith(isSnapping: false));
      }
    }
  }

  // ── New Location Point ────────────────────────────────────────────────────

  Future<void> _onNewLocationPoint(
      NewLocationPointEvent event, Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    final current = state as HomeLoaded;
    if (current.tracking?.isPunchedIn != true) return;

    final newPosition = LatLng(event.lat, event.lng);

    // Last stored point — used for distance check and duration calculation.
    final lastPoint = current.currentBatch.isNotEmpty
        ? current.currentBatch.last
        : current.finalLocations.isNotEmpty
            ? current.finalLocations.last
            : null;

    final distanceMeters = lastPoint != null
        ? _haversineMeters(lastPoint.position, newPosition)
        : 0.0;

    // ── Stationary: within threshold → update durationSeconds on last point ──
    if (lastPoint != null &&
        distanceMeters < AppConstants.stationaryThresholdMeters.toDouble()) {
      final durationSeconds =
          event.timestamp.difference(lastPoint.timestamp).inSeconds;

      var updatedBatch = current.currentBatch;
      var updatedFinal = current.finalLocations;

      if (current.currentBatch.isNotEmpty) {
        final pts = List<LocationPoint>.from(current.currentBatch);
        pts[pts.length - 1] =
            pts.last.copyWith(durationSeconds: durationSeconds);
        updatedBatch = pts;
        await DataManager.saveCurrentBatch(
            updatedBatch, current.currentBatchDistance);
        debugPrint('[HomeBloc] duration update | source=currentBatch'
            ' | ts=${pts.last.timestamp.toIso8601String()}'
            ' | lat=${pts.last.position.latitude}'
            ' | lng=${pts.last.position.longitude}'
            ' | durationSeconds=$durationSeconds');
      } else {
        final pts = List<LocationPoint>.from(current.finalLocations);
        pts[pts.length - 1] =
            pts.last.copyWith(durationSeconds: durationSeconds);
        updatedFinal = pts;
        await DataManager.saveFinalLocations(updatedFinal);
        debugPrint('[HomeBloc] duration update | source=finalLocations'
            ' | ts=${pts.last.timestamp.toIso8601String()}'
            ' | lat=${pts.last.position.latitude}'
            ' | lng=${pts.last.position.longitude}'
            ' | durationSeconds=$durationSeconds');
      }

      emit(current.copyWith(
        currentBatch: updatedBatch,
        finalLocations: updatedFinal,
        lastKnownLocation: newPosition,
        lastGpsUpdateTime: event.timestamp,
      ));

      if (event.processBatch) await _processBatch(emit);
      return;
    }

    // ── Movement: add new point to batch ─────────────────────────────────────
    final deltaKm = distanceMeters / 1000.0;
    final newPoint = LocationPoint(
      position: newPosition,
      timestamp: event.timestamp,
      isSnapped: false,
    );
    final updatedBatch = [...current.currentBatch, newPoint];
    final newBatchDistance = current.currentBatchDistance + deltaKm;

    await DataManager.saveCurrentBatch(updatedBatch, newBatchDistance);

    emit(current.copyWith(
      currentBatch: updatedBatch,
      lastKnownLocation: newPosition,
      lastGpsUpdateTime: event.timestamp,
      currentBatchDistance: newBatchDistance,
    ));

    if (event.processBatch) await _processBatch(emit);
  }

  // ── Process Current Batch ─────────────────────────────────────────────────

  Future<void> _processBatch(Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;

    final current = state as HomeLoaded;
    if (current.tracking == null) return;

    final batchToProcess = List<LocationPoint>.from(current.currentBatch);
    if (batchToProcess.isEmpty && current.finalLocations.isEmpty) return;

    // ── Step 1: clear currentBatch in state and Hive.
    emit(current.copyWith(
      currentBatch: [],
      currentBatchDistance: 0.0,
      isSnapping: true,
    ));
    await DataManager.saveCurrentBatch([], 0.0);

    try {
      // ── Step 2: snap batch if non-empty; osrmDistance stays 0 if stationary.
      double osrmDistance = 0.0;
      List<LocationPoint> snappedBatch = [];

      if (batchToProcess.isNotEmpty) {
        final snapResult = await _snapBatch(
          batch: batchToProcess,
          finalLocations: current.finalLocations,
        );
        if (snapResult != null) {
          (snappedBatch, osrmDistance) = snapResult;
        }
      }

      // ── Step 3: compute cumulative distance and build full locations array.
      final latestState = state is HomeLoaded ? state as HomeLoaded : current;
      final newFinalDistance = latestState.finalLocationsDistance + osrmDistance;
      var allLocations = [...latestState.finalLocations, ...snappedBatch];

      if (allLocations.isEmpty) {
        if (state is HomeLoaded) {
          emit((state as HomeLoaded).copyWith(isSnapping: false));
        }
        return;
      }

      // ── Step 4: stamp last point with cumulative + batch distances.
      allLocations = [
        ...allLocations.take(allLocations.length - 1),
        allLocations.last.copyWith(
          cumulativeDistanceKm: newFinalDistance,
          batchDistanceKm: osrmDistance,
        ),
      ];

      // ── Step 5: write to Firestore.
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

      // ── Step 6: update state.
      if (state is! HomeLoaded) return;
      emit((state as HomeLoaded).copyWith(
        isSnapping: false,
        finalLocations: allLocations,
        finalLocationsDistance: newFinalDistance,
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
      distance +=
          _haversineMeters(distInput[i].position, distInput[i + 1].position) /
              1000.0;
    }

    return (snapped, distance);
  }

  /// Returns distance in metres between two LatLng points.
  double _haversineMeters(LatLng a, LatLng b) {
    const r = 6371000.0; // Earth radius in metres
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
