import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

class AttendanceModel {
  final String date; // yyyy-MM-dd (doc ID)
  final DateTime? punchInTimestamp;
  final DateTime? punchOutTimestamp;
  final String? punchInImage; // Storage URL
  final double distance; // km
  final LatLng? punchOutLocation;
  final int customerVisitCount;

  const AttendanceModel({
    required this.date,
    this.punchInTimestamp,
    this.punchOutTimestamp,
    this.punchInImage,
    this.distance = 0.0,
    this.punchOutLocation,
    this.customerVisitCount = 0,
  });

  bool get isPunchedIn => punchInTimestamp != null;
  bool get isPunchedOut => punchOutTimestamp != null;

  Duration get attendanceDuration {
    if (punchInTimestamp == null) return Duration.zero;
    final end = punchOutTimestamp ?? DateTime.now();
    return end.difference(punchInTimestamp!);
  }

  factory AttendanceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    LatLng? loc;
    if (data['punchOutLocation'] != null) {
      final gp = data['punchOutLocation'] as GeoPoint;
      loc = LatLng(gp.latitude, gp.longitude);
    }
    return AttendanceModel(
      date: doc.id,
      punchInTimestamp: (data['punchInTimestamp'] as Timestamp?)?.toDate(),
      punchOutTimestamp: (data['punchOutTimestamp'] as Timestamp?)?.toDate(),
      punchInImage: data['punchInImage'],
      distance: (data['distance'] ?? 0.0).toDouble(),
      punchOutLocation: loc,
      customerVisitCount: data['customerVisitCount'] ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'distance': distance,
      'customerVisitCount': customerVisitCount,
    };
    if (punchInTimestamp != null) {
      map['punchInTimestamp'] = Timestamp.fromDate(punchInTimestamp!);
    }
    if (punchOutTimestamp != null) {
      map['punchOutTimestamp'] = Timestamp.fromDate(punchOutTimestamp!);
    }
    if (punchInImage != null) map['punchInImage'] = punchInImage;
    if (punchOutLocation != null) {
      map['punchOutLocation'] =
          GeoPoint(punchOutLocation!.latitude, punchOutLocation!.longitude);
    }
    return map;
  }

  factory AttendanceModel.fromJson(Map<String, dynamic> json) {
    LatLng? loc;
    if (json['punchOutLocation'] != null) {
      loc = LatLng(
        json['punchOutLocation']['lat'],
        json['punchOutLocation']['lng'],
      );
    }
    return AttendanceModel(
      date: json['date'] ?? '',
      punchInTimestamp: json['punchInTimestamp'] != null
          ? DateTime.parse(json['punchInTimestamp'])
          : null,
      punchOutTimestamp: json['punchOutTimestamp'] != null
          ? DateTime.parse(json['punchOutTimestamp'])
          : null,
      punchInImage: json['punchInImage'],
      distance: (json['distance'] ?? 0.0).toDouble(),
      punchOutLocation: loc,
      customerVisitCount: json['customerVisitCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'punchInTimestamp': punchInTimestamp?.toIso8601String(),
        'punchOutTimestamp': punchOutTimestamp?.toIso8601String(),
        'punchInImage': punchInImage,
        'distance': distance,
        'punchOutLocation': punchOutLocation == null
            ? null
            : {'lat': punchOutLocation!.latitude, 'lng': punchOutLocation!.longitude},
        'customerVisitCount': customerVisitCount,
      };

  AttendanceModel copyWith({
    String? date,
    DateTime? punchInTimestamp,
    DateTime? punchOutTimestamp,
    String? punchInImage,
    double? distance,
    LatLng? punchOutLocation,
    int? customerVisitCount,
  }) =>
      AttendanceModel(
        date: date ?? this.date,
        punchInTimestamp: punchInTimestamp ?? this.punchInTimestamp,
        punchOutTimestamp: punchOutTimestamp ?? this.punchOutTimestamp,
        punchInImage: punchInImage ?? this.punchInImage,
        distance: distance ?? this.distance,
        punchOutLocation: punchOutLocation ?? this.punchOutLocation,
        customerVisitCount: customerVisitCount ?? this.customerVisitCount,
      );
}
