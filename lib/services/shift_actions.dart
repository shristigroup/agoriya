import 'package:flutter/foundation.dart';

/// A tapped shift reminder ("in" or "out") waiting for the home screen to start
/// the punch-in / punch-out flow. A notification tap can arrive before the home
/// screen has loaded, so the request is held here until it consumes it.
class ShiftActionBus {
  static final ValueNotifier<String?> pending = ValueNotifier<String?>(null);
}
