import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_event.dart';
import 'home_state.dart';
import '../../../data/repositories/firestore_repository.dart';
import '../../../data/local/local_storage_service.dart';
import '../../../data/models/attendance_model.dart';
import '../../../data/models/visit_model.dart';
import '../../../data/models/location_model.dart';
import '../../../core/utils/app_utils.dart';
import '../../../services/location_tracking_service.dart';
import '../../../services/osrm_service.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final FirestoreRepository _repo;
  final String userId;

  // Guards against concurrent or duplicate operations
  bool _snapping = false;
  bool _punchingOut = false;

  // Background service subscriptions (owned here so home_screen.dart stays clean)
  StreamSubscription? _newPointSub;
  StreamSubscription? _batchFlushedSub;

  HomeBloc({required this.userId, FirestoreRepository? repo})
      : _repo = repo ?? FirestoreRepository(),
        super(HomeInitial()) {
    on<HomeInitEvent>(_onInit);
    on<PunchInEvent>(_onPunchIn);
    on<PunchOutEvent>(_onPunchOut);
    on<ResumeSessionEvent>(_onResumeSession);
    on<NewLocationPointEvent>(_onNewLocationPoint);
    on<SnapDirtyPointsEvent>(_onSnapDirtyPoints);
    on<CreateVisitEvent>(_onCreateVisit);
    on<UpdateVisitEvent>(_onUpdateVisit);
    on<CheckOutVisitEvent>(_onCheckOutVisit);
    on<FilterVisitsByClientEvent>(_onFilterVisits);
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
      add(SnapDirtyPointsEvent());
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

    // Phase 1: emit from local cache immediately
    AttendanceModel? attendance = LocalStorageService.getAttendance(today);
    final visits = LocalStorageService.getAllVisits();
    final locations = LocalStorageService.getTodayLocations();
    final displayDistance = LocalStorageService.getTotalDistanceDirty();

    LatLng? lastKnownLocation;
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) lastKnownLocation = LatLng(pos.latitude, pos.longitude);
    } catch (_) {}

    emit(HomeLoaded(
      attendance: attendance,
      locations: locations,
      visits: visits,
      filteredVisits: visits,
      lastKnownLocation: lastKnownLocation,
      displayDistance: displayDistance,
    ));

    // Phase 2: background refresh from Firestore
    try {
      final freshAttendance = await _repo.getAttendance(userId, today);
      if (freshAttendance != null) {
        await LocalStorageService.saveAttendance(freshAttendance);
        attendance = freshAttendance;
      }

      final remoteVisits = await _repo.getVisits(userId);
      for (final v in remoteVisits) {
        await LocalStorageService.saveVisit(v);
      }
      final allVisits = LocalStorageService.getAllVisits();

      if (freshAttendance?.isPunchedIn == true && !freshAttendance!.isPunchedOut) {
        final dayLocs = await _repo.getDayLocations(userId, today);
        if (dayLocs != null) {
          await LocalStorageService.saveTodayLocations(dayLocs.points);
        }
      }

      final freshLocations = LocalStorageService.getTodayLocations();

      // Use the better of local estimate vs Firestore haversine distance
      final firestoreDist = freshAttendance?.distance ?? 0.0;
      final localDist = LocalStorageService.getTotalDistanceDirty();
      final bestDist = firestoreDist > localDist ? firestoreDist : localDist;
      if (bestDist > localDist) {
        await LocalStorageService.saveTotalDistanceDirty(bestDist);
      }

      emit(HomeLoaded(
        attendance: attendance,
        locations: freshLocations,
        visits: allVisits,
        filteredVisits: allVisits,
        lastKnownLocation: lastKnownLocation,
        displayDistance: bestDist,
      ));

      // Phase 3: snap dirty points if any exist
      if (freshLocations.any((p) => !p.isSnapped)) {
        add(SnapDirtyPointsEvent());
      }
    } catch (e) {
      emit(HomeError(e.toString()));
      emit(HomeLoaded(
        attendance: attendance,
        locations: locations,
        visits: visits,
        filteredVisits: visits,
        lastKnownLocation: lastKnownLocation,
        displayDistance: displayDistance,
      ));
    }
  }

  // ── Punch In ──────────────────────────────────────────────────────────────

  Future<void> _onPunchIn(PunchInEvent event, Emitter<HomeState> emit) async {
    try {
      final today = AppUtils.todayKey();
      final now = DateTime.now();
      final attendance = AttendanceModel(
        date: today,
        punchInTimestamp: now,
        punchInImage: event.imageUrl,
      );
      await _repo.punchIn(userId, today, now, event.imageUrl);
      await LocalStorageService.saveAttendance(attendance);
      await LocalStorageService.clearTodayLocations();
      await LocalStorageService.clearDistances(); // reset for new day

      await LocationTrackingService.start(userId, today);

      emit(PunchInSuccess(attendance));
    } catch (e) {
      emit(HomeError(e.toString()));
    }
  }

  // ── Punch Out ─────────────────────────────────────────────────────────────

  Future<void> _onPunchOut(PunchOutEvent event, Emitter<HomeState> emit) async {
    if (_punchingOut) return;
    _punchingOut = true;

    final current = state;
    if (current is! HomeLoaded) { _punchingOut = false; return; }

    // Show loading overlay immediately — prevents double-tap and shows feedback.
    emit(current.copyWith(isPunchingOut: true));

    try {
      final today = AppUtils.todayKey();
      final now = DateTime.now();

      // Stop background tracking first, wait briefly for final flush.
      LocationTrackingService.stop();
      await Future.delayed(const Duration(seconds: 1));

      // Determine last known position.
      final locations = LocalStorageService.getTodayLocations();
      LatLng? lastLoc = locations.isNotEmpty ? locations.last.position : null;
      if (lastLoc == null) {
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
          );
          lastLoc = LatLng(pos.latitude, pos.longitude);
        } catch (_) {}
      }

      // Snap any remaining dirty points (≤15, one fast OSRM call).
      final dirty = locations.where((p) => !p.isSnapped).toList();
      double finalDistance = LocalStorageService.getTotalDistance();

      if (dirty.isNotEmpty) {
        LocationPoint? anchor;
        for (final p in locations.reversed) {
          if (p.isSnapped) { anchor = p; break; }
        }

        final input = [if (anchor != null) anchor, ...dirty];
        final tracepoints = await OsrmService.snapTracepoints(
          input.map((p) => p.position).toList(),
        );

        final startIdx = anchor != null ? 1 : 0;
        final snappedDirty = <LocationPoint>[];
        for (int i = startIdx; i < input.length; i++) {
          final pos = tracepoints[i] ?? input[i].position;
          snappedDirty.add(LocationPoint(
            position: pos,
            timestamp: input[i].timestamp,
            isSnapped: true,
          ));
        }

        // Incremental road distance for this final batch.
        final distInput = [if (anchor != null) anchor, ...snappedDirty];
        for (int i = 0; i < distInput.length - 1; i++) {
          finalDistance += _haversine(distInput[i].position, distInput[i + 1].position);
        }

        await _repo.replaceLocationsWithSnapped(userId, today, dirty, snappedDirty);
      }

      final geoPoint = lastLoc != null
          ? GeoPoint(lastLoc.latitude, lastLoc.longitude)
          : const GeoPoint(0, 0);

      await _repo.punchOut(userId, today, now, geoPoint);
      await _repo.updateDistance(userId, today, finalDistance);

      final updatedAttendance = current.attendance!.copyWith(
        punchOutTimestamp: now,
        punchOutLocation: lastLoc,
        distance: finalDistance,
      );
      await LocalStorageService.saveAttendance(updatedAttendance);
      await LocalStorageService.clearTodayLocations();
      await LocalStorageService.clearDistances();

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

      // Clears punchOutTimestamp + punchOutLocation — Cloud Function detects
      // this write and sends FCM "resumed session" notification to the manager.
      await _repo.resumeSession(userId, today);

      final resumed = AttendanceModel(
        date: current.attendance!.date,
        punchInTimestamp: current.attendance!.punchInTimestamp,
        punchOutTimestamp: null,
        punchInImage: current.attendance!.punchInImage,
        distance: current.attendance!.distance,
        punchOutLocation: null,
        customerVisitCount: current.attendance!.customerVisitCount,
      );
      await LocalStorageService.saveAttendance(resumed);

      // Restart background location tracking from where it left off.
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
      isSnapped: false, // raw GPS — will be snapped on next batchFlushed
    );

    // Haversine delta for live distance display.
    double delta = 0;
    if (current.locations.isNotEmpty) {
      delta = _haversine(current.locations.last.position, newPoint.position);
    }

    final updatedLocations = [...current.locations, newPoint];
    final newDisplayDistance = current.displayDistance + delta;

    await LocalStorageService.saveTodayLocations(updatedLocations);
    await LocalStorageService.saveTotalDistanceDirty(newDisplayDistance);

    emit(current.copyWith(
      locations: updatedLocations,
      displayDistance: newDisplayDistance,
    ));
  }

  // ── Snap Dirty Points ─────────────────────────────────────────────────────

  Future<void> _onSnapDirtyPoints(
      SnapDirtyPointsEvent event, Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    if (_snapping) return; // already in progress

    final current = state as HomeLoaded;
    final dirty = current.locations.where((p) => !p.isSnapped).toList();
    if (dirty.isEmpty) return;

    _snapping = true;
    emit(current.copyWith(isSnapping: true));

    try {
      final today = AppUtils.todayKey();
      double totalDistance = LocalStorageService.getTotalDistance();

      // Find last snapped point as the distance anchor.
      LocationPoint? anchor;
      for (final p in current.locations.reversed) {
        if (p.isSnapped) { anchor = p; break; }
      }

      // Process dirty points in sub-batches of 15 (aligned with flush cadence).
      final batches = _chunk(dirty, 15);
      final allSnapped = <LocationPoint>[];

      for (final batch in batches) {
        final input = [if (anchor != null) anchor, ...batch];
        final tracepoints = await OsrmService.snapTracepoints(
          input.map((p) => p.position).toList(),
        );

        final startIdx = anchor != null ? 1 : 0;
        final snappedBatch = <LocationPoint>[];
        for (int i = startIdx; i < input.length; i++) {
          final pos = tracepoints[i] ?? input[i].position;
          snappedBatch.add(LocationPoint(
            position: pos,
            timestamp: input[i].timestamp,
            isSnapped: true,
          ));
        }

        // Haversine between consecutive snapped points for road-accurate distance.
        final distInput = [if (anchor != null) anchor, ...snappedBatch];
        for (int i = 0; i < distInput.length - 1; i++) {
          totalDistance += _haversine(distInput[i].position, distInput[i + 1].position);
        }

        allSnapped.addAll(snappedBatch);
        anchor = snappedBatch.last;

        // Replace this batch in Firestore.
        await _repo.replaceLocationsWithSnapped(userId, today, batch, snappedBatch);
      }

      await LocalStorageService.saveTotalDistance(totalDistance);
      await LocalStorageService.saveTotalDistanceDirty(totalDistance); // no dirty remaining
      await _repo.updateDistance(userId, today, totalDistance);

      // Rebuild location list: existing snapped + newly snapped, sorted by time.
      final updatedLocations = [
        ...current.locations.where((p) => p.isSnapped),
        ...allSnapped,
      ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      await LocalStorageService.saveTodayLocations(updatedLocations);

      emit(current.copyWith(
        isSnapping: false,
        locations: updatedLocations,
        displayDistance: totalDistance,
      ));
    } catch (e) {
      debugPrint('[HomeBloc] snapDirtyPoints error: $e');
      if (state is HomeLoaded) {
        emit((state as HomeLoaded).copyWith(isSnapping: false));
      }
    } finally {
      _snapping = false;
    }
  }

  // ── Visits ────────────────────────────────────────────────────────────────

  Future<void> _onCreateVisit(CreateVisitEvent event, Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    final current = state as HomeLoaded;
    try {
      final now = DateTime.now();
      final visitId = AppUtils.visitDocId(event.clientName, event.location, now);
      final visit = VisitModel(
        id: visitId,
        clientName: event.clientName,
        location: event.location,
        checkinTimestamp: now,
      );
      await _repo.createVisit(userId, visit);
      await LocalStorageService.saveVisit(visit);

      final today = AppUtils.todayKey();
      await _repo.incrementVisitCount(userId, today);
      final updatedAtt = current.attendance?.copyWith(
        customerVisitCount: (current.attendance?.customerVisitCount ?? 0) + 1,
      );
      if (updatedAtt != null) await LocalStorageService.saveAttendance(updatedAtt);

      final allVisits = LocalStorageService.getAllVisits();
      final filtered = current.filterClient != null
          ? allVisits.where((v) => v.clientName == current.filterClient).toList()
          : allVisits;

      emit(VisitCreated(visit));
      emit(current.copyWith(
        attendance: updatedAtt,
        visits: allVisits,
        filteredVisits: filtered,
      ));
    } catch (e) {
      emit(HomeError(e.toString()));
    }
  }

  Future<void> _onUpdateVisit(UpdateVisitEvent event, Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    final current = state as HomeLoaded;
    try {
      await _repo.updateVisit(userId, event.visit);
      await LocalStorageService.saveVisit(event.visit);
      final allVisits = LocalStorageService.getAllVisits();
      final filtered = current.filterClient != null
          ? allVisits.where((v) => v.clientName == current.filterClient).toList()
          : allVisits;
      emit(VisitUpdated(event.visit));
      emit(current.copyWith(visits: allVisits, filteredVisits: filtered));
    } catch (e) {
      emit(HomeError(e.toString()));
    }
  }

  Future<void> _onCheckOutVisit(CheckOutVisitEvent event, Emitter<HomeState> emit) async {
    add(UpdateVisitEvent(event.visit.copyWith(checkoutTimestamp: DateTime.now())));
  }

  Future<void> _onFilterVisits(
      FilterVisitsByClientEvent event, Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    final current = state as HomeLoaded;
    final filtered = event.clientName == null
        ? current.visits
        : current.visits.where((v) => v.clientName == event.clientName).toList();
    emit(current.copyWith(
      filteredVisits: filtered,
      filterClient: event.clientName,
      clearFilter: event.clientName == null,
    ));
  }

  Future<void> _onAddComment(AddCommentEvent event, Emitter<HomeState> emit) async {
    try {
      final user = LocalStorageService.getUser();
      if (user == null) return;
      await _repo.addComment(
        event.targetUserId,
        event.visitId,
        VisitComment(
          id: '',
          userId: user.id,
          userName: user.fullName,
          text: event.text,
          timestamp: DateTime.now(),
        ),
      );
    } catch (e) {
      emit(HomeError(e.toString()));
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Haversine distance in km between two LatLng points.
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

  List<List<T>> _chunk<T>(List<T> list, int size) {
    final chunks = <List<T>>[];
    for (int i = 0; i < list.length; i += size) {
      chunks.add(list.sublist(i, (i + size).clamp(0, list.length)));
    }
    return chunks;
  }
}
