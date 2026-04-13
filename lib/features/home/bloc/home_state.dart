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
  final LatLng? lastKnownLocation;
  final bool isRefreshing;
  final bool isSnapping;
  final bool isPunchingOut;
  final double displayDistance;

  HomeLoaded({
    this.attendance,
    this.locations = const [],
    this.visits = const [],
    this.lastKnownLocation,
    this.isRefreshing = false,
    this.isSnapping = false,
    this.isPunchingOut = false,
    this.displayDistance = 0.0,
  });

  bool get isPunchedIn => attendance?.isPunchedIn ?? false;
  bool get isPunchedOut => attendance?.isPunchedOut ?? false;

  HomeLoaded copyWith({
    AttendanceModel? attendance,
    List<LocationPoint>? locations,
    List<VisitModel>? visits,
    LatLng? lastKnownLocation,
    bool? isRefreshing,
    bool? isSnapping,
    bool? isPunchingOut,
    double? displayDistance,
    bool clearLastKnown = false,
  }) =>
      HomeLoaded(
        attendance: attendance ?? this.attendance,
        locations: locations ?? this.locations,
        visits: visits ?? this.visits,
        lastKnownLocation:
            clearLastKnown ? null : (lastKnownLocation ?? this.lastKnownLocation),
        isRefreshing: isRefreshing ?? this.isRefreshing,
        isSnapping: isSnapping ?? this.isSnapping,
        isPunchingOut: isPunchingOut ?? this.isPunchingOut,
        displayDistance: displayDistance ?? this.displayDistance,
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
