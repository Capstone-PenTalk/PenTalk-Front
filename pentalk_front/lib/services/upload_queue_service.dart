import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';  // Color 사용
import 'dart:convert';
import '../models/drawing_models.dart';

/// ===============================
/// 업로드 Queue 관리 서비스
/// 실패한 배치를 저장했다가 재전송
/// ===============================
class UploadQueueService {
  static Database? _database;

  /// 데이터베이스 초기화
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'upload_queue.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE pending_uploads (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            strokes_json TEXT NOT NULL,
            retry_count INTEGER DEFAULT 0,
            created_at INTEGER NOT NULL,
            last_attempt_at INTEGER
          )
        ''');

        // 인덱스
        await db.execute('''
          CREATE INDEX idx_session_id ON pending_uploads(session_id)
        ''');

        await db.execute('''
          CREATE INDEX idx_created_at ON pending_uploads(created_at)
        ''');

        debugPrint('✅ Upload queue database created');
      },
    );
  }

  /// ===============================
  /// Queue에 배치 추가
  /// ===============================
  static Future<int> addToQueue({
    required String sessionId,
    required List<Stroke> strokes,
  }) async {
    final db = await database;

    // Stroke → JSON
    final strokesJson = strokes.map((s) => {
      'sId': s.strokeId,  // id → strokeId
      'pts': s.points.map((p) => {'x': p.x, 'y': p.y}).toList(),
      'c': '#${s.color.value.toRadixString(16).padLeft(8, '0').substring(2)}',
      'w': s.width,
    }).toList();

    final id = await db.insert('pending_uploads', {
      'session_id': sessionId,
      'strokes_json': jsonEncode(strokesJson),
      'retry_count': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    debugPrint('📥 Added to queue: $id (${strokes.length} strokes)');
    return id;
  }

  /// ===============================
  /// Queue에서 대기 중인 배치 가져오기
  /// ===============================
  static Future<List<QueuedBatch>> getPendingBatches() async {
    final db = await database;

    final results = await db.query(
      'pending_uploads',
      orderBy: 'created_at ASC',
    );

    return results.map((row) {
      final strokesJson = jsonDecode(row['strokes_json'] as String) as List;

      final strokes = strokesJson.map((json) {
        final points = (json['pts'] as List).map((p) =>
            DrawPoint(
              x: (p['x'] as num).toDouble(),
              y: (p['y'] as num).toDouble(),
            )
        ).toList();

        // 색상 파싱
        final colorString = json['c'] as String;
        final colorInt = int.parse(colorString.replaceFirst('#', ''), radix: 16);
        final color = Color(0xFF000000 | colorInt);

        return Stroke(
          strokeId: json['sId'] as int,
          points: points,
          color: color,
          width: (json['w'] as num).toDouble(),
        );
      }).toList();

      return QueuedBatch(
        id: row['id'] as int,
        sessionId: row['session_id'] as String,
        strokes: strokes,
        retryCount: row['retry_count'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      );
    }).toList();
  }

  /// ===============================
  /// Queue에서 배치 삭제 (전송 성공 시)
  /// ===============================
  static Future<void> removeFromQueue(int id) async {
    final db = await database;

    await db.delete(
      'pending_uploads',
      where: 'id = ?',
      whereArgs: [id],
    );

    debugPrint('✅ Removed from queue: $id');
  }

  /// ===============================
  /// 재시도 횟수 증가
  /// ===============================
  static Future<void> incrementRetryCount(int id) async {
    final db = await database;

    await db.update(
      'pending_uploads',
      {
        'retry_count': (await db.query(
          'pending_uploads',
          columns: ['retry_count'],
          where: 'id = ?',
          whereArgs: [id],
        )).first['retry_count'] as int + 1,
        'last_attempt_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    debugPrint('🔄 Incremented retry count for: $id');
  }

  /// ===============================
  /// 재시도 횟수 초과한 배치 삭제
  /// ===============================
  static Future<int> removeFailedBatches({int maxRetries = 3}) async {
    final db = await database;

    final count = await db.delete(
      'pending_uploads',
      where: 'retry_count >= ?',
      whereArgs: [maxRetries],
    );

    if (count > 0) {
      debugPrint('🗑️ Removed $count failed batches (max retries exceeded)');
    }

    return count;
  }

  /// ===============================
  /// Queue 통계
  /// ===============================
  static Future<QueueStats> getStats() async {
    final db = await database;

    final result = await db.rawQuery('''
      SELECT 
        COUNT(*) as total,
        SUM(CASE WHEN retry_count = 0 THEN 1 ELSE 0 END) as pending,
        SUM(CASE WHEN retry_count > 0 THEN 1 ELSE 0 END) as retrying
      FROM pending_uploads
    ''');

    final row = result.first;
    return QueueStats(
      total: row['total'] as int,
      pending: row['pending'] as int,
      retrying: row['retrying'] as int,
    );
  }

  /// ===============================
  /// Queue 전체 삭제 (테스트용)
  /// ===============================
  static Future<void> clearAll() async {
    final db = await database;
    await db.delete('pending_uploads');
    debugPrint('🗑️ Cleared all pending uploads');
  }
}

/// ===============================
/// Queue에 저장된 배치
/// ===============================
class QueuedBatch {
  final int id;
  final String sessionId;
  final List<Stroke> strokes;
  final int retryCount;
  final DateTime createdAt;

  QueuedBatch({
    required this.id,
    required this.sessionId,
    required this.strokes,
    required this.retryCount,
    required this.createdAt,
  });
}

/// ===============================
/// Queue 통계
/// ===============================
class QueueStats {
  final int total;
  final int pending;
  final int retrying;

  QueueStats({
    required this.total,
    required this.pending,
    required this.retrying,
  });

  @override
  String toString() => 'Total: $total, Pending: $pending, Retrying: $retrying';
}