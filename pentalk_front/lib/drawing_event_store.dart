import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DrawingEventStore {
  DrawingEventStore._();

  static final DrawingEventStore instance = DrawingEventStore._();
  static const _dbName = 'drawing_events.db';
  static const _table = 'drawing_events';

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    final baseDir = await getApplicationDocumentsDirectory();
    final dbPath = path.join(baseDir.path, _dbName);
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            direction TEXT NOT NULL,
            event TEXT,
            payload TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<void> saveEvent({
    required String direction,
    required Map<String, dynamic> payload,
  }) async {
    final db = _db;
    if (db == null) return;
    final event = payload['e']?.toString();
    await db.insert(
      _table,
      {
        'direction': direction,
        'event': event,
        'payload': jsonEncode(payload),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }
}
