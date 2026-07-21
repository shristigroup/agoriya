import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Cross-process/cross-isolate advisory lock guarding locationsBox +
/// settingsBox (the boxes involved in syncing finalLocations/
/// finalLocationsDistance). Hive itself has zero concurrency protection —
/// this is what makes it safe for the FCM watchdog handler (a short-lived,
/// separate isolate) to open those boxes without risking the corruption we
/// hit when the tracking isolate and main isolate both had a box open at
/// once.
///
/// Protocol: the main isolate acquires this lock ONCE at startup, before
/// opening locationsBox/settingsBox, and holds it for its entire process
/// lifetime — never explicitly released; the OS releases it automatically
/// when the process dies, for any reason. Any other isolate that wants to
/// touch those boxes must acquire the SAME lock first. If it can't within a
/// short timeout, that reliably means the main isolate is alive and holding
/// it, so the caller should skip its own access rather than risk opening
/// the same box concurrently.
class LocationsBoxLock {
  static Future<File> _lockFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/locations_box.lock');
    if (!await file.exists()) await file.create(recursive: true);
    return file;
  }

  /// Acquires the lock and never releases it — for the main isolate, at
  /// startup, before opening locationsBox/settingsBox. Waits as long as
  /// needed (blockingExclusive); callers should still bound this with a
  /// generous timeout so a stuck lock can never prevent the app from
  /// starting at all — see LocalStorageService.init.
  static Future<void> acquireForSession() async {
    final file = await _lockFile();
    final raf = await file.open(mode: FileMode.write);
    await raf.lock(FileLock.blockingExclusive);
    // Deliberately not stored/closed — held until process death.
  }

  /// Attempts to acquire the lock within [timeout]. Returns an open, locked
  /// [RandomAccessFile] on success (caller must unlock+close it when done),
  /// or null if it couldn't be acquired in time.
  static Future<RandomAccessFile?> tryAcquire({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final file = await _lockFile();
    final raf = await file.open(mode: FileMode.write);
    try {
      await raf.lock(FileLock.blockingExclusive).timeout(timeout);
      return raf;
    } catch (_) {
      await raf.close();
      return null;
    }
  }
}
