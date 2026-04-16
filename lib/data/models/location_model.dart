import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

class LocationPoint {
  final LatLng position;
  final DateTime timestamp;
  final bool isSnapped;

  /// Set only on the last point of each snapped batch written to Firestore.
  /// Equals the running total (finalLocationsDistance) at the moment that
  /// batch was committed — useful for debugging without reading the attendance doc.
  final double? cumulativeDistanceKm;

  /// Set only on the last point of each snapped batch written to Firestore.
  /// Equals the OSRM distance for just this batch (not the running total).
  final double? batchDistanceKm;

  /// Seconds the user was stationary at this location during the current batch
  /// window. null / 0 means the user was moving when this point was recorded.
  /// Updated in-memory as long as the user stays within 50 m; written to
  /// Firestore at batch-flush time.
  final int? durationSeconds;

  const LocationPoint({
    required this.position,
    required this.timestamp,
    this.isSnapped = false,
    this.cumulativeDistanceKm,
    this.batchDistanceKm,
    this.durationSeconds,
  });

  factory LocationPoint.fromFirestore(Map<String, dynamic> map) {
    final gp = map['geoPoint'] as GeoPoint;
    return LocationPoint(
      position: LatLng(gp.latitude, gp.longitude),
      timestamp: (map['timestamp'] as Timestamp).toDate(),
      isSnapped: map['snapped'] as bool? ?? false,
      cumulativeDistanceKm:
          (map['cumulativeDistanceKm'] as num?)?.toDouble(),
      batchDistanceKm: (map['batchDistanceKm'] as num?)?.toDouble(),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toFirestore() {
    final m = <String, dynamic>{
      'geoPoint': GeoPoint(position.latitude, position.longitude),
      'timestamp': Timestamp.fromDate(timestamp),
      'snapped': isSnapped,
    };
    if (cumulativeDistanceKm != null) m['cumulativeDistanceKm'] = cumulativeDistanceKm;
    if (batchDistanceKm != null) m['batchDistanceKm'] = batchDistanceKm;
    if (durationSeconds != null && durationSeconds! > 0) m['durationSeconds'] = durationSeconds;
    return m;
  }

  factory LocationPoint.fromJson(Map<String, dynamic> json) => LocationPoint(
        position: LatLng(
            (json['lat'] as num).toDouble(), (json['lng'] as num).toDouble()),
        timestamp: DateTime.parse(json['timestamp'] as String),
        isSnapped: json['snapped'] as bool? ?? false,
        cumulativeDistanceKm:
            (json['cumulativeDistanceKm'] as num?)?.toDouble(),
        batchDistanceKm: (json['batchDistanceKm'] as num?)?.toDouble(),
        durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'lat': position.latitude,
      'lng': position.longitude,
      'timestamp': timestamp.toIso8601String(),
      'snapped': isSnapped,
    };
    if (cumulativeDistanceKm != null) m['cumulativeDistanceKm'] = cumulativeDistanceKm;
    if (batchDistanceKm != null) m['batchDistanceKm'] = batchDistanceKm;
    if (durationSeconds != null && durationSeconds! > 0) m['durationSeconds'] = durationSeconds;
    return m;
  }

  LocationPoint copyWith({
    LatLng? position,
    DateTime? timestamp,
    bool? isSnapped,
    double? cumulativeDistanceKm,
    double? batchDistanceKm,
    int? durationSeconds,
  }) =>
      LocationPoint(
        position: position ?? this.position,
        timestamp: timestamp ?? this.timestamp,
        isSnapped: isSnapped ?? this.isSnapped,
        cumulativeDistanceKm: cumulativeDistanceKm ?? this.cumulativeDistanceKm,
        batchDistanceKm: batchDistanceKm ?? this.batchDistanceKm,
        durationSeconds: durationSeconds ?? this.durationSeconds,
      );
}

class DayLocations {
  final String date;
  final List<LocationPoint> points;

  const DayLocations({required this.date, required this.points});

  factory DayLocations.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final rawList =
        List<Map<String, dynamic>>.from(data['locations'] ?? []);
    final points = rawList
        .map((e) => LocationPoint.fromFirestore(e))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return DayLocations(date: doc.id, points: points);
  }

  factory DayLocations.fromJson(Map<String, dynamic> json) => DayLocations(
        date: json['date'] ?? '',
        points: (json['points'] as List<dynamic>? ?? [])
            .map((e) =>
                LocationPoint.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'points': points.map((p) => p.toJson()).toList(),
      };
}
