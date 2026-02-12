import 'package:flutter/material.dart';
import '../models/drawing_models.dart';
import '../models/personal_stroke.dart';
import '../services/local_db_service.dart';

/// ===============================
/// 개인 필기 Provider (로컬 DB 연동)
/// ===============================
class PersonalDrawingProvider extends ChangeNotifier {
  final LocalDbService _dbService = LocalDbService();

  // 현재 페이지 ID
  String? _currentPageId;

  // 개인 필기 데이터 (완성된 선들)
  final Map<int, Stroke> _personalStrokes = {};

  // 현재 그리는 중인 선
  final Map<int, Stroke> _personalActiveStrokes = {};

  // 개인 필기 표시 여부
  bool _showPersonalLayer = true;

  // 로딩 상태
  bool _isLoading = false;

  // Getters
  Map<int, Stroke> get personalStrokes => _personalStrokes;
  Map<int, Stroke> get personalActiveStrokes => _personalActiveStrokes;
  bool get showPersonalLayer => _showPersonalLayer;
  bool get isLoading => _isLoading;
  String? get currentPageId => _currentPageId;

  /// 모든 개인 필기 (완성 + 진행중)
  List<Stroke> get allPersonalStrokes {
    return [..._personalStrokes.values, ..._personalActiveStrokes.values];
  }

  /// ===============================
  /// 페이지 로드
  /// ===============================
  Future<void> loadPage(String pageId) async {
    if (_currentPageId == pageId) {
      debugPrint('📄 Already loaded page: $pageId');
      return;
    }

    _isLoading = true;
    _currentPageId = pageId;
    _personalStrokes.clear();
    _personalActiveStrokes.clear();
    notifyListeners();

    try {
      debugPrint('📖 Loading personal strokes for page: $pageId');

      final personalStrokesList = await _dbService.getStrokesByPageId(pageId);

      for (final ps in personalStrokesList) {
        _personalStrokes[ps.strokeId] = ps.toStroke();
      }

      debugPrint('✅ Loaded ${_personalStrokes.length} personal strokes');
    } catch (e) {
      debugPrint('❌ Failed to load page: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// ===============================
  /// 그리기 시작
  /// ===============================
  void startDrawing(int strokeId, DrawPoint point, Color color, double width) {
    if (_currentPageId == null) {
      debugPrint('⚠️ Cannot draw: No page loaded');
      return;
    }

    final stroke = Stroke(
      strokeId: strokeId,
      color: color,
      width: width,
      points: [point],
    );

    _personalActiveStrokes[strokeId] = stroke;
    notifyListeners();
  }

  /// ===============================
  /// 그리기 이동
  /// ===============================
  void updateDrawing(int strokeId, DrawPoint point) {
    final stroke = _personalActiveStrokes[strokeId];
    if (stroke == null) {
      debugPrint('⚠️ Cannot update: Stroke $strokeId not found');
      return;
    }

    final updatedPoints = [...stroke.points, point];
    _personalActiveStrokes[strokeId] = stroke.copyWith(points: updatedPoints);

    // 3개마다 한번씩만 리렌더링 (최적화)
    if (updatedPoints.length % 3 == 0) {
      notifyListeners();
    }
  }

  /// ===============================
  /// 그리기 종료 (DB 저장)
  /// ===============================
  Future<void> endDrawing(int strokeId, List<DrawPoint>? refinedPoints) async {
    if (_currentPageId == null) {
      debugPrint('⚠️ Cannot end draw: No page loaded');
      return;
    }

    final stroke = _personalActiveStrokes.remove(strokeId);
    if (stroke == null) {
      debugPrint('⚠️ Cannot end: Stroke $strokeId not found');
      return;
    }

    // refined points가 있으면 적용
    final finalStroke = refinedPoints != null && refinedPoints.isNotEmpty
        ? stroke.withRefinedPoints(refinedPoints)
        : stroke;

    // 메모리에 추가
    _personalStrokes[strokeId] = finalStroke;
    notifyListeners();

    // DB에 저장 (비동기)
    try {
      final personalStroke = PersonalStroke.fromStroke(
        finalStroke,
        _currentPageId!,
      );

      await _dbService.insertStroke(personalStroke);
      debugPrint('💾 Saved personal stroke #$strokeId to DB');
    } catch (e) {
      debugPrint('❌ Failed to save stroke: $e');
      // DB 저장 실패해도 메모리에는 있으므로 계속 사용 가능
    }
  }

  /// ===============================
  /// 실행 취소 (마지막 선 삭제)
  /// ===============================
  Future<void> undoLastStroke() async {
    if (_personalStrokes.isEmpty) {
      debugPrint('⚠️ No strokes to undo');
      return;
    }

    if (_currentPageId == null) return;

    // 마지막 선 찾기 (strokeId가 가장 큰 것)
    final lastStrokeId = _personalStrokes.keys.reduce(
          (a, b) => a > b ? a : b,
    );

    // 메모리에서 삭제
    _personalStrokes.remove(lastStrokeId);
    notifyListeners();

    // DB에서 삭제
    try {
      await _dbService.deleteStroke(_currentPageId!, lastStrokeId);
      debugPrint('🗑️ Undo: Removed stroke #$lastStrokeId');
    } catch (e) {
      debugPrint('❌ Failed to delete stroke from DB: $e');
    }
  }

  /// ===============================
  /// 특정 선 삭제
  /// ===============================
  Future<void> deleteStroke(int strokeId) async {
    if (_currentPageId == null) return;

    final removed = _personalStrokes.remove(strokeId) != null ||
        _personalActiveStrokes.remove(strokeId) != null;

    if (removed) {
      notifyListeners();

      try {
        await _dbService.deleteStroke(_currentPageId!, strokeId);
        debugPrint('🗑️ Deleted stroke #$strokeId');
      } catch (e) {
        debugPrint('❌ Failed to delete stroke: $e');
      }
    }
  }

  /// ===============================
  /// 현재 페이지의 모든 필기 삭제
  /// ===============================
  Future<void> clearCurrentPage() async {
    if (_currentPageId == null) return;

    _personalStrokes.clear();
    _personalActiveStrokes.clear();
    notifyListeners();

    try {
      await _dbService.deleteAllStrokesInPage(_currentPageId!);
      debugPrint('🗑️ Cleared all personal strokes in page: $_currentPageId');
    } catch (e) {
      debugPrint('❌ Failed to clear page: $e');
    }
  }

  /// ===============================
  /// 개인 레이어 토글
  /// ===============================
  void togglePersonalLayer() {
    _showPersonalLayer = !_showPersonalLayer;
    notifyListeners();
    debugPrint('👁️ Personal layer: ${_showPersonalLayer ? 'ON' : 'OFF'}');
  }

  void setPersonalLayerVisible(bool visible) {
    if (_showPersonalLayer != visible) {
      _showPersonalLayer = visible;
      notifyListeners();
    }
  }

  /// ===============================
  /// 통계
  /// ===============================
  Future<int> getTotalStrokeCount() async {
    return await _dbService.getTotalStrokeCount();
  }

  Future<Map<String, int>> getStrokeCountByPage() async {
    return await _dbService.getStrokeCountByPage();
  }

  Future<List<String>> getAllPages() async {
    return await _dbService.getAllPageIds();
  }

  /// ===============================
  /// 정리
  /// ===============================

  /// 30일 이상 된 필기 삭제
  Future<int> cleanupOldStrokes({int days = 30}) async {
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    return await _dbService.deleteStrokesOlderThan(cutoffDate);
  }

  /// 전체 개인 필기 삭제 (초기화)
  Future<void> deleteAllPersonalStrokes() async {
    _personalStrokes.clear();
    _personalActiveStrokes.clear();
    _currentPageId = null;
    notifyListeners();

    await _dbService.deleteAllStrokes();
    debugPrint('💥 Deleted all personal strokes');
  }

  @override
  void dispose() {
    _dbService.close();
    super.dispose();
  }
}