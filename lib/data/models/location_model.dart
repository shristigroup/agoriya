import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

class LocationPoint {
  final LatLng position;
  final DateTime timestamp;
  final bool isSnapped; // true = OSRM-snapped, false = raw GPS (dirty)

  const LocationPoint({
    required this.position,
    required this.timestamp,
    this.isSnapped = false,
  });

  factory LocationPoint.fromFirestore(Map<String, dynamic> map) {
    final gp = map['geoPoint'] as GeoPoint;
    return LocationPoint(
      position: LatLng(gp.latitude, gp.longitude),
      timestamp: (map['timestamp'] as Timestamp).toDate(),
      isSnapped: map['snapped'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'geoPoint': GeoPoint(position.latitude, position.longitude),
        'timestamp': Timestamp.fromDate(timestamp),
        'snapped': isSnapped,
      };

  factory LocationPoint.fromJson(Map<String, dynamic> json) => LocationPoint(
        position: LatLng(json['lat'], json['lng']),
        timestamp: DateTime.parse(json['timestamp']),
        isSnapped: json['snapped'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': timestamp.toIso8601String(),
        'snapped': isSnapped,
      };

  LocationPoint copyWith({LatLng? position, DateTime? timestamp, bool? isSnapped}) =>
      LocationPoint(
        position: position ?? this.position,
        timestamp: timestamp ?? this.timestamp,
        isSnapped: isSnapped ?? this.isSnapped,
      );
}

class DayLocations {
  final String date;
  final List<LocationPoint> points;

  const DayLocations({required this.date, required this.points});

  factory DayLocations.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final rawList = List<Map<String, dynamic>>.from(data['locations'] ?? []);
    return DayLocations(
      date: doc.id,
      points: rawList.map((e) => LocationPoint.fromFirestore(e)).toList(),
    );
  }

  factory DayLocations.fromJson(Map<String, dynamic> json) => DayLocations(
        date: json['date'] ?? '',
        points: (json['points'] as List<dynamic>? ?? [])
            .map((e) => LocationPoint.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'points': points.map((p) => p.toJson()).toList(),
      };
}
