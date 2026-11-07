import 'package:latlong2/latlong.dart';
import '../../data/models/location_model.dart';
import 'polyline_codec.dart';

/// Turns stored points into the line to draw: OSRM's road path wherever a
/// point carries one, straight lines between points everywhere else (stretches
/// OSRM couldn't match, today's not-yet-synced points, and sessions stored
/// before road paths existed — those have no `road` fields, so they draw
/// exactly as they always did).
class RoutePath {
  const RoutePath._();

  /// [points] must be in time order.
  static List<LatLng> build(List<LocationPoint> points) {
    final path = <LatLng>[];
    var i = 0;
    while (i < points.length) {
      final p = points[i];
      path.add(p.position);

      final road = p.road;
      final endMs = p.roadEndMs;
      if (road != null && endMs != null) {
        // The end point may not exist any more (e.g. a partial list); then
        // fall back to straight lines from here.
        var j = i + 1;
        while (j < points.length &&
            points[j].timestamp.millisecondsSinceEpoch != endMs) {
          j++;
        }
        if (j < points.length) {
          path.addAll(PolylineCodec.decode(road));
          // The points strictly between i and j lie on the road path; the end
          // point is added by the next iteration.
          i = j;
          continue;
        }
      }
      i++;
    }
    return path;
  }
}
