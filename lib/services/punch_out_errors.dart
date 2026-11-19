import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';

/// What the user sees when punching out can't complete. Kept separate from the
/// bloc so the wording and the error-to-message mapping can be tested.
class PunchOutMessages {
  const PunchOutMessages._();

  static const String offline =
      "You're offline. Connect to the internet and try again. "
      'You are still punched in.';

  static const String unreachable =
      "Couldn't reach the server. Check your internet connection and try "
      'again. You are still punched in.';

  static const String syncIncomplete =
      "Couldn't finish syncing your locations. Check your internet connection "
      'and try again. You are still punched in.';

  static const String generic =
      "Couldn't punch out. Please try again. You are still punched in.";

  /// Maps whatever a failed punch-out threw to a message for the user.
  static String forError(Object error) {
    if (error is PunchOutSyncIncomplete) return syncIncomplete;
    if (error is TimeoutException || error is SocketException) {
      return unreachable;
    }
    if (error is FirebaseException &&
        (error.code == 'unavailable' ||
            error.code == 'deadline-exceeded' ||
            error.code == 'network-request-failed')) {
      return unreachable;
    }
    return generic;
  }
}

/// Thrown when the sync that runs before punching out could not store every
/// pending location (typically the connection dropped part-way). The user is
/// still punched in and can retry; whatever was already written stays written.
class PunchOutSyncIncomplete implements Exception {
  const PunchOutSyncIncomplete();
  @override
  String toString() => 'PunchOutSyncIncomplete';
}
