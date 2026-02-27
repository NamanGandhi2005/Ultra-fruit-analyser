import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/scan_model.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'fruit_analyzer.db');
    return await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE scans(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT,
        image_path TEXT,
        fruit TEXT,
        stage INTEGER,
        stage_name TEXT,
        confidence REAL,
        is_rotten INTEGER,
        date_time TEXT,
        nutrients TEXT,
        color TEXT,
        is_synced INTEGER DEFAULT 0
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE scans ADD COLUMN user_id TEXT DEFAULT 'unknown'");
    }
    if (oldVersion < 3) {
      await db.execute("ALTER TABLE scans ADD COLUMN is_synced INTEGER DEFAULT 0");
    }
  }

  Future<int> insertScan(Scan scan) async {
    Database db = await database;
    return await db.insert('scans', scan.toMap());
  }

  Future<void> markAsSynced(int id) async {
    Database db = await database;
    await db.update(
      'scans',
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Scan>> getAllScans(String userId) async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'scans', 
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'date_time DESC'
    );
    return List.generate(maps.length, (i) => Scan.fromMap(maps[i]));
  }

  Future<List<Scan>> getScansByFruit(String userId, String fruit) async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'scans',
      where: 'user_id = ? AND fruit = ?',
      whereArgs: [userId, fruit],
      orderBy: 'date_time DESC',
    );
    return List.generate(maps.length, (i) => Scan.fromMap(maps[i]));
  }

  Future<void> deleteScan(int id) async {
    Database db = await database;
    await db.delete(
      'scans',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
