import 'package:latlong2/latlong.dart';
import '../core/utils/app_utils.dart';
import '../data/models/location_model.dart';
import 'osrm_service.dart';

/// What a single OSRM request turns into.
class RouteChunk {
  /// The carried point with the road path that starts at it, if any — the
  /// caller replaces the already-stored copy with this one.
  final LocationPoint? carry;

  /// One stored point per input point (carry excluded), in order.
  final List<LocationPoint> stored;

  /// Distance covered by this chunk, including the leg from the carry.
  final double distanceKm;

  const RouteChunk(this.carry, this.stored, this.distanceKm);
}

/// Pure conversion of "points we sent + what OSRM answered" into "points to
/// store". One stored point per input point — real timestamp always; position
/// moved onto the road when OSRM matched it, left raw when it did not. OSRM's
/// road path goes on the point where each matching starts (see
/// LocationPoint.road).
class RouteBuilder {
  const RouteBuilder._();

  /// [carry] is the last already-stored point, sent as the request's first
  /// coordinate so the new road path starts exactly where the old one ended.
  /// [raw] are the new points. [trace] is OSRM's answer for `[carry, ...raw]`
  /// (or a failure, in which case everything stays raw).
  static RouteChunk build({
    LocationPoint? carry,
    required List<LocationPoint> raw,
    required OsrmTrace trace,
  }) {
    final offset = carry != null ? 1 : 0;
    final n = offset + raw.length;
    final tps = List<OsrmTracepoint?>.generate(
        n, (i) => i < trace.tracepoints.length ? trace.tracepoints[i] : null);

    // Stored points: snapped position when matched, raw otherwise.
    var stored = <LocationPoint>[
      for (var k = 0; k < raw.length; k++)
        raw[k].copyWithPosition(
          position: tps[offset + k]?.location,
          isSnapped: tps[offset + k] != null,
        ),
    ];

    // Where each point sits for distance purposes (carry as already stored).
    LatLng posOf(int idx) =>
        idx < offset ? carry!.position : stored[idx - offset].position;
    int tsOf(int idx) =>
        (idx < offset ? carry!.timestamp : stored[idx - offset].timestamp)
            .millisecondsSinceEpoch;

    // Road path on the first point of each matching that has 2+ points.
    LocationPoint? updatedCarry;
    for (var m = 0; m < trace.matchings.length; m++) {
      int? first, last;
      for (var k = 0; k < n; k++) {
        if (tps[k]?.matchingIndex == m) {
          first ??= k;
          last = k;
        }
      }
      if (first == null || last == null || last == first) continue;
      final polyline = trace.matchings[m].polyline;
      final endMs = tsOf(last);
      if (first < offset) {
        // Never overwrite a path the carried point already starts.
        if (carry!.road == null) {
          updatedCarry = carry.copyWith(road: polyline, roadEndMs: endMs);
        }
      } else {
        final i = first - offset;
        stored[i] = stored[i].copyWith(road: polyline, roadEndMs: endMs);
      }
    }

    // Distance: OSRM's own leg distances between consecutive matched
    // waypoints of a matching; straight lines through everything else
    // (unmatched points, gaps between matchings, a failed request).
    double meters = 0;
    LatLng? prevPos;
    int? prevMatching, prevWaypoint;
    final pending = <LatLng>[];

    double straight(List<LatLng> pts) {
      var d = 0.0;
      for (var i = 0; i < pts.length - 1; i++) {
        d += AppUtils.haversineMeters(pts[i], pts[i + 1]);
      }
      return d;
    }

    for (var k = 0; k < n; k++) {
      final tp = tps[k];
      final pos = posOf(k);
      if (tp == null) {
        pending.add(pos);
        continue;
      }
      final m = tp.matchingIndex;
      final consecutive = prevMatching == m &&
          prevWaypoint != null &&
          tp.waypointIndex == prevWaypoint + 1 &&
          prevWaypoint < trace.matchings[m].legDistancesM.length;
      if (consecutive) {
        // Unmatched points between two waypoints of one matching lie inside
        // the route OSRM already measured.
        meters += trace.matchings[m].legDistancesM[prevWaypoint];
      } else {
        meters += straight([if (prevPos != null) prevPos, ...pending, pos]);
      }
      pending.clear();
      prevPos = pos;
      prevMatching = m;
      prevWaypoint = tp.waypointIndex;
    }
    if (pending.isNotEmpty) {
      meters += straight([if (prevPos != null) prevPos, ...pending]);
    }

    return RouteChunk(updatedCarry, stored, meters / 1000.0);
  }
}
