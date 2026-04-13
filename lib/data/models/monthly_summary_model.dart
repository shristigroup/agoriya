import 'package:cloud_firestore/cloud_firestore.dart';

class MonthlySummaryModel {
  final String monthKey;      // 'YYYY-MM'
  final int punchCount;       // days with a punch-in
  final int totalHours;
  final int totalMinutes;
  final int totalDistanceKm;  // rounded km
  final int totalVisits;
  final int totalExpense;     // ₹ rounded
  final DateTime computedAt;

  const MonthlySummaryModel({
    required this.monthKey,
    required this.punchCount,
    required this.totalHours,
    required this.totalMinutes,
    required this.totalDistanceKm,
    required this.totalVisits,
    required this.totalExpense,
    required this.computedAt,
  });

  factory MonthlySummaryModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MonthlySummaryModel(
      monthKey: doc.id,
      punchCount: (data['punchCount'] as num?)?.toInt() ?? 0,
      totalHours: (data['totalHours'] as num?)?.toInt() ?? 0,
      totalMinutes: (data['totalMinutes'] as num?)?.toInt() ?? 0,
      totalDistanceKm: (data['totalDistanceKm'] as num?)?.toInt() ?? 0,
      totalVisits: (data['totalVisits'] as num?)?.toInt() ?? 0,
      totalExpense: (data['totalExpense'] as num?)?.toInt() ?? 0,
      computedAt: (data['computedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'punchCount': punchCount,
        'totalHours': totalHours,
        'totalMinutes': totalMinutes,
        'totalDistanceKm': totalDistanceKm,
        'totalVisits': totalVisits,
        'totalExpense': totalExpense,
        'computedAt': Timestamp.fromDate(computedAt),
      };

  factory MonthlySummaryModel.fromJson(Map<String, dynamic> json) =>
      MonthlySummaryModel(
        monthKey: json['monthKey'] as String? ?? '',
        punchCount: (json['punchCount'] as num?)?.toInt() ?? 0,
        totalHours: (json['totalHours'] as num?)?.toInt() ?? 0,
        totalMinutes: (json['totalMinutes'] as num?)?.toInt() ?? 0,
        totalDistanceKm: (json['totalDistanceKm'] as num?)?.toInt() ?? 0,
        totalVisits: (json['totalVisits'] as num?)?.toInt() ?? 0,
        totalExpense: (json['totalExpense'] as num?)?.toInt() ?? 0,
        computedAt: DateTime.parse(json['computedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'monthKey': monthKey,
        'punchCount': punchCount,
        'totalHours': totalHours,
        'totalMinutes': totalMinutes,
        'totalDistanceKm': totalDistanceKm,
        'totalVisits': totalVisits,
        'totalExpense': totalExpense,
        'computedAt': computedAt.toIso8601String(),
      };
}
