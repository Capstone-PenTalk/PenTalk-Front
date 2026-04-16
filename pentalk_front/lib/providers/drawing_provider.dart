import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/drawing_models.dart';
import '../drawing_event_store.dart';
import '../native_drawing.dart';
import '../services/socket_service.dart';

/// ===============================
/// 판서 데이터 Provider (Socket.IO 통합)
/// 최적화: notifyListeners() 호출 최소화
/// ===============================
class DrawingProvider extends ChangeNotifier {
  // Socket.IO 서비스
  final SocketService _socketService = SocketService();
  final DrawingEventStore _eventStore = DrawingEventStore.instance;
  StreamSubscription<Map<String, dynamic>>? _nativeDrawEventSubscription;

  // 내 펜 (로컬에서 그린 선들)
  final Map<int, Stroke> _myStrokes = {};
  final Map<int, Stroke> _myActiveStrokes = {};

  // 상대 펜 (다른 사람이 그린 선들)
  final Map<int, Stroke> _othersStrokes = {};
  final Map<int, Stroke> _othersActiveStrokes = {};

  // 학생 개인 필기 (로컬 전용, 서버 미전송)
  final Map<int, Stroke> _studentPrivateStrokes = {};
  final Map<int, Stroke> _studentPrivateActiveStrokes = {};

  // 배경 이미지 URL
  String? _backgroundUrl;
  double? _pdfWidth;
  double? _pdfHeight;

  // 그리기 모드 (교사용)
  bool _isDrawingMode = false;
  Color _currentColor = Colors.black;
  double _currentWidth = 2.5;
  Color? _lastNativeColor;
  double? _lastNativeWidth;

  // 사용자 정보
  String? _userId;
  String? _roomId;
  bool _isTeacher = false;

  // 소켓 연결 상태
  bool _isSocketConnected = false;
  int _strokeIdSeed = DateTime.now().microsecondsSinceEpoch;
  String? _localDraftKey;
  bool _isHydratingLocalDraft = false;

  // Getters
  Map<int, Stroke> get myStrokes => _myStrokes;
  Map<int, Stroke> get myActiveStrokes => _myActiveStrokes;
  Map<int, Stroke> get othersStrokes => _othersStrokes;
  Map<int, Stroke> get othersActiveStrokes => _othersActiveStrokes;
  Map<int, Stroke> get studentPrivateStrokes => _studentPrivateStrokes;
  Map<int, Stroke> get studentPrivateActiveStrokes => _studentPrivateActiveStrokes;
  List<Stroke> get myCompletedStrokes => _myStrokes.values.toList();
  List<Stroke> get myActiveStrokeList => _myActiveStrokes.values.toList();
  List<Stroke> get othersCompletedStrokes => _othersStrokes.values.toList();
  List<Stroke> get othersActiveStrokeList =>
      _othersActiveStrokes.values.toList();
  List<Stroke> get studentPrivateCompletedStrokes =>
      _studentPrivateStrokes.values.toList();
  List<Stroke> get studentPrivateActiveStrokeList =>
      _studentPrivateActiveStrokes.values.toList();
  String? get backgroundUrl => _backgroundUrl;
  double? get pdfWidth => _pdfWidth;
  double? get pdfHeight => _pdfHeight;
  bool get isDrawingMode => _isDrawingMode;
  Color get currentColor => _currentColor;
  double get currentWidth => _currentWidth;
  bool get isSocketConnected => _isSocketConnected;
  String? get userId => _userId;
  String? get roomId => _roomId;
  String? get localDraftKey => _localDraftKey;

  /// 내 모든 선들 (완성 + 진행중)
  List<Stroke> get myAllStrokes {
    return [..._myStrokes.values, ..._myActiveStrokes.values];
  }

  /// 다른 사람들의 모든 선들
  List<Stroke> get othersAllStrokes {
    return [..._othersStrokes.values, ..._othersActiveStrokes.values];
  }

  /// 전체 선들 (내 것 + 남의 것)
  List<Stroke> get allStrokes {
    return [...myAllStrokes, ...othersAllStrokes];
  }

  DrawingProvider() {
    _setupNativeDrawingListener();
    _setupSocketListeners();
  }

  Future<void> openDocument({required String draftKey}) async {
    _localDraftKey = draftKey;
    _clearAllInMemory(notify: false);
    await _restoreFromLocalDraft();
    notifyListeners();
  }

  Future<void> _restoreFromLocalDraft() async {
    final draftKey = _localDraftKey;
    if (draftKey == null || draftKey.isEmpty) return;
    final payload = await _eventStore.loadDraft(draftKey);
    if (payload == null) return;

    _isHydratingLocalDraft = true;
    try {
      _myStrokes
        ..clear()
        ..addAll(_deserializeStrokeMap(payload['myStrokes']));
      _studentPrivateStrokes
        ..clear()
        ..addAll(_deserializeStrokeMap(payload['studentPrivateStrokes']));
      _myActiveStrokes.clear();
      _studentPrivateActiveStrokes.clear();
    } finally {
      _isHydratingLocalDraft = false;
    }
  }

  Future<void> _persistLocalDraft() async {
    final draftKey = _localDraftKey;
    if (draftKey == null || draftKey.isEmpty) return;
    await _eventStore.saveDraft(
      draftKey: draftKey,
      payload: {
        'myStrokes': _serializeStrokeMap(_myStrokes),
        'studentPrivateStrokes': _serializeStrokeMap(_studentPrivateStrokes),
      },
    );
  }

  void _persistLocalDraftSoon() {
    if (_isHydratingLocalDraft || _localDraftKey == null) return;
    unawaited(_persistLocalDraft());
  }

  Future<void> clearLocalDraft() async {
    final draftKey = _localDraftKey;
    if (draftKey == null || draftKey.isEmpty) return;
    await _eventStore.deleteDraft(draftKey);
    _clearAllInMemory();
  }

  void _clearAllInMemory({bool notify = true}) {
    _myStrokes.clear();
    _myActiveStrokes.clear();
    _othersStrokes.clear();
    _othersActiveStrokes.clear();
    _studentPrivateStrokes.clear();
    _studentPrivateActiveStrokes.clear();
    if (notify) {
      notifyListeners();
    }
  }

  Map<String, dynamic> _serializeStrokeMap(Map<int, Stroke> source) {
    return source.map((strokeId, stroke) {
      return MapEntry(
        '$strokeId',
        {
          'strokeId': stroke.strokeId,
          'color': '#${stroke.color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
          'width': stroke.width,
          'points': stroke.points.map((point) => point.toJson()).toList(),
          'refinedPoints': stroke.refinedPoints?.map((point) => point.toJson()).toList(),
        },
      );
    });
  }

  Map<int, Stroke> _deserializeStrokeMap(dynamic raw) {
    if (raw is! Map) return {};
    final result = <int, Stroke>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final json = Map<String, dynamic>.from(value);
      final strokeId = (json['strokeId'] as num?)?.toInt();
      final width = (json['width'] as num?)?.toDouble();
      final pointsRaw = json['points'] as List<dynamic>?;
      if (strokeId == null || width == null || pointsRaw == null || pointsRaw.isEmpty) {
        continue;
      }
      final points = pointsRaw
          .whereType<Map>()
          .map((point) => DrawPoint.fromJson(Map<String, dynamic>.from(point)))
          .toList();
      if (points.isEmpty) continue;
      final refinedRaw = json['refinedPoints'] as List<dynamic>?;
      final refinedPoints = refinedRaw
          ?.whereType<Map>()
          .map((point) => DrawPoint.fromJson(Map<String, dynamic>.from(point)))
          .toList();

      result[strokeId] = Stroke(
        strokeId: strokeId,
        color: _parseSnapshotColor(json['color'] as String?),
        width: width,
        points: points,
        refinedPoints: refinedPoints == null || refinedPoints.isEmpty ? null : refinedPoints,
      );
    }
    return result;
  }

  /// ===============================
  /// Socket.IO 연결
  /// ===============================
  Future<void> connectSocket({
    required String serverUrl,
    required String userId,
    required String roomId,
    required bool isTeacher,
    String? classId,
    String? materialId,
  }) async {
    _userId = userId;
    _roomId = roomId;
    _isTeacher = isTeacher;

    try {
      await _socketService.connect(
        serverUrl: serverUrl,
        userId: userId,
        roomId: roomId,
        isTeacher: isTeacher,
        classId: classId,
        materialId: materialId,
      );

      _isSocketConnected = _socketService.isConnected;
      debugPrint(
        '[socket][provider] connect requested roomId=$roomId userId=$userId materialId=$materialId connected=$_isSocketConnected',
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to connect socket: $e');
      _isSocketConnected = false;
      notifyListeners();
    }
  }

  /// ===============================
  /// Socket.IO 이벤트 리스너 설정
  /// ===============================
  void _setupSocketListeners() {
    // 판서 이벤트 수신
    _socketService.onDrawEventReceived = (event) {
      _handleReceivedDrawEvent(event);
    };

    // 연결 상태
    _socketService.onConnected = () {
      _isSocketConnected = true;
      notifyListeners();
      debugPrint('✅ Socket connected');
    };

    _socketService.onDisconnected = () {
      _isSocketConnected = false;
      notifyListeners();
      debugPrint('❌ Socket disconnected');
    };

    _socketService.onError = (error) {
      debugPrint('[socket][provider] error: $error');
    };

    // 사용자 입/퇴장
    _socketService.onUserJoined = (userId) {
      debugPrint('👤 User joined: $userId');
    };

    _socketService.onUserLeft = (userId) {
      debugPrint('👋 User left: $userId');
    };
  }

  /// ===============================
  /// Native drawing 이벤트 수신 설정
  /// ===============================
  void _setupNativeDrawingListener() {
    _nativeDrawEventSubscription = NativeDrawingBridge.drawEvents.listen(
      (payload) {
        try {
          final event = DrawEvent.fromJson(payload);
          _logNormalized(event, source: 'native');
          _handleLocalNativeEvent(event);
        } catch (e) {
          debugPrint('[draw][error] Native event parse failed: $e payload=$payload');
        }
      },
      onError: (error, stackTrace) {
        debugPrint('[draw][error] Native event stream failed: $error');
      },
    );
  }

  /// ===============================
  /// 수신된 판서 이벤트 처리 (다른 사람의 펜)
  /// ===============================
  void _handleReceivedDrawEvent(DrawEvent event) {
    switch (event.eventType) {
      case DrawEventType.drawStart:
        _handleOthersDrawStart(event);
        break;
      case DrawEventType.drawMove:
        _handleOthersDrawMove(event);
        break;
      case DrawEventType.drawEnd:
        _handleOthersDrawEnd(event);
        break;
      case DrawEventType.undo:
        _handleOthersUndo(event);
        break;
      case DrawEventType.eraser:
        _handleOthersEraser(event);
        break;
      case DrawEventType.clearAll:
        _handleRemoteClearAll();
        break;
    }
  }

  void _handleLocalNativeEvent(DrawEvent event) {
    if (event.eventType == DrawEventType.drawEnd &&
        (event.points == null || event.points!.isEmpty)) {
      return;
    }
    switch (event.eventType) {
      case DrawEventType.drawStart:
        _handleMyDrawStart(event);
        break;
      case DrawEventType.drawMove:
        _handleMyDrawMove(event);
        break;
      case DrawEventType.drawEnd:
        _handleMyDrawEnd(event);
        break;
      case DrawEventType.undo:
        _handleMyUndo(event);
        break;
      case DrawEventType.eraser:
        if (event.strokeId == 0) {
          clear();
          return;
        }
        _handleMyUndo(event);
        break;
      case DrawEventType.clearAll:
        clear();
        return;
    }

    if (_socketService.isConnected && _userId != null) {
      switch (event.eventType) {
        case DrawEventType.drawStart:
        case DrawEventType.drawMove:
        case DrawEventType.drawEnd:
          _socketService.sendDrawEvent(event, _userId!);
          break;
        case DrawEventType.undo:
          _socketService.sendUndo(event.strokeId, _userId!);
          break;
        case DrawEventType.eraser:
          _socketService.sendEraser(event.strokeId, _userId!);
          break;
        case DrawEventType.clearAll:
          _socketService.sendClearAll(_userId!);
          break;
      }
    }
  }

  void debugInjectDrawEvent(Map<String, dynamic> payload) {
    final event = DrawEvent.fromJson(payload);
    _logNormalized(event, source: 'debug');
    _handleReceivedDrawEvent(event);
  }

  void _logNormalized(DrawEvent event, {required String source}) {
    if (!kDebugMode && event.eventType == DrawEventType.drawMove) return;
    switch (event.eventType) {
      case DrawEventType.drawStart:
        if (event.point == null) return;
        debugPrint(
          '[draw][$source] ds sId=${event.strokeId} x=${event.point!.x} y=${event.point!.y} c=${event.color} w=${event.width}',
        );
        break;
      case DrawEventType.drawMove:
        if (event.point == null) return;
        debugPrint(
          '[draw][$source] dm sId=${event.strokeId} x=${event.point!.x} y=${event.point!.y}',
        );
        break;
      case DrawEventType.drawEnd:
        final points = event.points ?? const <DrawPoint>[];
        final first = points.isNotEmpty ? points.first : null;
        final last = points.isNotEmpty ? points.last : null;
        debugPrint(
          '[draw][$source] de sId=${event.strokeId} pts=${points.length} first=${first?.x},${first?.y} last=${last?.x},${last?.y}',
        );
        break;
      case DrawEventType.undo:
      case DrawEventType.eraser:
        debugPrint('[draw][$source] ${event.eventType.code} sId=${event.strokeId}');
        break;
      case DrawEventType.clearAll:
        debugPrint('[draw][$source] cl');
        break;
    }
  }

  /// 다른 사람의 draw_start
  void _handleOthersDrawStart(DrawEvent event) {
    if (event.point == null) return;

    final stroke = Stroke(
      strokeId: event.strokeId,
      color: event.color ?? Colors.blue, // 다른 사람은 파란색
      width: event.width ?? 2.5,
      points: [event.point!],
    );

    _othersActiveStrokes[event.strokeId] = stroke;
    notifyListeners();
  }

  /// 다른 사람의 draw_move
  void _handleOthersDrawMove(DrawEvent event) {
    if (event.point == null) return;

    final stroke = _othersActiveStrokes[event.strokeId];
    if (stroke == null) {
      debugPrint('Warning: draw_move for unknown stroke ${event.strokeId}');
      return;
    }

    final updatedPoints = [...stroke.points, event.point!];
    _othersActiveStrokes[event.strokeId] = stroke.copyWith(points: updatedPoints);

    if (updatedPoints.length % 3 == 0) {
      notifyListeners();
    }
  }

  /// 다른 사람의 draw_end
  void _handleOthersDrawEnd(DrawEvent event) {
    final stroke = _othersActiveStrokes.remove(event.strokeId);
    if (stroke == null) {
      debugPrint('Warning: draw_end for unknown stroke ${event.strokeId}');
      return;
    }

    final finalStroke = event.points != null && event.points!.isNotEmpty
        ? stroke.withRefinedPoints(event.points!)
        : stroke;

    _othersStrokes[event.strokeId] = finalStroke;
    notifyListeners();
  }

  /// 다른 사람의 undo
  void _handleOthersUndo(DrawEvent event) {
    final removed = _othersStrokes.remove(event.strokeId) != null ||
        _othersActiveStrokes.remove(event.strokeId) != null;

    if (removed) {
      notifyListeners();
    }
  }

  /// 다른 사람의 eraser
  void _handleOthersEraser(DrawEvent event) {
    if (event.strokeId == 0) {
      _othersStrokes.clear();
      _othersActiveStrokes.clear();
      notifyListeners();
      return;
    }
    final removed = _othersStrokes.remove(event.strokeId) != null ||
        _othersActiveStrokes.remove(event.strokeId) != null;

    if (removed) {
      notifyListeners();
    }
  }

  void _handleRemoteClearAll() {
    _myStrokes.clear();
    _myActiveStrokes.clear();
    _othersStrokes.clear();
    _othersActiveStrokes.clear();
    _persistLocalDraftSoon();
    notifyListeners();
  }

  /// ===============================
  /// 내 판서 이벤트 처리 (로컬)
  /// ===============================
  void _handleMyDrawStart(DrawEvent event) {
    if (event.point == null) return;

    _lastNativeColor = event.color ?? _lastNativeColor ?? _currentColor;
    _lastNativeWidth = event.width ?? _lastNativeWidth ?? _currentWidth;
    final stroke = Stroke(
      strokeId: event.strokeId,
      color: _lastNativeColor ?? Colors.black,
      width: _lastNativeWidth ?? 2.5,
      points: [event.point!],
    );

    _myActiveStrokes[event.strokeId] = stroke;
    notifyListeners();
  }

  void _handleMyDrawMove(DrawEvent event) {
    if (event.point == null) return;

    final stroke = _myActiveStrokes[event.strokeId];
    if (stroke == null) {
      final fallbackColor = _lastNativeColor ?? _currentColor;
      final fallbackWidth = _lastNativeWidth ?? _currentWidth;
      _myActiveStrokes[event.strokeId] = Stroke(
        strokeId: event.strokeId,
        color: fallbackColor,
        width: fallbackWidth,
        points: [event.point!],
      );
      notifyListeners();
      return;
    }

    final updatedPoints = [...stroke.points, event.point!];
    _myActiveStrokes[event.strokeId] = stroke.copyWith(points: updatedPoints);

    if (updatedPoints.length % 3 == 0) {
      notifyListeners();
    }
  }

  void _handleMyDrawEnd(DrawEvent event) {
    final stroke = _myActiveStrokes.remove(event.strokeId);
    if (stroke == null) {
      if (event.points == null || event.points!.isEmpty) return;
      final fallbackColor = _lastNativeColor ?? _currentColor;
      final fallbackWidth = _lastNativeWidth ?? _currentWidth;
      _myStrokes[event.strokeId] = Stroke(
        strokeId: event.strokeId,
        color: fallbackColor,
        width: fallbackWidth,
        points: event.points!,
      );
      _persistLocalDraftSoon();
      notifyListeners();
      return;
    }

    final finalStroke = event.points != null && event.points!.isNotEmpty
        ? stroke.withRefinedPoints(event.points!)
        : stroke;

    _myStrokes[event.strokeId] = finalStroke;
    _persistLocalDraftSoon();
    notifyListeners();
  }

  void _handleMyUndo(DrawEvent event) {
    final removed = _myStrokes.remove(event.strokeId) != null ||
        _myActiveStrokes.remove(event.strokeId) != null;

    if (!removed) {
      debugPrint(
        '[draw][warn] my undo/eraser target not found sId=${event.strokeId} '
        'myCompleted=${_myStrokes.length} myActive=${_myActiveStrokes.length}',
      );
      return;
    }
    _persistLocalDraftSoon();
    notifyListeners();
  }

  /// ===============================
  /// 설정 관련
  /// ===============================
  void setBackgroundUrl(String? url) {
    if (_backgroundUrl != url) {
      _backgroundUrl = url;
      notifyListeners();
    }
  }

  void setPdfPageSize({required double width, required double height}) {
    if (_pdfWidth != width || _pdfHeight != height) {
      _pdfWidth = width;
      _pdfHeight = height;
    }
  }

  void setDrawingMode(bool enabled) {
    if (_isDrawingMode != enabled) {
      _isDrawingMode = enabled;
      notifyListeners();
    }
  }

  Future<void> syncMyStrokesFromNativeSnapshot() async {
    final snapshot = await NativeDrawingBridge.exportDrawingSnapshot();
    final restoredStrokes = <int, Stroke>{};
    Color? restoredLastColor;
    double? restoredLastWidth;

    for (final stroke in snapshot) {
      final strokeId = (stroke['sId'] as num?)?.toInt();
      final width = (stroke['w'] as num?)?.toDouble();
      final colorHex = stroke['c'] as String?;
      final rawPoints = stroke['pts'] as List<dynamic>?;
      if (strokeId == null || width == null || rawPoints == null || rawPoints.isEmpty) {
        continue;
      }

      final points = rawPoints
          .whereType<Map>()
          .map((point) => DrawPoint.fromJson(Map<String, dynamic>.from(point)))
          .toList();
      if (points.isEmpty) {
        continue;
      }

      final color = _parseSnapshotColor(colorHex);
      restoredStrokes[strokeId] = Stroke(
        strokeId: strokeId,
        color: color,
        width: width,
        points: points,
      );
      restoredLastColor = color;
      restoredLastWidth = width;
    }

    // iOS에서 drawing mode를 다시 켰다가 바로 끄면 새 native view가 빈 스냅샷을
    // 반환할 수 있어 기존 stroke를 유지한다.
    if (restoredStrokes.isEmpty) {
      debugPrint(
        '[draw][native-sync] empty snapshot -> keep existing ${_myStrokes.length} strokes',
      );
      return;
    }

    // 기존 Flutter stroke를 유지한 채, native snapshot 결과만 누적 반영한다.
    // (drawing mode on/off 반복 시 과거 stroke가 사라지지 않아야 함)
    _myStrokes.addAll(restoredStrokes);
    _myActiveStrokes.removeWhere((strokeId, _) => restoredStrokes.containsKey(strokeId));
    _lastNativeColor = restoredLastColor ?? _lastNativeColor;
    _lastNativeWidth = restoredLastWidth ?? _lastNativeWidth;

    debugPrint('[draw][native-sync] restored ${_myStrokes.length} strokes from native snapshot');
    notifyListeners();
  }

  void setColor(Color color) {
    if (_currentColor != color) {
      _currentColor = color;
    }
  }

  void setWidth(double width) {
    if (_currentWidth != width) {
      _currentWidth = width;
    }
  }

  Color _parseSnapshotColor(String? hexColor) {
    if (hexColor == null) {
      return _lastNativeColor ?? _currentColor;
    }
    final hex = hexColor.replaceAll('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    return _lastNativeColor ?? _currentColor;
  }

  /// ===============================
  /// 내가 그릴 때: 로컬 + 소켓 전송
  /// ===============================
  int _nextStrokeId() {
    _strokeIdSeed += 1;
    return _strokeIdSeed;
  }

  int sendDrawStart(DrawPoint point) {
    final strokeId = _nextStrokeId();

    final event = DrawEvent(
      eventType: DrawEventType.drawStart,
      strokeId: strokeId,
      point: point,
      color: _currentColor,
      width: _currentWidth,
    );

    // 로컬에 먼저 표시
    _handleMyDrawStart(event);

    // Socket.IO로 전송
    if (_isSocketConnected && _userId != null) {
      _socketService.sendDrawEvent(event, _userId!);
    } else {
      debugPrint(
        '[draw][local] Socket not ready for drawStart sId=$strokeId connected=$_isSocketConnected userId=$_userId roomId=$_roomId',
      );
    }

    // MethodChannel로도 전송 (네이티브)
    try {
      NativeDrawingBridge.sendDrawEvent(event.toJson());
    } catch (e) {
      debugPrint('[draw][error] Native send drawStart failed: $e');
    }

    return strokeId;
  }

  void sendDrawMove(int strokeId, DrawPoint point) {
    final event = DrawEvent(
      eventType: DrawEventType.drawMove,
      strokeId: strokeId,
      point: point,
    );

    // 로컬에 먼저 표시
    _handleMyDrawMove(event);

    // Socket.IO로 전송
    if (_isSocketConnected && _userId != null) {
      _socketService.sendDrawEvent(event, _userId!);
    }

    // MethodChannel로도 전송
    try {
      NativeDrawingBridge.sendDrawEvent(event.toJson());
    } catch (e) {
      debugPrint('[draw][error] Native send drawMove failed: $e');
    }
  }

  void sendDrawEnd(int strokeId, List<DrawPoint> points) {
    final copiedPoints = List<DrawPoint>.from(points);
    final event = DrawEvent(
      eventType: DrawEventType.drawEnd,
      strokeId: strokeId,
      points: copiedPoints,
    );

    // 로컬에 먼저 표시
    _handleMyDrawEnd(event);

    // Socket.IO로 전송
    if (_isSocketConnected && _userId != null) {
      _socketService.sendDrawEvent(event, _userId!);
    } else {
      debugPrint(
        '[draw][local] Socket not ready for drawEnd sId=$strokeId connected=$_isSocketConnected userId=$_userId roomId=$_roomId',
      );
    }

    // MethodChannel로도 전송
    try {
      NativeDrawingBridge.sendDrawEvent(event.toJson());
    } catch (e) {
      debugPrint('[draw][error] Native send drawEnd failed: $e');
    }
  }

  void sendUndo(int strokeId) {
    final event = DrawEvent(
      eventType: DrawEventType.undo,
      strokeId: strokeId,
    );

    // 로컬에 먼저 실행
    _handleMyUndo(event);

    // Socket.IO로 전송
    if (_isSocketConnected && _userId != null) {
      _socketService.sendUndo(strokeId, _userId!);
    } else {
      debugPrint(
        '[draw][local] Socket not ready for undo sId=$strokeId connected=$_isSocketConnected userId=$_userId roomId=$_roomId',
      );
    }

    // MethodChannel로도 전송
    try {
      NativeDrawingBridge.sendDrawEvent(event.toJson());
    } catch (e) {
      debugPrint('[draw][error] Native send undo failed: $e');
    }
  }

  /// 전체 초기화
  void clear() {
    _clearAllInMemory(notify: false);
    _persistLocalDraftSoon();
    notifyListeners();

    // Socket.IO로 전송 (교사만)
    if (_isTeacher && _isSocketConnected && _userId != null) {
      _socketService.sendClearAll(_userId!);
    }
  }

  /// Socket 연결 해제
  void disconnectSocket() {
    _socketService.disconnect();
    _isSocketConnected = false;
    notifyListeners();
  }

  /// ===============================
  /// 학생 개인 필기 (로컬 전용, 서버 미전송)
  /// ===============================
  int startStudentPrivateStroke(DrawPoint point) {
    final strokeId = _nextStrokeId();
    final stroke = Stroke(
      strokeId: strokeId,
      color: _currentColor,
      width: _currentWidth,
      points: [point],
    );
    _studentPrivateActiveStrokes[strokeId] = stroke;
    notifyListeners();
    return strokeId;
  }

  void appendStudentPrivatePoint(int strokeId, DrawPoint point) {
    final stroke = _studentPrivateActiveStrokes[strokeId];
    if (stroke == null) return;
    final updatedPoints = [...stroke.points, point];
    _studentPrivateActiveStrokes[strokeId] =
        stroke.copyWith(points: updatedPoints);
    if (updatedPoints.length % 3 == 0) {
      notifyListeners();
    }
  }

  void endStudentPrivateStroke(int strokeId, List<DrawPoint> points) {
    final stroke = _studentPrivateActiveStrokes.remove(strokeId);
    if (stroke == null) return;
    final copiedPoints = List<DrawPoint>.from(points);
    final finalStroke = copiedPoints.isNotEmpty
        ? stroke.withRefinedPoints(copiedPoints)
        : stroke;
    _studentPrivateStrokes[strokeId] = finalStroke;
    _persistLocalDraftSoon();
    notifyListeners();
  }

  void clearStudentPrivateStrokes() {
    _studentPrivateStrokes.clear();
    _studentPrivateActiveStrokes.clear();
    _persistLocalDraftSoon();
    notifyListeners();
  }

  @override
  void dispose() {
    _nativeDrawEventSubscription?.cancel();
    disconnectSocket();
    super.dispose();
  }
}
