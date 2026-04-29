import 'dart:convert';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DrawingEventStore {
  DrawingEventStore._();

  static final DrawingEventStore instance = DrawingEventStore._();
  static const _dbName = 'drawing_events.db';
  static const _table = 'drawing_events';
  static const _draftTable = 'drawing_drafts';
  static const _dbVersion = 2;

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    final baseDir = await getApplicationDocumentsDirectory();
    final dbPath = '${baseDir.path}/$_dbName';
    _db = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createEventTable(db);
        await _createDraftTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createDraftTable(db);
        }
      },
    );
  }

  Future<void> _createEventTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        direction TEXT NOT NULL,
        event TEXT,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createDraftTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_draftTable (
        draft_key TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
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

  Future<void> saveDraft({
    required String draftKey,
    required Map<String, dynamic> payload,
  }) async {
    final db = _db;
    if (db == null) return;
    await db.insert(
      _draftTable,
      {
        'draft_key': draftKey,
        'payload': jsonEncode(payload),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> loadDraft(String draftKey) async {
    final db = _db;
    if (db == null) return null;
    final rows = await db.query(
      _draftTable,
      columns: ['payload'],
      where: 'draft_key = ?',
      whereArgs: [draftKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final payload = rows.first['payload'] as String?;
    if (payload == null || payload.isEmpty) return null;
    return Map<String, dynamic>.from(jsonDecode(payload) as Map);
  }

  Future<void> deleteDraft(String draftKey) async {
    final db = _db;
    if (db == null) return;
    await db.delete(
      _draftTable,
      where: 'draft_key = ?',
      whereArgs: [draftKey],
    );
  }
}
