import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_constants.dart';

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

  /// Snaps each input point to its nearest road position using OSRM tracepoints.
  /// Returns a list of the same length — null at an index means OSRM could not
  /// match that point; callers should fall back to the original position.
  static Future<List<LatLng?>> snapTracepoints(List<LatLng> points) async {
    if (points.length < 2) return points.map<LatLng?>((p) => p).toList();

    try {
      final coords = points.map((p) => '${p.longitude},${p.latitude}').join(';');
      final url = '${AppConstants.osrmMatchUrl}/$coords'
          '?overview=false&annotations=false';
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['code'] == 'Ok' && data['tracepoints'] != null) {
          return (data['tracepoints'] as List).map<LatLng?>((tp) {
            if (tp == null) return null;
            final loc = tp['location'] as List;
            return LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble());
          }).toList();
        }
      }
    } catch (_) {}

    // Fall back to original points on any error
    return points.map<LatLng?>((p) => p).toList();
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
