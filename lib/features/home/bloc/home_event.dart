import '../../../data/models/visit_model.dart';

abstract class HomeEvent {}

class HomeInitEvent extends HomeEvent {
  final String userId;
  HomeInitEvent(this.userId);
}

class PunchInEvent extends HomeEvent {
  final String imageUrl;
  PunchInEvent(this.imageUrl);
}

class PunchOutEvent extends HomeEvent {}

class NewLocationPointEvent extends HomeEvent {
  final double lat;
  final double lng;
  final DateTime timestamp;
  NewLocationPointEvent({required this.lat, required this.lng, required this.timestamp});
}

class CreateVisitEvent extends HomeEvent {
  final String clientName;
  final String location;
  CreateVisitEvent({required this.clientName, required this.location});
}

class UpdateVisitEvent extends HomeEvent {
  final VisitModel visit;
  UpdateVisitEvent(this.visit);
}

class CheckOutVisitEvent extends HomeEvent {
  final VisitModel visit;
  CheckOutVisitEvent(this.visit);
}

class FilterVisitsByClientEvent extends HomeEvent {
  final String? clientName;
  FilterVisitsByClientEvent(this.clientName);
}

class AddCommentEvent extends HomeEvent {
  final String visitId;
  final String text;
  final String targetUserId; // whose visit
  AddCommentEvent({
    required this.visitId,
    required this.text,
    required this.targetUserId,
  });
}

/// Triggered after each Firestore batch flush to OSRM-snap the new dirty points.
class SnapDirtyPointsEvent extends HomeEvent {}
