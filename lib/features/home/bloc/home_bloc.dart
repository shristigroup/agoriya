import 'package:flutter_bloc/flutter_bloc.dart';
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

  HomeBloc({required this.userId, FirestoreRepository? repo})
      : _repo = repo ?? FirestoreRepository(),
        super(HomeInitial()) {
    on<HomeInitEvent>(_onInit);
    on<PunchInEvent>(_onPunchIn);
    on<PunchOutEvent>(_onPunchOut);
    on<NewLocationPointEvent>(_onNewLocationPoint);
    on<RefreshDistanceEvent>(_onRefreshDistance);
    on<CreateVisitEvent>(_onCreateVisit);
    on<UpdateVisitEvent>(_onUpdateVisit);
    on<CheckOutVisitEvent>(_onCheckOutVisit);
    on<FilterVisitsByClientEvent>(_onFilterVisits);
    on<AddCommentEvent>(_onAddComment);
  }

  Future<void> _onInit(HomeInitEvent event, Emitter<HomeState> emit) async {
    emit(HomeLoading());
    try {
      final today = AppUtils.todayKey();

      // Load from local first
      AttendanceModel? attendance = LocalStorageService.getAttendance(today);
      final visits = LocalStorageService.getAllVisits();
      final locations = LocalStorageService.getTodayLocations();

      // Determine last known location for map centering
      LatLng? lastKnownLocation;
      final (prevLat, prevLng) = LocalStorageService.getPrevPunchOutLocation();
      if (prevLat != null && prevLng != null) {
        lastKnownLocation = LatLng(prevLat, prevLng);
      }

      // Emit cached state immediately
      emit(HomeLoaded(
        attendance: attendance,
        locations: locations,
        visits: visits,
        filteredVisits: visits,
        lastKnownLocation: lastKnownLocation,
      ));

      // Fetch fresh data in background
      final freshAttendance = await _repo.getAttendance(userId, today);
      if (freshAttendance != null) {
        await LocalStorageService.saveAttendance(freshAttendance);
        attendance = freshAttendance;
      }

      // Fetch prev day punch out location if not cached
      if (prevLat == null) {
        final lastAtt = await _repo.getLastAttendance(userId);
        if (lastAtt?.punchOutLocation != null) {
          final loc = lastAtt!.punchOutLocation!;
          await LocalStorageService.savePrevPunchOutLocation(loc.latitude, loc.longitude);
          lastKnownLocation = loc;
        }
      }

      // Fetch visits from Firestore and merge
      final remoteVisits = await _repo.getVisits(userId);
      for (final v in remoteVisits) {
        await LocalStorageService.saveVisit(v);
      }
      final allVisits = LocalStorageService.getAllVisits();

      // Fetch today's locations if punched in
      if (freshAttendance?.isPunchedIn == true && !freshAttendance!.isPunchedOut) {
        final dayLocs = await _repo.getDayLocations(userId, today);
        if (dayLocs != null) {
          await LocalStorageService.saveTodayLocations(dayLocs.points);
        }
      }

      final freshLocations = LocalStorageService.getTodayLocations();

      emit(HomeLoaded(
        attendance: attendance,
        locations: freshLocations,
        visits: allVisits,
        filteredVisits: allVisits,
        lastKnownLocation: lastKnownLocation,
      ));
    } catch (e) {
      emit(HomeError(e.toString()));
    }
  }

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

      // Start background tracking
      await LocationTrackingService.start(userId, today);

      emit(PunchInSuccess(attendance));
    } catch (e) {
      emit(HomeError(e.toString()));
    }
  }

  Future<void> _onPunchOut(PunchOutEvent event, Emitter<HomeState> emit) async {
    final current = state;
    if (current is! HomeLoaded) return;

    try {
      final today = AppUtils.todayKey();
      final now = DateTime.now();

      // Get current location for punch out
      final locations = LocalStorageService.getTodayLocations();
      LatLng? lastLoc = locations.isNotEmpty ? locations.last.position : null;

      if (lastLoc == null) {
        // Try to get current location
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
          );
          lastLoc = LatLng(pos.latitude, pos.longitude);
        } catch (_) {}
      }

      // Stop tracking
      LocationTrackingService.stop();

      // Calculate final distance via OSRM
      double finalDistance = current.attendance?.distance ?? 0.0;
      if (locations.length >= 2) {
        final snapped = await OsrmService.snapToRoads(
          locations.map((p) => p.position).toList(),
        );
        finalDistance = await OsrmService.calculateRouteDistance(snapped);
      }

      final geoPoint = lastLoc != null
          ? GeoPoint(lastLoc.latitude, lastLoc.longitude)
          : const GeoPoint(0, 0);

      await _repo.punchOut(userId, today, now, geoPoint);
      await _repo.updateDistance(userId, today, finalDistance);

      // Save punch out location for next day map center
      if (lastLoc != null) {
        await LocalStorageService.savePrevPunchOutLocation(
          lastLoc.latitude,
          lastLoc.longitude,
        );
      }

      final updatedAttendance = current.attendance!.copyWith(
        punchOutTimestamp: now,
        punchOutLocation: lastLoc,
        distance: finalDistance,
      );
      await LocalStorageService.saveAttendance(updatedAttendance);

      // Clear today's locations from local (only keep for current day)
      await LocalStorageService.clearTodayLocations();

      final totalTime = updatedAttendance.attendanceDuration;
      emit(PunchOutSuccess(attendance: updatedAttendance, totalTime: totalTime));
    } catch (e) {
      emit(HomeError(e.toString()));
    }
  }

  Future<void> _onNewLocationPoint(
      NewLocationPointEvent event, Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    final current = state as HomeLoaded;
    final newPoint = LocationPoint(
      position: LatLng(event.lat, event.lng),
      timestamp: event.timestamp,
    );
    final updatedLocations = [...current.locations, newPoint];
    await LocalStorageService.saveTodayLocations(updatedLocations);
    emit(current.copyWith(locations: updatedLocations));
  }

  Future<void> _onRefreshDistance(
      RefreshDistanceEvent event, Emitter<HomeState> emit) async {
    if (state is! HomeLoaded) return;
    final current = state as HomeLoaded;
    final locations = current.locations;
    if (locations.length < 2) return;

    try {
      final snapped = await OsrmService.snapToRoads(
        locations.map((p) => p.position).toList(),
      );
      final distance = await OsrmService.calculateRouteDistance(snapped);
      final today = AppUtils.todayKey();
      await _repo.updateDistance(userId, today, distance);
      final updatedAtt = current.attendance?.copyWith(distance: distance);
      if (updatedAtt != null) {
        await LocalStorageService.saveAttendance(updatedAtt);
      }
      emit(current.copyWith(attendance: updatedAtt));
    } catch (_) {}
  }

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

      // Increment visit count in attendance
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
    final updated = event.visit.copyWith(checkoutTimestamp: DateTime.now());
    add(UpdateVisitEvent(updated));
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
      final comment = VisitComment(
        id: '',
        userId: user.id,
        userName: user.fullName,
        text: event.text,
        timestamp: DateTime.now(),
      );
      await _repo.addComment(event.targetUserId, event.visitId, comment);
    } catch (e) {
      emit(HomeError(e.toString()));
    }
  }
}
