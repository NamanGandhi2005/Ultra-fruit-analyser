import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class User {
  final String username;
  final String email;
  final String createdAt;
  int analysisCount;

  User({
    required this.username,
    required this.email,
    required this.createdAt,
    required this.analysisCount,
  });

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      username: map['username'] ?? '',
      email: map['email'] ?? '',
      createdAt: map['createdAt'] ?? '',
      analysisCount: map['analysisCount'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'email': email,
      'createdAt': createdAt,
      'analysisCount': analysisCount,
    };
  }

  static Future<User?> load(SharedPreferences prefs, String username) async {
    final userJson = prefs.getString('user_profile_$username');
    if (userJson != null) {
      return User.fromMap(json.decode(userJson));
    }
    return null;
  }

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setString('user_profile_$username', json.encode(toMap()));
  }
}
