import 'package:latlong2/latlong.dart';

/// Google's encoded-polyline format, which OSRM returns for `geometries=polyline`
/// (precision 5, about 1 m). A route of a few dozen vertices is a few hundred
/// bytes — far smaller than the same vertices as stored point objects.
class PolylineCodec {
  const PolylineCodec._();

  static List<LatLng> decode(String encoded, {int precision = 5}) {
    final factor = _pow10(precision);
    final out = <LatLng>[];
    var i = 0, lat = 0, lng = 0;
    while (i < encoded.length) {
      for (var axis = 0; axis < 2; axis++) {
        var shift = 0, result = 0, b;
        do {
          b = encoded.codeUnitAt(i++) - 63;
          result |= (b & 0x1f) << shift;
          shift += 5;
        } while (b >= 0x20);
        final delta = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
        if (axis == 0) {
          lat += delta;
        } else {
          lng += delta;
        }
      }
      out.add(LatLng(lat / factor, lng / factor));
    }
    return out;
  }

  static String encode(List<LatLng> points, {int precision = 5}) {
    final factor = _pow10(precision);
    final sb = StringBuffer();
    var prevLat = 0, prevLng = 0;
    for (final p in points) {
      final lat = (p.latitude * factor).round();
      final lng = (p.longitude * factor).round();
      _write(sb, lat - prevLat);
      _write(sb, lng - prevLng);
      prevLat = lat;
      prevLng = lng;
    }
    return sb.toString();
  }

  static void _write(StringBuffer sb, int value) {
    var v = value < 0 ? ~(value << 1) : (value << 1);
    while (v >= 0x20) {
      sb.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    sb.writeCharCode(v + 63);
  }

  static int _pow10(int n) {
    var r = 1;
    for (var i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }
}
