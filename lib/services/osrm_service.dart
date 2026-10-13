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
