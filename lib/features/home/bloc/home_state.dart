import '../../../data/models/tracking_model.dart';
import '../../../data/models/visit_model.dart';
import '../../../data/models/location_model.dart';
import 'package:latlong2/latlong.dart';

abstract class HomeState {}

class HomeInitial extends HomeState {}

class HomeLoading extends HomeState {}

class HomeLoaded extends HomeState {
  final TrackingModel? tracking;

  /// OSRM-snapped points committed to Firestore. Reading these back after each
  /// commit means this list is always identical to the Firestore locations array,
  /// ensuring owner and manager see the same snapped path.
  final List<LocationPoint> finalLocations;

  /// Raw GPS points collected since the last committed batch.
  /// These are NOT yet in Firestore. Cleared at the start of each
  /// ProcessCurrentBatch operation (before the OSRM await) so new points
  /// arriving during snapping accumulate into a fresh batch.
  final List<LocationPoint> currentBatch;

  final List<VisitModel> visits;
  final LatLng? lastKnownLocation;

  /// Updated on every GPS event from the background service, including
  /// stationary pings that don't add a new location point. Used by the map
  /// marker to show when the last GPS fix was received.
  final DateTime? lastGpsUpdateTime;

  final bool isRefreshing;
  final bool isSnapping; // true while OSRM snap is in flight
  final bool isPunchingOut;

  /// OSRM-accurate total for all committed batches.
  final double finalLocationsDistance;

  /// Live haversine estimate for the points in currentBatch.
  final double currentBatchDistance;

  HomeLoaded({
    this.tracking,
    this.finalLocations = const [],
    this.currentBatch = const [],
    this.visits = const [],
    this.lastKnownLocation,
    this.lastGpsUpdateTime,
    this.isRefreshing = false,
    this.isSnapping = false,
    this.isPunchingOut = false,
    this.finalLocationsDistance = 0.0,
    this.currentBatchDistance = 0.0,
  });

  /// Combined view used by TrackTab and punchOut logic.
  List<LocationPoint> get allLocations => [...finalLocations, ...currentBatch];

  /// Single display value shown in the stats strip.
  double get displayDistance => finalLocationsDistance + currentBatchDistance;

  bool get isPunchedIn => tracking?.isPunchedIn ?? false;
  bool get isPunchedOut => tracking?.isPunchedOut ?? false;

  HomeLoaded copyWith({
    TrackingModel? tracking,
    List<LocationPoint>? finalLocations,
    List<LocationPoint>? currentBatch,
    List<VisitModel>? visits,
    LatLng? lastKnownLocation,
    DateTime? lastGpsUpdateTime,
    bool? isRefreshing,
    bool? isSnapping,
    bool? isPunchingOut,
    double? finalLocationsDistance,
    double? currentBatchDistance,
    bool clearLastKnown = false,
  }) =>
      HomeLoaded(
        tracking: tracking ?? this.tracking,
        finalLocations: finalLocations ?? this.finalLocations,
        currentBatch: currentBatch ?? this.currentBatch,
        visits: visits ?? this.visits,
        lastKnownLocation: clearLastKnown
            ? null
            : (lastKnownLocation ?? this.lastKnownLocation),
        lastGpsUpdateTime: lastGpsUpdateTime ?? this.lastGpsUpdateTime,
        isRefreshing: isRefreshing ?? this.isRefreshing,
        isSnapping: isSnapping ?? this.isSnapping,
        isPunchingOut: isPunchingOut ?? this.isPunchingOut,
        finalLocationsDistance:
            finalLocationsDistance ?? this.finalLocationsDistance,
        currentBatchDistance:
            currentBatchDistance ?? this.currentBatchDistance,
      );
}

class HomeError extends HomeState {
  final String message;
  HomeError(this.message);
}

class PunchInSuccess extends HomeState {
  final TrackingModel tracking;
  PunchInSuccess(this.tracking);
}

class PunchOutSuccess extends HomeState {
  final TrackingModel tracking;
  final Duration totalTime;
  PunchOutSuccess({required this.tracking, required this.totalTime});
}

class VisitCreated extends HomeState {
  final VisitModel visit;
  VisitCreated(this.visit);
}

class VisitUpdated extends HomeState {
  final VisitModel visit;
  VisitUpdated(this.visit);
}
