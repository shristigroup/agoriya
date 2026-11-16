import 'dart:async';
import 'dart:io';

/// Answers "can this phone reach our backend right now?" before an action that
/// needs the server (punching out), so the user gets an immediate, clear
/// message instead of a spinner that never ends.
///
/// Firestore writes made while offline are queued by the SDK and their futures
/// only complete once the server acknowledges them, so without this (and the
/// timeouts on the writes themselves) an offline punch-out just hangs.
class NetworkCheck {
  const NetworkCheck._();

  /// The host looked up. Any Google API host works; this is the one the app
  /// actually writes to.
  static const String host = 'firestore.googleapis.com';

  /// Resolves [host] (twice at most, to ride out one flaky lookup). Returns
  /// false if it cannot be resolved within [timeout] each time.
  ///
  /// [lookup] exists so tests can stand in for the real DNS lookup.
  static Future<bool> isOnline({
    Duration timeout = const Duration(seconds: 4),
    Future<List<InternetAddress>> Function(String host)? lookup,
  }) async {
    final resolve = lookup ?? InternetAddress.lookup;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final result = await resolve(host).timeout(timeout);
        if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
          return true;
        }
      } on SocketException {
        // no route / no DNS: try once more
      } on TimeoutException {
        // lookup took too long: try once more
      }
    }
    return false;
  }
}
