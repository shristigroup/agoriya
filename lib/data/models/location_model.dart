import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

class LocationPoint {
  final LatLng position;
  final DateTime timestamp;

  const LocationPoint({required this.position, required this.timestamp});

  factory LocationPoint.fromFirestore(Map<String, dynamic> map) {
    final gp = map['geoPoint'] as GeoPoint;
    return LocationPoint(
      position: LatLng(gp.latitude, gp.longitude),
      timestamp: (map['timestamp'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'geoPoint': GeoPoint(position.latitude, position.longitude),
        'timestamp': Timestamp.fromDate(timestamp),
      };

  factory LocationPoint.fromJson(Map<String, dynamic> json) => LocationPoint(
        position: LatLng(json['lat'], json['lng']),
        timestamp: DateTime.parse(json['timestamp']),
      );

  Map<String, dynamic> toJson() => {
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': timestamp.toIso8601String(),
      };
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
