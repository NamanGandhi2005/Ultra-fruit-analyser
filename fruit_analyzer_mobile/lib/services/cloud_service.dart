import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:flutter/foundation.dart';
import '../models/scan_model.dart';
import 'database_service.dart';

class CloudService {
  final DatabaseService _dbService = DatabaseService();

  // Observable sync status for UI
  static final ValueNotifier<String> syncStatus = ValueNotifier<String>("Idle");

  // --- MONGODB CONFIG ---
  static const String _connectionString = "mongodb+srv://namangandhipersonal_db_user:06mrYqOU9jeCrTGF@cluster0.kuzrlxp.mongodb.net/fruit_analyzer?retryWrites=true&w=majority";
  static const String _collectionName = "scans";

  Future<Db> _getDb() async {
    syncStatus.value = "Connecting to Mongo...";
    try {
      final db = await Db.create(_connectionString);
      await db.open();
      return db;
    } catch (e) {
      print('Cloud Sync: Connection FAILED: $e');
      syncStatus.value = "Mongo Connection Failed";
      rethrow;
    }
  }

  Future<void> uploadScan(Scan scan, String userId) async {
    Db? db;
    try {
      File imageFile = File(scan.imagePath);
      if (!await imageFile.exists()) {
        print('Cloud Sync: Local image not found');
        return;
      }

      // 1. Convert Image to Base64 (Store directly in MongoDB)
      syncStatus.value = "Encoding Image...";
      List<int> imageBytes = await imageFile.readAsBytes();
      String base64Image = base64Encode(imageBytes);

      // 2. Prepare Data
      db = await _getDb();
      final collection = db.collection(_collectionName);

      final Map<String, dynamic> scanData = scan.toMap();
      scanData['image_data_base64'] = base64Image; // Store actual image data
      scanData.remove('image_path'); // Don't need local path in cloud
      scanData['user_id'] = userId; 
      scanData['is_synced'] = 1;
      scanData.remove('id');

      syncStatus.value = "Uploading to Atlas...";
      var result = await collection.insertOne(scanData);
      
      if (result.isSuccess) {
        if (scan.id != null) {
          await _dbService.markAsSynced(scan.id!);
        }
        syncStatus.value = "Sync Complete";
      } else {
        syncStatus.value = "Save Failed";
      }
    } catch (e) {
      print('Cloud Sync Error: $e');
      syncStatus.value = "Sync Error";
    } finally {
      await db?.close();
      Future.delayed(const Duration(seconds: 3), () {
        if (syncStatus.value == "Sync Complete") syncStatus.value = "Idle";
      });
    }
  }

  Future<void> syncDown(String userId) async {
    Db? db;
    try {
      db = await _getDb();
      final collection = db.collection(_collectionName);
      
      final documents = await collection.find(where.eq('user_id', userId)).toList();
      final appDir = await getApplicationDocumentsDirectory();

      for (var doc in documents) {
        DateTime dt = DateTime.parse(doc['date_time']);
        List<Scan> localScans = await _dbService.getAllScans(userId);
        bool exists = localScans.any((s) => s.dateTime.toIso8601String() == dt.toIso8601String());

        if (!exists && doc.containsKey('image_data_base64')) {
          // Recover image from Base64
          String base64Image = doc['image_data_base64'];
          String localPath = '${appDir.path}/sync_${dt.millisecondsSinceEpoch}.jpg';
          
          File file = File(localPath);
          await file.writeAsBytes(base64Decode(base64Image));

          doc['image_path'] = localPath;
          doc.remove('image_data_base64');
          doc['is_synced'] = 1;
          doc.remove('_id');
          
          await _dbService.insertScan(Scan.fromMap(doc));
        }
      }
    } catch (e) {
      print('Cloud Sync Error (SyncDown): $e');
    } finally {
      await db?.close();
    }
  }

  Future<void> syncPendingScans(String userId) async {
    try {
      List<Scan> allScans = await _dbService.getAllScans(userId);
      List<Scan> pending = allScans.where((s) => !s.isSynced).toList();
      for (var scan in pending) {
        await uploadScan(scan, userId);
      }
    } catch (e) {
      print('Cloud Sync Error (Pending): $e');
    }
  }

  Future<void> deleteScan(String userId, String timestamp) async {
    Db? db;
    try {
      db = await _getDb();
      final collection = db.collection(_collectionName);
      String dateStr = DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp)).toIso8601String();
      await collection.remove(where.eq('user_id', userId).and(where.eq('date_time', dateStr)));
    } catch (e) {
      print('Cloud Sync Error (Delete): $e');
    } finally {
      await db?.close();
    }
  }
}
