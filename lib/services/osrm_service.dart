import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_constants.dart';

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

  /// OSRM did not answer at all (no network, timeout, or a server-side error),
  /// as opposed to answering "no": `NoMatch`, `NoSegment`, `TooBig` and the
  /// like are normal replies about the data, and retrying them never helps.
  bool get noAnswer =>
      reason == 'timeout' ||
      reason == 'error' ||
      reason.startsWith('http_429') ||
      reason.startsWith('http_5');

  /// Nothing matched: every input point is unmatched, no road paths.
  factory OsrmTrace.failed(String reason, int inputCount) =>
      OsrmTrace(const [], List<OsrmTracepoint?>.filled(inputCount, null), reason);
}

class OsrmService {
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
          '&timestamps=${stamps.join(';')}'
          '&radiuses=${List.filled(points.length, AppConstants.osrmRadiusMeters).join(';')}';
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
}
