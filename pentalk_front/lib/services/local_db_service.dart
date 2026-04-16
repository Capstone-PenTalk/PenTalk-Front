import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import '../models/personal_stroke.dart';

/// ===============================
/// 로컬 DB 서비스 (개인 필기 저장용)
/// SQLite 사용
/// ===============================
class LocalDbService {
  static final LocalDbService _instance = LocalDbService._internal();
  static Database? _database;

  factory LocalDbService() => _instance;

  LocalDbService._internal();

  /// 데이터베이스 초기화
  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDatabase();
    return _database!;
  }

  /// DB 파일 생성 및 테이블 생성
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'personal_strokes.db');

    debugPrint('📂 Opening database at: $path');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// 테이블 생성
  Future<void> _onCreate(Database db, int version) async {
    debugPrint('🔨 Creating personal_strokes table...');

    await db.execute('''
      CREATE TABLE personal_strokes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        page_id TEXT NOT NULL,
        stroke_id INTEGER NOT NULL,
        color INTEGER NOT NULL,
        width REAL NOT NULL,
        points_json TEXT NOT NULL,
        refined_points_json TEXT,
        timestamp TEXT NOT NULL,
        UNIQUE(page_id, stroke_id)
      )
    ''');

    // 페이지별 조회 최적화를 위한 인덱스
    await db.execute('''
      CREATE INDEX idx_page_id ON personal_strokes(page_id)
    ''');

    // 시간순 정렬을 위한 인덱스
    await db.execute('''
      CREATE INDEX idx_timestamp ON personal_strokes(timestamp)
    ''');

    debugPrint('✅ Table created successfully');
  }

  /// DB 버전 업그레이드 (나중에 필요시)
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('⬆️ Upgrading database from v$oldVersion to v$newVersion');

    // 예: 버전 2에서 새 컬럼 추가
    // if (oldVersion < 2) {
    //   await db.execute('ALTER TABLE personal_strokes ADD COLUMN new_field TEXT');
    // }
  }

  /// ===============================
  /// CRUD 작업
  /// ===============================

  /// 1. 개인 필기 저장
  Future<int> insertStroke(PersonalStroke stroke) async {
    try {
      final db = await database;
      final id = await db.insert(
        'personal_strokes',
        stroke.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace, // 같은 stroke_id면 덮어쓰기
      );

      debugPrint('💾 Saved stroke #${stroke.strokeId} to DB (id: $id)');
      return id;
    } catch (e) {
      debugPrint('❌ Failed to save stroke: $e');
      rethrow;
    }
  }

  /// 2. 여러 개 한번에 저장 (배치)
  Future<void> insertStrokeBatch(List<PersonalStroke> strokes) async {
    if (strokes.isEmpty) return;

    try {
      final db = await database;
      final batch = db.batch();

      for (final stroke in strokes) {
        batch.insert(
          'personal_strokes',
          stroke.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
      debugPrint('💾 Saved ${strokes.length} strokes in batch');
    } catch (e) {
      debugPrint('❌ Failed to save batch: $e');
      rethrow;
    }
  }

  /// 3. 특정 페이지의 모든 필기 가져오기
  Future<List<PersonalStroke>> getStrokesByPageId(String pageId) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'personal_strokes',
        where: 'page_id = ?',
        whereArgs: [pageId],
        orderBy: 'timestamp ASC', // 시간순 정렬
      );

      final strokes = maps.map((map) => PersonalStroke.fromMap(map)).toList();
      debugPrint('📖 Loaded ${strokes.length} strokes for page: $pageId');

      return strokes;
    } catch (e) {
      debugPrint('❌ Failed to load strokes: $e');
      return [];
    }
  }

  /// 4. 특정 stroke 삭제 (실행 취소용)
  Future<int> deleteStroke(String pageId, int strokeId) async {
    try {
      final db = await database;
      final count = await db.delete(
        'personal_strokes',
        where: 'page_id = ? AND stroke_id = ?',
        whereArgs: [pageId, strokeId],
      );

      debugPrint('🗑️ Deleted stroke #$strokeId (rows affected: $count)');
      return count;
    } catch (e) {
      debugPrint('❌ Failed to delete stroke: $e');
      return 0;
    }
  }

  /// 5. 특정 페이지의 모든 필기 삭제
  Future<int> deleteAllStrokesInPage(String pageId) async {
    try {
      final db = await database;
      final count = await db.delete(
        'personal_strokes',
        where: 'page_id = ?',
        whereArgs: [pageId],
      );

      debugPrint('🗑️ Deleted all strokes in page: $pageId (count: $count)');
      return count;
    } catch (e) {
      debugPrint('❌ Failed to delete all strokes: $e');
      return 0;
    }
  }

  /// 6. 전체 데이터 삭제 (앱 초기화용)
  Future<void> deleteAllStrokes() async {
    try {
      final db = await database;
      await db.delete('personal_strokes');
      debugPrint('🗑️ Deleted all personal strokes');
    } catch (e) {
      debugPrint('❌ Failed to delete all: $e');
    }
  }

  /// 7. 특정 시간 이전 필기 삭제 (정리용)
  Future<int> deleteStrokesOlderThan(DateTime date) async {
    try {
      final db = await database;
      final count = await db.delete(
        'personal_strokes',
        where: 'timestamp < ?',
        whereArgs: [date.toIso8601String()],
      );

      debugPrint('🗑️ Deleted $count old strokes before $date');
      return count;
    } catch (e) {
      debugPrint('❌ Failed to delete old strokes: $e');
      return 0;
    }
  }

  /// 8. 전체 페이지 목록 가져오기
  Future<List<String>> getAllPageIds() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.rawQuery(
        'SELECT DISTINCT page_id FROM personal_strokes ORDER BY page_id',
      );

      return maps.map((m) => m['page_id'] as String).toList();
    } catch (e) {
      debugPrint('❌ Failed to get page list: $e');
      return [];
    }
  }

  /// 9. 통계: 총 필기 개수
  Future<int> getTotalStrokeCount() async {
    try {
      final db = await database;
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM personal_strokes');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('❌ Failed to get count: $e');
      return 0;
    }
  }

  /// 10. 통계: 페이지별 필기 개수
  Future<Map<String, int>> getStrokeCountByPage() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.rawQuery(
        'SELECT page_id, COUNT(*) as count FROM personal_strokes GROUP BY page_id',
      );

      return Map.fromEntries(
        maps.map((m) => MapEntry(m['page_id'] as String, m['count'] as int)),
      );
    } catch (e) {
      debugPrint('❌ Failed to get stats: $e');
      return {};
    }
  }

  /// ===============================
  /// 유틸리티
  /// ===============================

  /// DB 닫기
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
    debugPrint('📪 Database closed');
  }

  /// DB 완전 삭제 (개발/테스트용)
  Future<void> deleteDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'personal_strokes.db');

    await databaseFactory.deleteDatabase(path);
    _database = null;
    debugPrint('💥 Database deleted: $path');
  }
}