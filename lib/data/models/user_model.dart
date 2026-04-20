import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id; // <firstName-lastName-phone>
  final String uid; // Firebase Auth UID
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final String? managerId;
  final Map<String, dynamic> reports; // hierarchical JSON
  final String? code; // org code this user belongs to

  const UserModel({
    required this.id,
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    this.managerId,
    this.reports = const {},
    this.code,
  });

  String get fullName => '$firstName $lastName';
  String get displayPhone => phoneNumber;

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      id: doc.id,
      uid: data['uid'] ?? '',
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      managerId: data['managerId'],
      reports: Map<String, dynamic>.from(data['reports'] ?? {}),
      code: data['code'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'uid': uid,
        'firstName': firstName,
        'lastName': lastName,
        'phoneNumber': phoneNumber,
        'managerId': managerId,
        'reports': reports,
        'code': code,
      };

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] ?? '',
        uid: json['uid'] ?? '',
        firstName: json['firstName'] ?? '',
        lastName: json['lastName'] ?? '',
        phoneNumber: json['phoneNumber'] ?? '',
        managerId: json['managerId'],
        reports: Map<String, dynamic>.from(json['reports'] ?? {}),
        code: json['code'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'uid': uid,
        'firstName': firstName,
        'lastName': lastName,
        'phoneNumber': phoneNumber,
        'managerId': managerId,
        'reports': reports,
        'code': code,
      };

  UserModel copyWith({
    String? id,
    String? uid,
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? managerId,
    Map<String, dynamic>? reports,
    String? code,
    bool clearManagerId = false,
    bool clearCode = false,
  }) =>
      UserModel(
        id: id ?? this.id,
        uid: uid ?? this.uid,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        managerId: clearManagerId ? null : (managerId ?? this.managerId),
        reports: reports ?? this.reports,
        code: clearCode ? null : (code ?? this.code),
      );
}
