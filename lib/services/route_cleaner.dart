import 'dart:math' as math;
import '../core/utils/app_utils.dart';
import '../data/models/location_model.dart';

/// Decides which unmatched points of a sync unit are stray GPS fixes.
///
/// Runs AFTER OSRM, on the points OSRM could not place on a road (matched
/// points are trusted and never removed). Nothing here is a speed limit: the
/// limit is the "fence" of the session's own leg speeds, Q3 + 1.5 × (Q3 − Q1),
/// where Q1/Q3 are the speeds a quarter / three quarters of the legs are below.
///
/// One round: for every candidate B (unmatched, with a neighbour on each side)
/// compare the path THROUGH B with the path skipping it —
///   excessBefore = excess(A→B) + excess(B→C)
///   gain         = excessBefore − excess(A→C)
/// where excess(speed) is how far the speed is over the fence. B qualifies only
/// if skipping it removes at least [guardShare] of the excess (the "guard": a
/// real stray removes ~all of it; a one-sided jump such as a stale position
/// followed by a real fix removes little, and must not start a cascade). The
/// best qualifying point is dropped, speeds and fence are recomputed, repeat.
///
/// Edges: the point in front of the unit (the "carry", already saved) is judged
/// too when it is itself unmatched — the point before it then serves as the
/// fixed anchor. The unit's right-hand neighbour is a neighbour only.
class RouteCleaner {
  const RouteCleaner._();

  /// Standard outlier fence multiplier.
  static const double fenceMultiplier = 1.5;

  /// A removal must eliminate at least this share of the speed excess.
  static const double guardShare = 0.5;

  /// A point with a stay (a real place) is only removable when its worst leg is
  /// more than this many times the fence.
  static const double stayFenceFactor = 2.0;

  /// Fewer legs than this and there is too little evidence to judge anything.
  static const int minLegs = 8;

  /// How many recent saved points give the fence its history.
  static const int historyPoints = 50;

  /// Returns the timestamps (ms since epoch) of the points to drop.
  ///
  /// [history]: everything already saved, oldest first (dropped points are
  /// ignored). [unit]: the new points with OSRM's answer applied (`isSnapped`).
  /// [next]: the right-hand neighbour — the next pending point — or null.
  static Set<int> clean({
    required List<LocationPoint> history,
    required List<LocationPoint> unit,
    LocationPoint? next,
  }) {
    final saved = history.visible;
    final tail = saved.length > historyPoints
        ? saved.sublist(saved.length - historyPoints)
        : saved;

    final carry = tail.isNotEmpty ? tail.last : null;
    final p8 = (carry != null && !carry.isSnapped && tail.length >= 2)
        ? tail[tail.length - 2]
        : null;

    final chain = <LocationPoint>[...tail, ...unit, if (next != null) next];
    // First index that may be judged: the carry when it has a point before it
    // and is unmatched, otherwise the first point of the unit. Index 0 never
    // has a left neighbour.
    var from = p8 != null ? tail.length - 1 : tail.length;
    if (from < 1) from = 1;

    final dropped = <int>{};
    while (true) {
      final n = chain.length;
      final speeds = <double?>[null];
      for (var j = 1; j < n; j++) {
        speeds.add(_speed(chain[j - 1], chain[j]));
      }
      final sorted = speeds.whereType<double>().toList()..sort();
      if (sorted.length < minLegs) break;
      final q1 = _quantile(sorted, 0.25);
      final q3 = _quantile(sorted, 0.75);
      final fence = q3 + fenceMultiplier * (q3 - q1);
      double excess(double? s) => s == null ? 0 : math.max(0, s - fence);

      var best = -1;
      var bestGain = 1e-9;
      for (var j = from; j <= n - 2; j++) {
        final b = chain[j];
        if (b.isSnapped) continue;
        final before = excess(speeds[j]) + excess(speeds[j + 1]);
        if (before <= 0) continue;
        final gain = before - excess(_speed(chain[j - 1], chain[j + 1]));
        if (gain < guardShare * before || gain <= bestGain) continue;
        if ((b.durationSeconds ?? 0) > 0) {
          final worst = math.max(speeds[j] ?? 0, speeds[j + 1] ?? 0);
          if (worst <= stayFenceFactor * fence) continue;
        }
        best = j;
        bestGain = gain;
      }
      if (best < 0) break;
      dropped.add(chain[best].timestamp.millisecondsSinceEpoch);
      chain.removeAt(best);
    }
    return dropped;
  }

  /// km/h from when the user LEFT [a] (its timestamp plus its stay) to when
  /// they reached [b]. Falls back to the plain timestamp difference when the
  /// stay runs right up to [b]; null when no time at all separates them.
  static double? _speed(LocationPoint a, LocationPoint b) {
    final meters = AppUtils.haversineMeters(a.position, b.position);
    final departure = a.timestamp.add(Duration(seconds: a.durationSeconds ?? 0));
    var seconds = b.timestamp.difference(departure).inMilliseconds / 1000.0;
    if (seconds < 1) {
      seconds = b.timestamp.difference(a.timestamp).inMilliseconds / 1000.0;
    }
    if (seconds < 1) return null;
    return meters / seconds * 3.6;
  }

  /// Linear-interpolated quantile of an ascending list.
  static double _quantile(List<double> sorted, double q) {
    final pos = (sorted.length - 1) * q;
    final lo = pos.floor();
    final hi = pos.ceil();
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
  }
}
