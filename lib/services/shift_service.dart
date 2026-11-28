import 'package:geolocator/geolocator.dart';
import '../core/utils/shift_check.dart';
import '../data/local/local_storage_service.dart';
import '../data/models/shift_model.dart';
import '../data/repositories/shift_repository.dart';
import '../features/home/bloc/home_state.dart';

/// Looks up the signed-in user's shift and their last known position, for the
/// punch-in / punch-out checks.
class ShiftService {
  /// The shift the signed-in user is on, or null (no org code, no shift, or the
  /// lookup failed: a failed lookup must never block a punch-in).
  static Future<ShiftModel?> myShift() async {
    try {
      final user = LocalStorageService.getUser();
      final code = user?.code;
      if (user == null || code == null || code.isEmpty) return null;
      return await ShiftRepository().getShiftForUser(code, user.id);
    } catch (_) {
      return null;
    }
  }

  /// The tracker's latest point if the session has one, otherwise the phone's
  /// cached position. Null if neither exists. Staleness is judged by the check
  /// itself (see Geofence.maxAge).
  static Future<KnownPosition?> lastKnown(HomeLoaded? state) async {
    final now = DateTime.now();
    final p = state?.lastKnownLocation;
    final at = state?.lastGpsUpdateTime;
    if (p != null && at != null) {
      return KnownPosition(
          lat: p.latitude, lng: p.longitude, age: now.difference(at));
    }
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        return KnownPosition(
          lat: pos.latitude,
          lng: pos.longitude,
          accuracyM: pos.accuracy,
          age: now.difference(pos.timestamp),
        );
      }
    } catch (_) {}
    return null;
  }
}
