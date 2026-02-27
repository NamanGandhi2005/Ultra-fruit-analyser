import 'dart:convert';

class Scan {
  final int? id;
  final String userId;
  final String imagePath;
  final String fruit;
  final int stage;
  final String stageName;
  final double confidence;
  final bool isRotten;
  final DateTime dateTime;
  final Map<String, dynamic> nutrients;
  final String color;
  bool isSynced;

  Scan({
    this.id,
    required this.userId,
    required this.imagePath,
    required this.fruit,
    required this.stage,
    required this.stageName,
    required this.confidence,
    required this.isRotten,
    required this.dateTime,
    required this.nutrients,
    required this.color,
    this.isSynced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'image_path': imagePath,
      'fruit': fruit,
      'stage': stage,
      'stage_name': stageName,
      'confidence': confidence,
      'is_rotten': isRotten ? 1 : 0,
      'date_time': dateTime.toIso8601String(),
      'nutrients': json.encode(nutrients),
      'color': color,
      'is_synced': isSynced ? 1 : 0,
    };
  }

  factory Scan.fromMap(Map<String, dynamic> map) {
    return Scan(
      id: map['id'],
      userId: map['user_id'] ?? 'unknown',
      imagePath: map['image_path'],
      fruit: map['fruit'],
      stage: map['stage'],
      stageName: map['stage_name'],
      confidence: map['confidence'],
      isRotten: map['is_rotten'] == 1,
      dateTime: DateTime.parse(map['date_time']),
      nutrients: json.decode(map['nutrients']),
      color: map['color'],
      isSynced: map['is_synced'] == 1,
    );
  }
}
