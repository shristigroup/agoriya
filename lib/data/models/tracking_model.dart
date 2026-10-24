import 'package:cloud_firestore/cloud_firestore.dart';

/// One punch-in session. Doc ID format: '{date}_{HHmmss}' e.g. '2026-04-16_093045'.
class TrackingModel {
  final String id;
  final String date;
  final DateTime startTime;
  final DateTime? stopTime;
  final String? punchInImage;

  /// OSRM-accurate total distance for this session in km.
  final double distance;

  /// Number of customer visits logged during this session.
  final int visitCount;

  /// Server timestamp of the last batch sync (the last locations write).
  /// Documents written by older builds call this field `lastUpdatedAt`.
  final DateTime? lastBatchSyncedAt;

  /// Set by the server watchdog when it closed this session itself (e.g.
  /// `no_location_data`); null when the user punched out. Read-only on the
  /// client — never written back.
  final String? autoClosedReason;

  const TrackingModel({
    required this.id,
    required this.date,
    required this.startTime,
    this.stopTime,
    this.punchInImage,
    this.distance = 0.0,
    this.visitCount = 0,
    this.lastBatchSyncedAt,
    this.autoClosedReason,
  });

  // ── Computed ────────────────────────────────────────────────────────────────

  bool get isActive => stopTime == null;
  bool get isStopped => stopTime != null;

  /// Closed by the server watchdog rather than by the user.
  bool get wasAutoClosed => stopTime != null && autoClosedReason != null;

  bool get isPunchedIn => isActive;
  bool get isPunchedOut => isStopped;

  Duration get attendanceDuration {
    final end = stopTime ?? DateTime.now();
    return end.difference(startTime);
  }

  // ── Doc ID helpers ──────────────────────────────────────────────────────────

  static String buildId(String date, DateTime startTime) {
    final h = startTime.hour.toString().padLeft(2, '0');
    final m = startTime.minute.toString().padLeft(2, '0');
    final s = startTime.second.toString().padLeft(2, '0');
    return '${date}_$h:$m:$s';
  }

  static String dateFromId(String id) => id.substring(0, 10);

  // ── Firestore serialisation ─────────────────────────────────────────────────

  factory TrackingModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TrackingModel(
      id: doc.id,
      date: dateFromId(doc.id),
      startTime: (data['startTime'] as Timestamp).toDate(),
      stopTime: (data['stopTime'] as Timestamp?)?.toDate(),
      punchInImage: data['punchInImage'] as String?,
      distance: (data['distance'] as num?)?.toDouble() ?? 0.0,
      visitCount: (data['visitCount'] as num?)?.toInt() ?? 0,
      lastBatchSyncedAt:
          ((data['lastBatchSyncedAt'] ?? data['lastUpdatedAt']) as Timestamp?)
              ?.toDate(),
      autoClosedReason: data['autoClosedReason'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'startTime': Timestamp.fromDate(startTime),
      'distance': distance,
      'visitCount': visitCount,
      // Explicit (not derived from stopTime being absent) so the FCM
      // watchdog's collectionGroup query can filter on it directly.
      'isPunchedIn': stopTime == null,
    };
    if (stopTime != null) map['stopTime'] = Timestamp.fromDate(stopTime!);
    if (punchInImage != null) map['punchInImage'] = punchInImage;
    return map;
  }

  // ── JSON (Hive) serialisation ───────────────────────────────────────────────

  factory TrackingModel.fromJson(Map<String, dynamic> json) => TrackingModel(
        id: json['id'] as String,
        date: json['date'] as String,
        startTime: DateTime.parse(json['startTime'] as String),
        stopTime: json['stopTime'] != null
            ? DateTime.parse(json['stopTime'] as String)
            : null,
        punchInImage: json['punchInImage'] as String?,
        distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
        visitCount: (json['visitCount'] as num?)?.toInt() ?? 0,
        lastBatchSyncedAt:
            (json['lastBatchSyncedAt'] ?? json['lastUpdatedAt']) != null
                ? DateTime.parse(
                    (json['lastBatchSyncedAt'] ?? json['lastUpdatedAt'])
                        as String)
                : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'startTime': startTime.toIso8601String(),
        'stopTime': stopTime?.toIso8601String(),
        'punchInImage': punchInImage,
        'distance': distance,
        'visitCount': visitCount,
        'lastBatchSyncedAt': lastBatchSyncedAt?.toIso8601String(),
      };

  // ── copyWith ────────────────────────────────────────────────────────────────

  TrackingModel copyWith({
    DateTime? stopTime,
    String? punchInImage,
    double? distance,
    int? visitCount,
    DateTime? lastBatchSyncedAt,
    String? autoClosedReason,
    bool clearStopTime = false,
  }) =>
      TrackingModel(
        id: id,
        date: date,
        startTime: startTime,
        stopTime: clearStopTime ? null : (stopTime ?? this.stopTime),
        punchInImage: punchInImage ?? this.punchInImage,
        distance: distance ?? this.distance,
        visitCount: visitCount ?? this.visitCount,
        lastBatchSyncedAt: lastBatchSyncedAt ?? this.lastBatchSyncedAt,
        // Resuming a session clears the server-side reason too.
        autoClosedReason:
            clearStopTime ? null : (autoClosedReason ?? this.autoClosedReason),
      );
}