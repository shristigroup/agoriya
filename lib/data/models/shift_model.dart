import 'package:cloud_firestore/cloud_firestore.dart';

/// A place for punch-in or punch-out, picked by the owner (name + address from
/// a place search, plus the coordinates).
class ShiftLocation {
  final double lat;
  final double lng;
  final String name;
  final String? address;

  const ShiftLocation({
    required this.lat,
    required this.lng,
    required this.name,
    this.address,
  });

  factory ShiftLocation.fromMap(Map<String, dynamic> m) => ShiftLocation(
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        name: m['name'] as String? ?? '',
        address: m['address'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'lat': lat,
        'lng': lng,
        'name': name,
        if (address != null) 'address': address,
      };
}

/// A shift: Codes/{code}/Shifts/{id}. Times are minutes after midnight, India
/// time. A shift may have times, a location, or both. [outLocation] null means
/// "same place as punch-in".
class ShiftModel {
  static const int defaultRadiusM = 100;

  final String id;
  final String name;
  final int? startMinute;
  final int? endMinute;
  final bool endNextDay;
  final ShiftLocation? inLocation;
  final ShiftLocation? outLocation;
  final int radiusM;
  final List<String> userIds;

  const ShiftModel({
    required this.id,
    required this.name,
    this.startMinute,
    this.endMinute,
    this.endNextDay = false,
    this.inLocation,
    this.outLocation,
    this.radiusM = defaultRadiusM,
    this.userIds = const [],
  });

  ShiftLocation? get effectiveOutLocation => outLocation ?? inLocation;
  bool get hasTimes => startMinute != null || endMinute != null;

  factory ShiftModel.fromMap(String id, Map<String, dynamic> m) => ShiftModel(
        id: id,
        name: m['name'] as String? ?? '',
        startMinute: (m['startMinute'] as num?)?.toInt(),
        endMinute: (m['endMinute'] as num?)?.toInt(),
        endNextDay: m['endNextDay'] as bool? ?? false,
        inLocation: m['inLocation'] is Map
            ? ShiftLocation.fromMap(Map<String, dynamic>.from(m['inLocation']))
            : null,
        outLocation: m['outLocation'] is Map
            ? ShiftLocation.fromMap(Map<String, dynamic>.from(m['outLocation']))
            : null,
        radiusM: (m['radiusM'] as num?)?.toInt() ?? defaultRadiusM,
        userIds: List<String>.from(m['userIds'] as List? ?? const []),
      );

  factory ShiftModel.fromDoc(DocumentSnapshot doc) =>
      ShiftModel.fromMap(doc.id, doc.data() as Map<String, dynamic>);

  Map<String, dynamic> toMap() => {
        'name': name,
        if (startMinute != null) 'startMinute': startMinute,
        if (endMinute != null) 'endMinute': endMinute,
        if (endNextDay) 'endNextDay': true,
        if (inLocation != null) 'inLocation': inLocation!.toMap(),
        if (outLocation != null) 'outLocation': outLocation!.toMap(),
        'radiusM': radiusM,
        'userIds': userIds,
      };

  ShiftModel copyWith({
    String? name,
    int? startMinute,
    int? endMinute,
    bool? endNextDay,
    ShiftLocation? inLocation,
    ShiftLocation? outLocation,
    int? radiusM,
    List<String>? userIds,
    bool clearTimes = false,
    bool clearOutLocation = false,
    bool clearLocation = false,
  }) =>
      ShiftModel(
        id: id,
        name: name ?? this.name,
        startMinute: clearTimes ? null : (startMinute ?? this.startMinute),
        endMinute: clearTimes ? null : (endMinute ?? this.endMinute),
        endNextDay: clearTimes ? false : (endNextDay ?? this.endNextDay),
        inLocation: clearLocation ? null : (inLocation ?? this.inLocation),
        outLocation: (clearLocation || clearOutLocation)
            ? null
            : (outLocation ?? this.outLocation),
        radiusM: radiusM ?? this.radiusM,
        userIds: userIds ?? this.userIds,
      );

  /// "09:30 - 18:00", "22:00 - 06:00 (next day)", or "" when there are no times.
  String get timeLabel {
    String fmt(int? m) => m == null
        ? '--:--'
        : '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    if (!hasTimes) return '';
    return '${fmt(startMinute)} - ${fmt(endMinute)}${endNextDay ? ' (next day)' : ''}';
  }
}
