import '../../../data/models/location_model.dart';
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

/// The location-tracking background isolate is the sole owner of the
/// tracking-cursor state (currentBatch/lastConfirmedPoint) — it pushes the
/// current values along with every sample so HomeBloc doesn't need a
/// round-trip request just to refresh the live map/UI. processBatch signals
/// that a full sync (OSRM + Firestore) is due.
class NewLocationPointEvent extends HomeEvent {
  final bool processBatch;
  final List<LocationPoint> currentBatch;
  final LocationPoint? lastConfirmedPoint;
  NewLocationPointEvent({
    this.processBatch = false,
    this.currentBatch = const [],
    this.lastConfirmedPoint,
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
/// Ensures the background isolate is running (restarting it if the OS
/// killed it) and requests its current cursor state; if the pending-sample
/// count is already at/past the flush threshold — meaning a processBatch
/// signal was missed while backgrounded — triggers a sync immediately
/// rather than waiting for the next sample.
class AppResumedEvent extends HomeEvent {}
