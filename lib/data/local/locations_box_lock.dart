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
/// Protocol: whoever wants locationsBox/settingsBox open must hold this
/// lock for as long as they're open, and release it as soon as they're
/// closed again — never open one without the other. The main isolate holds
/// it for its whole foreground session (acquired in LocalStorageService.init,
/// released/reacquired around app background/foreground via
/// closeLocationsBoxForBackground/reopenLocationsBoxForForeground), so the
/// FCM watchdog (and any future boot/update-triggered recovery) can safely
/// sync during exactly the window it's most likely to be needed — the app
/// backgrounded. [isHeldByThisIsolate] is the single source of truth for
/// "do I currently own these boxes" — see LocationSyncService.
/// processBatchAndEmitLatestLocationData, which checks it instead of
/// tracking a parallel "am I backgrounded" flag that could drift out of
/// sync with reality.
///
/// If the holder dies outright without going through a paired release
/// (crash, force-stop), the OS releases the underlying file lock
/// automatically when the process's file descriptors are torn down — a
/// safety net, not the primary release mechanism anymore.
class LocationsBoxLock {
  static RandomAccessFile? _heldLock;

  /// Whether this isolate currently holds the lock — via [acquireForSession]
  /// or a successful [tryAcquire]. The single source of truth callers should
  /// check before deciding whether they need to acquire it themselves.
  static bool get isHeldByThisIsolate => _heldLock != null;

  static Future<File> _lockFile() async {
    final dir = await getApplicationDocumentsDirectory();
    // NOT 'locations_box.lock': Hive keeps its own lock file for a box named
    // 'locations_box' at exactly that path and deletes it whenever the box is
    // closed, which removed this lock's file from under it and made later
    // closes fail with PathNotFoundException.
    final file = File('${dir.path}/locations_box_sync.lock');
    if (!await file.exists()) await file.create(recursive: true);
    return file;
  }

  /// Acquires the lock for as long as the caller keeps locationsBox/
  /// settingsBox open — at startup, and again on every app-foreground (see
  /// [releaseHeld]). Waits as long as needed (blockingExclusive); callers
  /// should still bound this with a generous timeout so a stuck lock can
  /// never prevent the app from starting/resuming at all — see
  /// LocalStorageService.init / reopenLocationsBoxForForeground. No-ops if
  /// already held (defensive against a double-acquire without an
  /// intervening release).
  static Future<void> acquireForSession() async {
    if (_heldLock != null) return;
    final file = await _lockFile();
    final raf = await file.open(mode: FileMode.write);
    await raf.lock(FileLock.blockingExclusive);
    _heldLock = raf;
  }

  /// Attempts to acquire the lock within [timeout], recording it as held by
  /// this isolate on success (so [releaseHeld] can release it later) — same
  /// bookkeeping [acquireForSession] uses, just non-blocking. Returns null
  /// if it couldn't be acquired in time (another isolate has it right now).
  /// No-ops (and returns immediately) if already held.
  static Future<bool> tryAcquire({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (_heldLock != null) return true;
    final file = await _lockFile();
    final raf = await file.open(mode: FileMode.write);
    try {
      await raf.lock(FileLock.blockingExclusive).timeout(timeout);
      _heldLock = raf;
      return true;
    } catch (_) {
      await raf.close();
      return false;
    }
  }

  /// Releases the lock acquired by [acquireForSession] or [tryAcquire] —
  /// call only AFTER locationsBox/settingsBox are already closed; the lock
  /// must stay held for as long as those boxes are open in this isolate's
  /// memory. No-ops if nothing is currently held.
  static Future<void> releaseHeld() async {
    final raf = _heldLock;
    _heldLock = null; // forget it first: a failure below must not leave us believing we still hold it
    if (raf == null) return;
    try {
      await raf.unlock();
    } catch (e) {
      print('[LocationsBoxLock] unlock failed (ignored): $e');
    }
    try {
      await raf.close();
    } catch (e) {
      print('[LocationsBoxLock] close failed (ignored): $e');
    }
  }
}