import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String username;
  final String role;
  final DateTime createdAt;

  const UserModel({
    required this.id,
    required this.username,
    required this.role,
    required this.createdAt,
  });

  bool get isAdmin => role == 'admin';
  bool get isViewer => role.toLowerCase() == 'viewer';
  bool get isQC => role.toLowerCase() == 'operator';

  factory UserModel.fromMap(Map<String, dynamic> map, String id) {
    // Safely parse the date whether it comes from Firestore (Timestamp) or Local Cache (int)
    DateTime parsedDate = DateTime.now();
    if (map['createdAt'] is Timestamp) {
      parsedDate = (map['createdAt'] as Timestamp).toDate();
    } else if (map['createdAt'] is int) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int);
    }

    return UserModel(
      id: id,
      username: map['username'] as String? ?? '',
      role: map['role'] as String? ?? 'operator',
      createdAt: parsedDate,
    );
  }

  // Used for saving to Firestore
  Map<String, dynamic> toMap() => {
    'username': username,
    'role': role,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  // NEW: Used safely for Local Storage JSON encoding!
  Map<String, dynamic> toJson() => {
    'id': id, // Ensure ID is saved so it can be extracted in getCachedUser
    'username': username,
    'role': role,
    'createdAt': createdAt.millisecondsSinceEpoch, // Encodes safely as an int
  };

  UserModel copyWith({String? username, String? role}) {
    return UserModel(
      id: id,
      username: username ?? this.username,
      role: role ?? this.role,
      createdAt: createdAt,
    );
  }
}