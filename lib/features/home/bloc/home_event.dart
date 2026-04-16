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
  final bool processBatch;
  NewLocationPointEvent({
    required this.lat,
    required this.lng,
    required this.timestamp,
    this.processBatch = false,
  });
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

class AddCommentEvent extends HomeEvent {
  final String visitId;
  final String text;
  final String targetUserId;
  AddCommentEvent({
    required this.visitId,
    required this.text,
    required this.targetUserId,
  });
}

/// Undo an accidental punch-out for today — clears punchOutTimestamp and
/// restarts location tracking. The Firestore write triggers the Cloud Function
/// to notify the manager.
class ResumeSessionEvent extends HomeEvent {}

/// Fired when the app returns to the foreground (AppLifecycleState.resumed).
/// If a session is active and currentBatch is non-empty, snaps the raw batch
/// to roads for display and writes the snapped result to Hive — so the map
/// shows a clean route immediately without waiting for the next batchFlushed.
/// Does NOT write to Firestore; that still happens on batchFlushed.
class AppResumedEvent extends HomeEvent {}
