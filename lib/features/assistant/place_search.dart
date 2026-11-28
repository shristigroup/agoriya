import 'dart:convert';
import 'package:http/http.dart' as http;

class PlaceResult {
  final String name;
  final String address;
  final double lat;
  final double lng;
  const PlaceResult(
      {required this.name, required this.address, required this.lat, required this.lng});
}

/// Place search by name, with the free OpenStreetMap geocoder (Nominatim).
/// Its usage policy asks for an identifying User-Agent and at most one request
/// a second: fine for an owner now and then. Swap this class for a paid
/// geocoder if usage grows.
class PlaceSearch {
  final http.Client _client;
  PlaceSearch([http.Client? client]) : _client = client ?? http.Client();

  static const _userAgent = 'TrackFolks/3 (https://tf.shristigroup.com)';

  /// Up to 5 matches, nearer to [nearLat]/[nearLng] first when given.
  Future<List<PlaceResult>> search(String query,
      {double? nearLat, double? nearLng}) async {
    final params = <String, String>{
      'q': query,
      'format': 'jsonv2',
      'limit': '5',
      if (nearLat != null && nearLng != null)
        // left, top, right, bottom: a soft preference, not a limit.
        'viewbox':
            '${nearLng - 0.5},${nearLat + 0.5},${nearLng + 0.5},${nearLat - 0.5}',
    };
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);
    final response = await _client
        .get(uri, headers: {'User-Agent': _userAgent, 'Accept-Language': 'en'})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Place search failed (${response.statusCode})');
    }
    return parsePlaces(jsonDecode(response.body) as List);
  }

  static List<PlaceResult> parsePlaces(List raw) {
    final out = <PlaceResult>[];
    for (final r in raw) {
      if (r is! Map) continue;
      final lat = double.tryParse('${r['lat']}');
      final lng = double.tryParse('${r['lon']}');
      if (lat == null || lng == null) continue;
      final display = (r['display_name'] as String?) ?? '';
      final name = (r['name'] as String?)?.trim().isNotEmpty == true
          ? (r['name'] as String).trim()
          : display.split(',').first.trim();
      out.add(PlaceResult(name: name, address: display, lat: lat, lng: lng));
    }
    return out;
  }
}
