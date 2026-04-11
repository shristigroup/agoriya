import '../../../data/models/attendance_model.dart';
import '../../../data/models/visit_model.dart';
import '../../../data/models/location_model.dart';
import 'package:latlong2/latlong.dart';

abstract class HomeState {}

class HomeInitial extends HomeState {}

class HomeLoading extends HomeState {}

class HomeLoaded extends HomeState {
  final AttendanceModel? attendance;
  final List<LocationPoint> locations;
  final List<VisitModel> visits;
  final List<VisitModel> filteredVisits;
  final String? filterClient;
  final LatLng? lastKnownLocation; // prev day punch out
  final bool isRefreshing;

  HomeLoaded({
    this.attendance,
    this.locations = const [],
    this.visits = const [],
    this.filteredVisits = const [],
    this.filterClient,
    this.lastKnownLocation,
    this.isRefreshing = false,
  });

  bool get isPunchedIn => attendance?.isPunchedIn ?? false;
  bool get isPunchedOut => attendance?.isPunchedOut ?? false;

  HomeLoaded copyWith({
    AttendanceModel? attendance,
    List<LocationPoint>? locations,
    List<VisitModel>? visits,
    List<VisitModel>? filteredVisits,
    String? filterClient,
    LatLng? lastKnownLocation,
    bool? isRefreshing,
    bool clearFilter = false,
    bool clearLastKnown = false,
  }) =>
      HomeLoaded(
        attendance: attendance ?? this.attendance,
        locations: locations ?? this.locations,
        visits: visits ?? this.visits,
        filteredVisits: filteredVisits ?? this.filteredVisits,
        filterClient: clearFilter ? null : (filterClient ?? this.filterClient),
        lastKnownLocation: clearLastKnown ? null : (lastKnownLocation ?? this.lastKnownLocation),
        isRefreshing: isRefreshing ?? this.isRefreshing,
      );
}

class HomeError extends HomeState {
  final String message;
  HomeError(this.message);
}

class PunchInSuccess extends HomeState {
  final AttendanceModel attendance;
  PunchInSuccess(this.attendance);
}

class PunchOutSuccess extends HomeState {
  final AttendanceModel attendance;
  final Duration totalTime;
  PunchOutSuccess({required this.attendance, required this.totalTime});
}

class VisitCreated extends HomeState {
  final VisitModel visit;
  VisitCreated(this.visit);
}

class VisitUpdated extends HomeState {
  final VisitModel visit;
  VisitUpdated(this.visit);
}
