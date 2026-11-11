import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_constants.dart';

/// Result of [OsrmService.matchSimplifiedGeometry]: the road geometry (null if
/// OSRM couldn't help) and a short reason code for diagnostics.
class OsrmMatch {
  final List<LatLng>? geometry;
  final String reason;
  const OsrmMatch(this.geometry, this.reason);
}

/// One OSRM matching: a connected stretch of the trace that was matched to
/// roads. OSRM may split a trace into several (a gap it can't bridge).
class OsrmMatching {
  /// Road path as an encoded polyline (precision 5).
  final String polyline;
  final double distanceM;
  final double confidence;

  /// Road distance of each consecutive pair of this matching's waypoints.
  final List<double> legDistancesM;

  const OsrmMatching(
      this.polyline, this.distanceM, this.confidence, this.legDistancesM);
}

/// Where OSRM placed one input point.
class OsrmTracepoint {
  final LatLng location;
  final int matchingIndex;

  /// Position of this point among its matching's waypoints.
  final int waypointIndex;

  const OsrmTracepoint(this.location, this.matchingIndex, this.waypointIndex);
}

/// Result of [OsrmService.matchTrace]. [tracepoints] has one entry per input
/// point, in order; null means OSRM could not use that point (no road close
/// enough, or no believable route to its neighbours) and skipped it — NOT that
/// it judged the fix a stray.
class OsrmTrace {
  final List<OsrmMatching> matchings;
  final List<OsrmTracepoint?> tracepoints;

  /// `ok`, `batch_too_small`, `no_match`, `timeout`, `error`, or
  /// `http_<status>[:<OSRM code>]` such as `http_400:NoMatch` / `http_400:TooBig`.
  final String reason;

  const OsrmTrace(this.matchings, this.tracepoints, this.reason);

  bool get ok => reason == 'ok';

  /// Nothing matched: every input point is unmatched, no road paths.
  factory OsrmTrace.failed(String reason, int inputCount) =>
      OsrmTrace(const [], List<OsrmTracepoint?>.filled(inputCount, null), reason);
}

class OsrmService {
  /// Snaps a list of GPS points to nearest roads using OSRM Match API.
  /// Falls back to original points on any error.
  static Future<List<LatLng>> snapToRoads(List<LatLng> points) async {
    if (points.length < 2) return points;

    final chunks = _chunkList(points, 100);
    final snapped = <LatLng>[];

    for (final chunk in chunks) {
      try {
        final coords =
            chunk.map((p) => '${p.longitude},${p.latitude}').join(';');
        final url =
            '${AppConstants.osrmMatchUrl}/$coords'
            '?overview=full&geometries=geojson&annotations=false';
        final response =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data['code'] == 'Ok' && data['matchings'] != null) {
            for (final matching in data['matchings'] as List) {
              final coords =
                  (matching['geometry']['coordinates'] as List);
              snapped.addAll(
                coords.map((c) => LatLng(
                      (c[1] as num).toDouble(),
                      (c[0] as num).toDouble(),
                    )),
              );
            }
            continue;
          }
        }
        snapped.addAll(chunk);
      } catch (_) {
        snapped.addAll(chunk);
      }
    }

    return snapped;
  }

  /// Calculate road distance between ordered points using OSRM Route API.
  /// Returns distance in km. Falls back to haversine on error.
  static Future<double> calculateRouteDistance(List<LatLng> points) async {
    if (points.length < 2) return 0.0;

    final chunks = _chunkList(points, 100);
    double totalKm = 0.0;

    for (int i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final segment =
          i > 0 ? [chunks[i - 1].last, ...chunk] : chunk;
      if (segment.length < 2) continue;

      try {
        final coords =
            segment.map((p) => '${p.longitude},${p.latitude}').join(';');
        final url =
            '${AppConstants.osrmRouteUrl}/$coords'
            '?overview=false&annotations=false';
        final response =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data['code'] == 'Ok' && data['routes'] != null) {
            final distMeters =
                (data['routes'][0]['distance'] as num).toDouble();
            totalKm += distMeters / 1000.0;
            continue;
          }
        }
        totalKm += _haversineDistance(segment);
      } catch (_) {
        totalKm += _haversineDistance(segment);
      }
    }

    return totalKm;
  }

  static double _haversineDistance(List<LatLng> points) {
    const earthRadius = 6371.0;
    double total = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final dLat = _toRad(p2.latitude - p1.latitude);
      final dLng = _toRad(p2.longitude - p1.longitude);
      final a = math.pow(math.sin(dLat / 2), 2) +
          math.cos(_toRad(p1.latitude)) *
              math.cos(_toRad(p2.latitude)) *
              math.pow(math.sin(dLng / 2), 2);
      final c = 2 * math.asin(math.sqrt(a));
      total += earthRadius * c;
    }
    return total;
  }

  /// Map-matches [points] (a raw GPS trace) to roads and returns a
  /// SIMPLIFIED geometry — Douglas-Peucker reduced by OSRM itself
  /// (`overview=simplified`), the same concept as Google Directions'
  /// `overview_polyline`: far fewer points than the raw trace or a
  /// `overview=full` request, while still visually following the road.
  /// `tidy=true` lets OSRM clean a noisy trace first (it drops points it
  /// considers duplicates/outliers instead of routing through them).
  /// Concatenates all returned matchings in trace order (OSRM can split a
  /// low-confidence trace into multiple matchings).
  ///
  /// Never throws. [OsrmMatch.geometry] is null when OSRM couldn't help —
  /// callers should fall back to the original points — and
  /// [OsrmMatch.reason] says why, for diagnostics.
  static Future<OsrmMatch> matchSimplifiedGeometry(List<LatLng> points) async {
    if (points.length < 2) {
      return const OsrmMatch(null, 'batch_too_small');
    }

    try {
      final coords = points.map((p) => '${p.longitude},${p.latitude}').join(';');
      final url = '${AppConstants.osrmMatchUrl}/$coords'
          '?overview=simplified&geometries=geojson&annotations=false&tidy=true';
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        print('[OSRM] matchSimplifiedGeometry HTTP ${response.statusCode} → '
            'falling back to raw points');
        return OsrmMatch(null, 'http_${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok' || data['matchings'] == null) {
        print('[OSRM] matchSimplifiedGeometry non-OK response | '
            'code=${data['code']} → falling back to raw points');
        return const OsrmMatch(null, 'no_match');
      }

      final result = <LatLng>[];
      for (final matching in data['matchings'] as List) {
        final coords = matching['geometry']['coordinates'] as List;
        result.addAll(coords.map((c) => LatLng(
              (c[1] as num).toDouble(),
              (c[0] as num).toDouble(),
            )));
      }
      if (result.isEmpty) return const OsrmMatch(null, 'no_match');

      print('[OSRM] matchSimplifiedGeometry OK | ${points.length} raw '
          'points → ${result.length} simplified points');
      return OsrmMatch(result, 'ok');
    } on TimeoutException {
      print('[OSRM] matchSimplifiedGeometry timeout → falling back to raw points');
      return const OsrmMatch(null, 'timeout');
    } catch (e) {
      print('[OSRM] matchSimplifiedGeometry error: $e → falling back to raw points');
      return const OsrmMatch(null, 'error');
    }
  }

  /// Map-matches a time-stamped trace and returns where each point landed plus
  /// the road path (as encoded polylines, one per matching).
  ///
  /// Timestamps are sent so OSRM can reject physically impossible hops; they
  /// must be strictly increasing, so equal ones are nudged forward a second in
  /// the REQUEST only. At most [AppConstants.osrmMaxCoordinates] points —
  /// callers split longer traces. Never throws; on any failure the result is
  /// [OsrmTrace.failed] with the reason, including OSRM's own error code.
  static Future<OsrmTrace> matchTrace(
      List<LatLng> points, List<DateTime> times) async {
    assert(points.length == times.length);
    if (points.length < 2) return OsrmTrace.failed('batch_too_small', points.length);
    if (points.length > AppConstants.osrmMaxCoordinates) {
      return OsrmTrace.failed('too_many_points', points.length);
    }

    try {
      final coords = points.map((p) => '${p.longitude},${p.latitude}').join(';');
      var prev = -1;
      final stamps = <int>[];
      for (final t in times) {
        var s = t.millisecondsSinceEpoch ~/ 1000;
        if (s <= prev) s = prev + 1;
        stamps.add(s);
        prev = s;
      }
      final url = '${AppConstants.osrmMatchUrl}/$coords'
          '?overview=simplified&geometries=polyline&annotations=false&tidy=true'
          '&timestamps=${stamps.join(';')}';
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      final trace = parseTraceResponse(
          response.statusCode, response.body, points.length);
      if (!trace.ok) {
        print('[OSRM] matchTrace ${trace.reason} → keeping raw points');
      }
      return trace;
    } on TimeoutException {
      print('[OSRM] matchTrace timeout → keeping raw points');
      return OsrmTrace.failed('timeout', points.length);
    } catch (e) {
      print('[OSRM] matchTrace error: $e → keeping raw points');
      return OsrmTrace.failed('error', points.length);
    }
  }

  /// Pure parsing of an OSRM /match response (kept separate from the network
  /// call so it can be unit-tested with recorded responses).
  static OsrmTrace parseTraceResponse(int status, String body, int inputCount) {
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {}

    if (status != 200) {
      final code = data?['code'];
      return OsrmTrace.failed(
          code is String ? 'http_$status:$code' : 'http_$status', inputCount);
    }
    if (data == null || data['code'] != 'Ok' || data['matchings'] == null) {
      return OsrmTrace.failed('no_match', inputCount);
    }

    final matchings = <OsrmMatching>[];
    for (final m in data['matchings'] as List) {
      final legs = (m['legs'] as List? ?? const [])
          .map((l) => (l['distance'] as num).toDouble())
          .toList();
      matchings.add(OsrmMatching(
        m['geometry'] as String,
        (m['distance'] as num).toDouble(),
        (m['confidence'] as num?)?.toDouble() ?? 0.0,
        legs,
      ));
    }
    if (matchings.isEmpty) return OsrmTrace.failed('no_match', inputCount);

    final tracepoints = <OsrmTracepoint?>[];
    for (final tp in (data['tracepoints'] as List? ?? const [])) {
      if (tp == null) {
        tracepoints.add(null);
        continue;
      }
      final loc = tp['location'] as List;
      tracepoints.add(OsrmTracepoint(
        LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
        (tp['matchings_index'] as num).toInt(),
        (tp['waypoint_index'] as num).toInt(),
      ));
    }
    // Defensive: always one entry per input point.
    while (tracepoints.length < inputCount) {
      tracepoints.add(null);
    }
    return OsrmTrace(matchings, tracepoints, 'ok');
  }

  static double _toRad(double deg) => deg * math.pi / 180;

  static List<List<T>> _chunkList<T>(List<T> list, int size) {
    final chunks = <List<T>>[];
    for (int i = 0; i < list.length; i += size) {
      final end = (i + size > list.length) ? list.length : i + size;
      chunks.add(list.sublist(i, end));
    }
    return chunks;
  }
}
