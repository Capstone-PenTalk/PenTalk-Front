import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/drawing_models.dart';
import '../native_drawing.dart';
import '../services/socket_service.dart';
import '../services/session_storage.dart';

/// ===============================
/// 판서 데이터 Provider (Socket.IO + Native 통합)
/// ===============================
class DrawingProvider extends ChangeNotifier {
  final SocketService _socketService = SocketService();
  StreamSubscription<Map<String, dynamic>>? _nativeDrawEventSubscription;

  SocketService get socketService => _socketService;

  // 내 펜
  final Map<int, Stroke> _myStrokes = {};
  final Map<int, Stroke> _myActiveStrokes = {};

  // 상대 펜
  final Map<int, Stroke> _othersStrokes = {};
  final Map<int, Stroke> _othersActiveStrokes = {};

  // 학생 개인 필기 (로컬 전용, 서버 미전송 / 팀원 추가)
  final Map<int, Stroke> _studentPrivateStrokes = {};
  final Map<int, Stroke> _studentPrivateActiveStrokes = {};

  // 배경
  String? _backgroundUrl;
  double? _pdfWidth;
  double? _pdfHeight;

  // 그리기 모드
  bool _isDrawingMode = false;
  Color _currentColor = Colors.black;
  double _currentWidth = 2.5;
  Color? _lastNativeColor;
  double? _lastNativeWidth;

  // 사용자 정보
  String? _userId;
  String? _roomId;
  bool _isTeacher = false;

  // 소켓 상태
  bool _isSocketConnected = false;
  int _strokeIdSeed = DateTime.now().microsecondsSinceEpoch;

  // lastTick (자동 재join용)
  int? _lastTick;
  Timer? _tickSaveTimer;

  int? get lastTick => _lastTick;

  // Getters
  Map<int, Stroke> get myStrokes => _myStrokes;
  Map<int, Stroke> get myActiveStrokes => _myActiveStrokes;
  Map<int, Stroke> get othersStrokes => _othersStrokes;
  Map<int, Stroke> get othersActiveStrokes => _othersActiveStrokes;
  Map<int, Stroke> get studentPrivateStrokes => _studentPrivateStrokes;
  Map<int, Stroke> get studentPrivateActiveStrokes => _studentPrivateActiveStrokes;
  String? get backgroundUrl => _backgroundUrl;
  double? get pdfWidth => _pdfWidth;
  double? get pdfHeight => _pdfHeight;
  bool get isDrawingMode => _isDrawingMode;
  Color get currentColor => _currentColor;
  double get currentWidth => _currentWidth;
  bool get isSocketConnected => _isSocketConnected;
  String? get userId => _userId;
  String? get roomId => _roomId;

  List<Stroke> get myAllStrokes =>
      [..._myStrokes.values, ..._myActiveStrokes.values];
  List<Stroke> get othersAllStrokes =>
      [..._othersStrokes.values, ..._othersActiveStrokes.values];
  List<Stroke> get allStrokes => [...myAllStrokes, ...othersAllStrokes];

  DrawingProvider() {
    _setupNativeDrawingListener();
    _setupSocketListeners();
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
    String? materialTitle,   // 세션 저장용 (내 코드)
    String? backgroundUrl,   // 세션 저장용 (내 코드)
  }) async {
    _userId = userId;
    _roomId = roomId;
    _isTeacher = isTeacher;

    // 저장된 lastTick 로드 (자동 재join용)
    final session = await SessionStorage.getLastSession();
    if (session?.lastTick != null) {
      _lastTick = session!.lastTick;
      debugPrint('📥 LastTick loaded: $_lastTick');
    }

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
      notifyListeners();

      _setupPresenceListeners();

      // 세션 정보 저장 (materialTitle 있을 때만)
      if (materialTitle != null) {
        await SessionStorage.saveSession(
          sessionId: roomId,
          roomId: roomId,
          role: isTeacher ? 'teacher' : 'student',
          materialTitle: materialTitle,
          backgroundUrl: backgroundUrl,
          serverUrl: serverUrl,
          lastTick: _lastTick,
        );
      }

      _startTickSaveTimer();
    } catch (e) {
      debugPrint('Failed to connect socket: $e');
      _isSocketConnected = false;
      notifyListeners();
    }
  }

  void _startTickSaveTimer() {
    _tickSaveTimer?.cancel();
    _tickSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_lastTick != null) SessionStorage.updateLastTick(_lastTick!);
    });
  }

  void _stopTickSaveTimer() {
    _tickSaveTimer?.cancel();
    _tickSaveTimer = null;
  }

  /// ===============================
  /// Socket 이벤트 리스너
  /// ===============================
  void _setupSocketListeners() {
    _socketService.onDrawEventReceived = _handleReceivedDrawEvent;

    _socketService.onConnected = () {
      _isSocketConnected = true;
      notifyListeners();
      debugPrint('✅ Socket connected');
    };

    // JOIN_SUCCESS → 300ms 후 sync:request (최초 & 재접속 모두)
    _socketService.onRoomJoined = (data) {
      debugPrint('✅ Room joined, scheduling sync:request...');
      Future.delayed(const Duration(milliseconds: 300), () {
        _socketService.requestSync(lastTick: _lastTick);
        debugPrint('📤 sync:request sent (lastTick: $_lastTick)');
      });
    };

    _socketService.onDisconnected = () {
      _isSocketConnected = false;
      notifyListeners();
    };

    _socketService.onError = (error) {
      debugPrint('[socket][provider] error: $error');
    };

    _socketService.onUserJoined = (userId) => debugPrint('👤 User joined: $userId');
    _socketService.onUserLeft = (userId) => debugPrint('👋 User left: $userId');
    _socketService.onSessionEnded = _handleSessionEnded;
  }

  void _setupPresenceListeners() {
    _socketService.setupPresenceListeners();
  }

  /// ===============================
  /// Native drawing 이벤트
  /// ===============================
  void _setupNativeDrawingListener() {
    _nativeDrawEventSubscription = NativeDrawingBridge.drawEvents.listen(
          (payload) {
        try {
          final event = DrawEvent.fromJson(payload);
          _logNormalized(event, source: 'native');
          _handleLocalNativeEvent(event);
        } catch (e) {
          debugPrint('[draw][error] Native event parse failed: $e');
        }
      },
      onError: (error) => debugPrint('[draw][error] Native stream: $error'),
    );
  }

  /// ===============================
  /// 수신된 이벤트 처리 (다른 사람)
  /// ===============================
  void _handleReceivedDrawEvent(DrawEvent event) {
    switch (event.eventType) {
      case DrawEventType.drawStart: _handleOthersDrawStart(event); break;
      case DrawEventType.drawMove: _handleOthersDrawMove(event); break;
      case DrawEventType.drawEnd: _handleOthersDrawEnd(event); break;
      case DrawEventType.undo: _handleOthersUndo(event); break;
      case DrawEventType.eraser: _handleOthersEraser(event); break;
      case DrawEventType.clearAll: _handleRemoteClearAll(); break;
    }
  }

  void _handleLocalNativeEvent(DrawEvent event) {
    if (event.eventType == DrawEventType.drawEnd &&
        (event.points == null || event.points!.isEmpty)) return;

    switch (event.eventType) {
      case DrawEventType.drawStart: _handleMyDrawStart(event); break;
      case DrawEventType.drawMove: _handleMyDrawMove(event); break;
      case DrawEventType.drawEnd: _handleMyDrawEnd(event); break;
      case DrawEventType.undo: _handleMyUndo(event); break;
      case DrawEventType.eraser:
        if (event.strokeId == 0) { clear(); return; }
        _handleMyUndo(event);
        break;
      case DrawEventType.clearAll: clear(); return;
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
          _socketService.sendClearAll(_userId!);
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
    debugPrint('[draw][$source] ${event.eventType.code} sId=${event.strokeId}');
  }

  // Others 핸들러
  void _handleOthersDrawStart(DrawEvent event) {
    if (event.point == null) return;
    _othersActiveStrokes[event.strokeId] = Stroke(
      strokeId: event.strokeId,
      color: event.color ?? Colors.blue,
      width: event.width ?? 2.5,
      points: [event.point!],
    );
    notifyListeners();
  }

  void _handleOthersDrawMove(DrawEvent event) {
    if (event.point == null) return;
    final stroke = _othersActiveStrokes[event.strokeId];
    if (stroke == null) return;
    final updated = [...stroke.points, event.point!];
    _othersActiveStrokes[event.strokeId] = stroke.copyWith(points: updated);
    if (updated.length % 3 == 0) notifyListeners();
  }

  void _handleOthersDrawEnd(DrawEvent event) {
    final stroke = _othersActiveStrokes.remove(event.strokeId);
    if (stroke == null) return;

    var final_ = stroke;
    if (event.points != null && event.points!.isNotEmpty) {
      final_ = final_.copyWith(refinedPoints: event.points);
    }
    if (event.color != null) final_ = final_.copyWith(color: event.color);
    if (event.width != null) final_ = final_.copyWith(width: event.width);

    _othersStrokes[event.strokeId] = final_;

    if (event.tick != null) {
      _lastTick = event.tick;
    }
    notifyListeners();
  }

  void _handleOthersUndo(DrawEvent event) {
    final removed = _othersStrokes.remove(event.strokeId) != null ||
        _othersActiveStrokes.remove(event.strokeId) != null;
    if (removed) notifyListeners();
  }

  void _handleOthersEraser(DrawEvent event) {
    if (event.strokeId == 0) {
      _othersStrokes.clear();
      _othersActiveStrokes.clear();
      notifyListeners();
      return;
    }
    final removed = _othersStrokes.remove(event.strokeId) != null ||
        _othersActiveStrokes.remove(event.strokeId) != null;
    if (removed) notifyListeners();
  }

  void _handleRemoteClearAll() {
    _myStrokes.clear();
    _myActiveStrokes.clear();
    _othersStrokes.clear();
    _othersActiveStrokes.clear();
    notifyListeners();
  }

  // My 핸들러
  void _handleMyDrawStart(DrawEvent event) {
    if (event.point == null) return;
    _lastNativeColor = event.color ?? _lastNativeColor ?? _currentColor;
    _lastNativeWidth = event.width ?? _lastNativeWidth ?? _currentWidth;
    _myActiveStrokes[event.strokeId] = Stroke(
      strokeId: event.strokeId,
      color: _lastNativeColor ?? Colors.black,
      width: _lastNativeWidth ?? 2.5,
      points: [event.point!],
    );
    notifyListeners();
  }

  void _handleMyDrawMove(DrawEvent event) {
    if (event.point == null) return;
    final stroke = _myActiveStrokes[event.strokeId];
    if (stroke == null) {
      _myActiveStrokes[event.strokeId] = Stroke(
        strokeId: event.strokeId,
        color: _lastNativeColor ?? _currentColor,
        width: _lastNativeWidth ?? _currentWidth,
        points: [event.point!],
      );
      notifyListeners();
      return;
    }
    final updated = [...stroke.points, event.point!];
    _myActiveStrokes[event.strokeId] = stroke.copyWith(points: updated);
    if (updated.length % 3 == 0) notifyListeners();
  }

  void _handleMyDrawEnd(DrawEvent event) {
    final stroke = _myActiveStrokes.remove(event.strokeId);

    // stroke 없으면 fallback으로 생성 (팀원 코드)
    if (stroke == null) {
      if (event.points == null || event.points!.isEmpty) return;
      _myStrokes[event.strokeId] = Stroke(
        strokeId: event.strokeId,
        color: _lastNativeColor ?? _currentColor,
        width: _lastNativeWidth ?? _currentWidth,
        points: event.points!,
      );
      notifyListeners();
      return;
    }

    var final_ = stroke;
    if (event.points != null && event.points!.isNotEmpty) {
      final_ = final_.copyWith(refinedPoints: event.points);
    }
    // de 이벤트의 color/width 반영 (내 코드 - 서버 전송에 필요)
    if (event.color != null) final_ = final_.copyWith(color: event.color);
    if (event.width != null) final_ = final_.copyWith(width: event.width);

    _myStrokes[event.strokeId] = final_;
    notifyListeners();
  }

  void _handleMyUndo(DrawEvent event) {
    final removed = _myStrokes.remove(event.strokeId) != null ||
        _myActiveStrokes.remove(event.strokeId) != null;
    if (removed) notifyListeners();
  }

  /// ===============================
  /// 설정
  /// ===============================
  void setBackgroundUrl(String? url) {
    if (_backgroundUrl != url) {
      _backgroundUrl = url;
      notifyListeners();
    }
  }

  void setPdfPageSize({required double width, required double height}) {
    _pdfWidth = width;
    _pdfHeight = height;
  }

  void setDrawingMode(bool enabled) {
    if (_isDrawingMode != enabled) {
      _isDrawingMode = enabled;
      notifyListeners();
    }
  }

  void setColor(Color color) {
    if (_currentColor != color) {
      _currentColor = color;
      notifyListeners();
    }
  }

  void setWidth(double width) {
    if (_currentWidth != width) {
      _currentWidth = width;
      notifyListeners();
    }
  }

  Color _parseSnapshotColor(String? hexColor) {
    if (hexColor == null) return _lastNativeColor ?? _currentColor;
    final hex = hexColor.replaceAll('#', '');
    if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
    return _lastNativeColor ?? _currentColor;
  }

  /// Native 스냅샷 동기화 (팀원 코드)
  Future<void> syncMyStrokesFromNativeSnapshot() async {
    final snapshot = await NativeDrawingBridge.exportDrawingSnapshot();
    final restored = <int, Stroke>{};
    Color? restoredLastColor;
    double? restoredLastWidth;

    for (final stroke in snapshot) {
      final strokeId = (stroke['sId'] as num?)?.toInt();
      final width = (stroke['w'] as num?)?.toDouble();
      final colorHex = stroke['c'] as String?;
      final rawPoints = stroke['pts'] as List<dynamic>?;
      if (strokeId == null || width == null || rawPoints == null || rawPoints.isEmpty) continue;

      final points = rawPoints
          .whereType<Map>()
          .map((p) => DrawPoint.fromJson(Map<String, dynamic>.from(p)))
          .toList();
      if (points.isEmpty) continue;

      final color = _parseSnapshotColor(colorHex);
      restored[strokeId] = Stroke(strokeId: strokeId, color: color, width: width, points: points);
      restoredLastColor = color;
      restoredLastWidth = width;
    }

    if (restored.isEmpty) return;

    _myStrokes.addAll(restored);
    _myActiveStrokes.removeWhere((id, _) => restored.containsKey(id));
    _lastNativeColor = restoredLastColor ?? _lastNativeColor;
    _lastNativeWidth = restoredLastWidth ?? _lastNativeWidth;
    notifyListeners();
  }

  /// ===============================
  /// 내가 그릴 때: 로컬 + 소켓 전송
  /// ===============================
  int _nextStrokeId() => ++_strokeIdSeed;

  int sendDrawStart(DrawPoint point) {
    final strokeId = _nextStrokeId();

    final event = DrawEvent(
      eventType: DrawEventType.drawStart,
      strokeId: strokeId,
      point: point,
      color: _currentColor,
      width: _currentWidth,
    );

    _handleMyDrawStart(event);

    if (_isSocketConnected && _userId != null) {
      _socketService.sendDrawEvent(event, _userId!);
    }

    try { NativeDrawingBridge.sendDrawEvent(event.toJson()); } catch (_) {}

    return strokeId;
  }

  void sendDrawMove(int strokeId, DrawPoint point) {
    final event = DrawEvent(
      eventType: DrawEventType.drawMove,
      strokeId: strokeId,
      point: point,
    );

    _handleMyDrawMove(event);

    if (_isSocketConnected && _userId != null) {
      _socketService.sendDrawEvent(event, _userId!);
    }

    try { NativeDrawingBridge.sendDrawEvent(event.toJson()); } catch (_) {}
  }

  void sendDrawEnd(int strokeId, List<DrawPoint> points) {
    final activeStroke = _myActiveStrokes[strokeId];

    final event = DrawEvent(
      eventType: DrawEventType.drawEnd,
      strokeId: strokeId,
      points: List<DrawPoint>.from(points),
      color: activeStroke?.color ?? _currentColor,  // 서버 전송에 필요
      width: activeStroke?.width ?? _currentWidth,  // 서버 전송에 필요
    );

    _handleMyDrawEnd(event);

    if (_isSocketConnected && _userId != null) {
      _socketService.sendDrawEvent(event, _userId!);
    }

    try { NativeDrawingBridge.sendDrawEvent(event.toJson()); } catch (_) {}
  }

  void sendUndo(int strokeId) {
    final event = DrawEvent(eventType: DrawEventType.undo, strokeId: strokeId);

    _handleMyUndo(event);

    if (_isSocketConnected && _userId != null) {
      _socketService.sendUndo(strokeId, _userId!);
    }

    try { NativeDrawingBridge.sendDrawEvent(event.toJson()); } catch (_) {}
  }

  /// ===============================
  /// 학생 개인 필기 (로컬 전용 / 팀원 추가)
  /// ===============================
  int startStudentPrivateStroke(DrawPoint point) {
    final strokeId = _nextStrokeId();
    _studentPrivateActiveStrokes[strokeId] = Stroke(
      strokeId: strokeId,
      color: _currentColor,
      width: _currentWidth,
      points: [point],
    );
    notifyListeners();
    return strokeId;
  }

  void appendStudentPrivatePoint(int strokeId, DrawPoint point) {
    final stroke = _studentPrivateActiveStrokes[strokeId];
    if (stroke == null) return;
    final updated = [...stroke.points, point];
    _studentPrivateActiveStrokes[strokeId] = stroke.copyWith(points: updated);
    if (updated.length % 3 == 0) notifyListeners();
  }

  void endStudentPrivateStroke(int strokeId, List<DrawPoint> points) {
    final stroke = _studentPrivateActiveStrokes.remove(strokeId);
    if (stroke == null) return;
    final copied = List<DrawPoint>.from(points);
    _studentPrivateStrokes[strokeId] =
    copied.isNotEmpty ? stroke.withRefinedPoints(copied) : stroke;
    notifyListeners();
  }

  void clearStudentPrivateStrokes() {
    _studentPrivateStrokes.clear();
    _studentPrivateActiveStrokes.clear();
    notifyListeners();
  }

  /// ===============================
  /// 전체 초기화
  /// ===============================
  void clear() {
    _myStrokes.clear();
    _myActiveStrokes.clear();
    _othersStrokes.clear();
    _othersActiveStrokes.clear();
    notifyListeners();

    if (_isTeacher && _isSocketConnected && _userId != null) {
      _socketService.sendClearAll(_userId!);
    }
  }

  /// ===============================
  /// 저장된 판서 로드 (읽기 전용)
  /// ===============================
  void loadSavedStrokes(List<Map<String, dynamic>> strokesData) {
    _othersStrokes.clear();
    _othersActiveStrokes.clear();

    for (final strokeData in strokesData) {
      try {
        final strokeId = strokeData['sId'] as int;
        final ptsData = strokeData['pts'] as List?;
        final points = <DrawPoint>[];

        if (ptsData != null) {
          for (final pt in ptsData) {
            if (pt is Map) {
              points.add(DrawPoint(
                x: (pt['x'] as num?)?.toDouble() ?? 0.0,
                y: (pt['y'] as num?)?.toDouble() ?? 0.0,
                pressure: (pt['p'] as num?)?.toDouble(),
              ));
            }
          }
        }

        if (points.isEmpty) {
          final x = (strokeData['x'] as num?)?.toDouble() ?? 0.0;
          final y = (strokeData['y'] as num?)?.toDouble() ?? 0.0;
          points.add(DrawPoint(x: x, y: y));
        }

        Color color = Colors.black;
        final colorStr = strokeData['c'] as String?;
        if (colorStr != null && colorStr.startsWith('#')) {
          try {
            color = Color(0xFF000000 | int.parse(colorStr.substring(1), radix: 16));
          } catch (_) {}
        }

        _othersStrokes[strokeId] = Stroke(
          strokeId: strokeId,
          color: color,
          width: (strokeData['w'] as num?)?.toDouble() ?? 2.5,
          points: points,
        );
      } catch (e) {
        debugPrint('❌ Failed to parse stroke: $e');
      }
    }

    notifyListeners();
  }

  void disconnectSocket() {
    _socketService.disconnect();
    _isSocketConnected = false;
    notifyListeners();
  }

  void _handleSessionEnded(Map<String, dynamic> data) {
    onSessionEnded?.call(data);
  }

  Function(Map<String, dynamic>)? onSessionEnded;

  @override
  void dispose() {
    // lastTick 저장
    if (_lastTick != null) {
      SessionStorage.updateLastTick(_lastTick!);
    }
    _stopTickSaveTimer();
    _nativeDrawEventSubscription?.cancel();
    disconnectSocket();
    super.dispose();
  }
}