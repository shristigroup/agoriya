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

/// The location-tracking background isolate is the sole writer of
/// currentBatch/finalLocations in Hive — this event is just a signal to
/// re-read them, optionally also triggering a batch sync.
class NewLocationPointEvent extends HomeEvent {
  final bool processBatch;
  NewLocationPointEvent({this.processBatch = false});
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
/// Re-reads currentBatch/finalLocations from Hive (the background isolate
/// may have written to them while the app was backgrounded) and, if the
/// backlog is already at/past the flush threshold — meaning a processBatch
/// signal was missed while the app was dead — triggers a sync immediately
/// rather than waiting for the next sample.
class AppResumedEvent extends HomeEvent {}
