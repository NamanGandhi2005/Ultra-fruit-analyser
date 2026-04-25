import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class HistoryEntry {
  final int? id;
  final String fruit;
  final double confidence;
  final bool isRotten;
  final Map<String, dynamic> nutrients;
  final DateTime timestamp;

  HistoryEntry({
    this.id,
    required this.fruit,
    required this.confidence,
    required this.isRotten,
    required this.nutrients,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fruit': fruit,
      'confidence': confidence,
      'is_rotten': isRotten ? 1 : 0,
      'nutrients': jsonEncode(nutrients),
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory HistoryEntry.fromMap(Map<String, dynamic> map) {
    return HistoryEntry(
      id: map['id'],
      fruit: map['fruit'],
      confidence: map['confidence'],
      isRotten: map['is_rotten'] == 1,
      nutrients: jsonDecode(map['nutrients']),
      timestamp: DateTime.parse(map['timestamp']),
    );
  }
}

class HistoryService {
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'fruit_history.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE history(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            fruit TEXT,
            confidence REAL,
            is_rotten INTEGER,
            nutrients TEXT,
            timestamp TEXT
          )
        ''');
      },
    );
  }

  Future<void> saveEntry(HistoryEntry entry) async {
    final db = await database;
    await db.insert('history', entry.toMap());
  }

  Future<List<HistoryEntry>> getAllEntries() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('history', orderBy: 'timestamp DESC');
    return List.generate(maps.length, (i) => HistoryEntry.fromMap(maps[i]));
  }

  Future<void> deleteAll() async {
    final db = await database;
    await db.delete('history');
  }
}
