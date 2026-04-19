import 'package:cloud_firestore/cloud_firestore.dart';

class OrgCodeModel {
  final String code;
  final String ownerId;
  final int totalUserCount;
  final int currentUserCount;

  const OrgCodeModel({
    required this.code,
    required this.ownerId,
    required this.totalUserCount,
    required this.currentUserCount,
  });

  int get remainingSeats => totalUserCount - currentUserCount;
  bool get isFull => currentUserCount >= totalUserCount;

  factory OrgCodeModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return OrgCodeModel(
      code: doc.id,
      ownerId: data['userId'] as String,
      totalUserCount: (data['totalUserCount'] as num?)?.toInt() ?? 5,
      currentUserCount: (data['currentUserCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': ownerId,
        'totalUserCount': totalUserCount,
        'currentUserCount': currentUserCount,
      };
}