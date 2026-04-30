import 'package:flutter/material.dart';
import '../models/drawing_models.dart';
import '../models/personal_stroke.dart';
import '../services/local_db_service.dart';

/// ===============================
/// 개인 필기 Provider (로컬 DB 연동)
/// ===============================
class PersonalDrawingProvider extends ChangeNotifier {
  final LocalDbService _dbService = LocalDbService();

  String? _currentPageId;
  final Map<int, Stroke> _personalStrokes = {};
  final Map<int, Stroke> _personalActiveStrokes = {};
  bool _showPersonalLayer = true;
  bool _isLoading = false;

  Map<int, Stroke> get personalStrokes => _personalStrokes;
  Map<int, Stroke> get personalActiveStrokes => _personalActiveStrokes;
  bool get showPersonalLayer => _showPersonalLayer;
  bool get isLoading => _isLoading;
  String? get currentPageId => _currentPageId;

  List<Stroke> get allPersonalStrokes {
    return [..._personalStrokes.values, ..._personalActiveStrokes.values];
  }

  /// ===============================
  /// 페이지 로드
  /// ===============================
  Future<void> loadPage(String pageId) async {
    if (_currentPageId == pageId) {
      debugPrint('Already loaded page: $pageId');
      return;
    }

    _isLoading = true;
    _currentPageId = pageId;
    _personalStrokes.clear();
    _personalActiveStrokes.clear();
    notifyListeners();

    try {
      debugPrint('Loading personal strokes for page: $pageId');

      final personalStrokesList = await _dbService.getStrokesByPageId(pageId);

      for (final ps in personalStrokesList) {
        _personalStrokes[ps.strokeId] = ps.toStroke();
      }

      debugPrint('Loaded ${_personalStrokes.length} personal strokes');
    } catch (e) {
      debugPrint('Failed to load page: $e');
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
      debugPrint('Cannot draw: No page loaded');
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
      debugPrint('Cannot update: Stroke $strokeId not found');
      return;
    }

    final updatedPoints = [...stroke.points, point];
    _personalActiveStrokes[strokeId] = stroke.copyWith(points: updatedPoints);

    if (updatedPoints.length % 3 == 0) {
      notifyListeners();
    }
  }

  /// ===============================
  /// 그리기 종료 (DB 저장)
  /// ===============================
  Future<void> endDrawing(int strokeId, List<DrawPoint>? refinedPoints) async {
    if (_currentPageId == null) {
      debugPrint('Cannot end draw: No page loaded');
      return;
    }

    final stroke = _personalActiveStrokes.remove(strokeId);
    if (stroke == null) {
      debugPrint('Cannot end: Stroke $strokeId not found');
      return;
    }

    final copiedRefinedPoints = refinedPoints != null
        ? List<DrawPoint>.from(refinedPoints)
        : null;

    final finalStroke = copiedRefinedPoints != null && copiedRefinedPoints.isNotEmpty
        ? stroke.withRefinedPoints(copiedRefinedPoints)
        : stroke;

    _personalStrokes[strokeId] = finalStroke;
    debugPrint(
      'Personal stroke committed: #$strokeId '
      'basePoints=${stroke.points.length} '
      'refinedPoints=${finalStroke.refinedPoints?.length ?? 0} '
      'page=$_currentPageId',
    );
    notifyListeners();

    try {
      final personalStroke = PersonalStroke.fromStroke(
        finalStroke,
        _currentPageId!,
      );
      await _dbService.insertStroke(personalStroke);
      debugPrint('Saved personal stroke #$strokeId to DB');
    } catch (e) {
      debugPrint('Failed to save stroke: $e');
    }
  }

  /// ===============================
  /// 실행 취소
  /// ===============================
  Future<void> undoLastStroke() async {
    if (_personalStrokes.isEmpty) {
      debugPrint('No strokes to undo');
      return;
    }

    if (_currentPageId == null) return;

    final lastStrokeId = _personalStrokes.keys.reduce(
          (a, b) => a > b ? a : b,
    );

    _personalStrokes.remove(lastStrokeId);
    notifyListeners();

    try {
      await _dbService.deleteStroke(_currentPageId!, lastStrokeId);
      debugPrint('Undo: Removed stroke #$lastStrokeId');
    } catch (e) {
      debugPrint('Failed to delete stroke from DB: $e');
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
        debugPrint('Deleted stroke #$strokeId');
      } catch (e) {
        debugPrint('Failed to delete stroke: $e');
      }
    }
  }

  /// ===============================
  /// 현재 페이지 모든 필기 삭제
  /// ===============================
  Future<void> clearCurrentPage() async {
    if (_currentPageId == null) return;

    _personalStrokes.clear();
    _personalActiveStrokes.clear();
    notifyListeners();

    try {
      await _dbService.deleteAllStrokesInPage(_currentPageId!);
      debugPrint('Cleared all personal strokes in page: $_currentPageId');
    } catch (e) {
      debugPrint('Failed to clear page: $e');
    }
  }

  /// ===============================
  /// PDF export용 전체 stroke 취합
  ///
  /// [pageIdOrder]: 세션의 materialTitle 순서대로 전달
  /// 또는 문서 페이지 키(materialId:pageNumber) 기반 매핑 전달
  ///
  /// 반환: POST /export/pdf 의 strokes 배열 형식
  /// ===============================
  Future<List<Map<String, dynamic>>> getAllPersonalStrokesForExport({
    required Map<String, int> pageMapping,
  }) async {
    debugPrint('Page mapping: $pageMapping');

    // DB에 저장된 모든 페이지 ID 조회
    final allPageIds = await _dbService.getAllPageIds();

    final result = <Map<String, dynamic>>[];

    for (final pageId in allPageIds) {
      // 알 수 없는 pageId는 page: 1로 fallback (안전 처리)
      final pageNumber = pageMapping[pageId] ?? 1;

      if (!pageMapping.containsKey(pageId)) {
        debugPrint('Unknown pageId "$pageId" -> fallback to page 1');
      }

      final strokes = await _dbService.getStrokesByPageId(pageId);

      for (final ps in strokes) {
        result.add(ps.toServerJson(pageNumber));
      }

      debugPrint(
          'Page "$pageId" (page: $pageNumber): ${strokes.length} strokes');
    }

    debugPrint(
        'Total export strokes: ${result.length} across ${allPageIds.length} pages');

    return result;
  }

  /// ===============================
  /// 개인 레이어 토글
  /// ===============================
  void togglePersonalLayer() {
    _showPersonalLayer = !_showPersonalLayer;
    notifyListeners();
    debugPrint('Personal layer: ${_showPersonalLayer ? 'ON' : 'OFF'}');
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

  Future<int> cleanupOldStrokes({int days = 30}) async {
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    return await _dbService.deleteStrokesOlderThan(cutoffDate);
  }

  Future<void> deleteAllPersonalStrokes() async {
    _personalStrokes.clear();
    _personalActiveStrokes.clear();
    _currentPageId = null;
    notifyListeners();

    await _dbService.deleteAllStrokes();
    debugPrint('Deleted all personal strokes');
  }

  @override
  void dispose() {
    _dbService.close();
    super.dispose();
  }
}
