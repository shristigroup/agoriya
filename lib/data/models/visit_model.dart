import 'package:cloud_firestore/cloud_firestore.dart';

class VisitModel {
  final String id; // doc ID
  final String clientName;
  final String location;
  final DateTime checkinTimestamp;
  final DateTime? checkoutTimestamp;
  final String? visitNotes;
  final double? expenseAmount;
  final String? billCopy; // Storage URL
  final List<VisitComment> comments;

  const VisitModel({
    required this.id,
    required this.clientName,
    required this.location,
    required this.checkinTimestamp,
    this.checkoutTimestamp,
    this.visitNotes,
    this.expenseAmount,
    this.billCopy,
    this.comments = const [],
  });

  bool get isCheckedOut => checkoutTimestamp != null;

  Duration get visitDuration {
    if (checkoutTimestamp == null) return DateTime.now().difference(checkinTimestamp);
    return checkoutTimestamp!.difference(checkinTimestamp);
  }

  factory VisitModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return VisitModel(
      id: doc.id,
      clientName: data['clientName'] ?? '',
      location: data['location'] ?? '',
      checkinTimestamp: (data['checkinTimestamp'] as Timestamp).toDate(),
      checkoutTimestamp: (data['checkoutTimestamp'] as Timestamp?)?.toDate(),
      visitNotes: data['visitNotes'],
      expenseAmount: (data['expenseAmount'] as num?)?.toDouble(),
      billCopy: data['billCopy'],
      comments: [],
    );
  }

  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'clientName': clientName,
      'location': location,
      'checkinTimestamp': Timestamp.fromDate(checkinTimestamp),
    };
    if (checkoutTimestamp != null) {
      map['checkoutTimestamp'] = Timestamp.fromDate(checkoutTimestamp!);
    }
    if (visitNotes != null) map['visitNotes'] = visitNotes;
    if (expenseAmount != null) map['expenseAmount'] = expenseAmount;
    if (billCopy != null) map['billCopy'] = billCopy;
    return map;
  }

  factory VisitModel.fromJson(Map<String, dynamic> json) => VisitModel(
        id: json['id'] ?? '',
        clientName: json['clientName'] ?? '',
        location: json['location'] ?? '',
        checkinTimestamp: DateTime.parse(json['checkinTimestamp']),
        checkoutTimestamp: json['checkoutTimestamp'] != null
            ? DateTime.parse(json['checkoutTimestamp'])
            : null,
        visitNotes: json['visitNotes'],
        expenseAmount: (json['expenseAmount'] as num?)?.toDouble(),
        billCopy: json['billCopy'],
        comments: (json['comments'] as List<dynamic>? ?? [])
            .map((e) => VisitComment.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'clientName': clientName,
        'location': location,
        'checkinTimestamp': checkinTimestamp.toIso8601String(),
        'checkoutTimestamp': checkoutTimestamp?.toIso8601String(),
        'visitNotes': visitNotes,
        'expenseAmount': expenseAmount,
        'billCopy': billCopy,
        'comments': comments.map((c) => c.toJson()).toList(),
      };

  VisitModel copyWith({
    String? id,
    String? clientName,
    String? location,
    DateTime? checkinTimestamp,
    DateTime? checkoutTimestamp,
    String? visitNotes,
    double? expenseAmount,
    String? billCopy,
    List<VisitComment>? comments,
  }) =>
      VisitModel(
        id: id ?? this.id,
        clientName: clientName ?? this.clientName,
        location: location ?? this.location,
        checkinTimestamp: checkinTimestamp ?? this.checkinTimestamp,
        checkoutTimestamp: checkoutTimestamp ?? this.checkoutTimestamp,
        visitNotes: visitNotes ?? this.visitNotes,
        expenseAmount: expenseAmount ?? this.expenseAmount,
        billCopy: billCopy ?? this.billCopy,
        comments: comments ?? this.comments,
      );
}

class VisitComment {
  final String id;
  final String userId;
  final String userName;
  final String text;
  final DateTime timestamp;

  const VisitComment({
    required this.id,
    required this.userId,
    required this.userName,
    required this.text,
    required this.timestamp,
  });

  factory VisitComment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return VisitComment(
      id: doc.id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      text: data['text'] ?? '',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'userName': userName,
        'text': text,
        'timestamp': Timestamp.fromDate(timestamp),
      };

  factory VisitComment.fromJson(Map<String, dynamic> json) => VisitComment(
        id: json['id'] ?? '',
        userId: json['userId'] ?? '',
        userName: json['userName'] ?? '',
        text: json['text'] ?? '',
        timestamp: DateTime.parse(json['timestamp']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'userName': userName,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };
}
