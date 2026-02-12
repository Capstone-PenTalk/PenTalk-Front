import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/drawing_models.dart';
import '../services/socket_service.dart';

/// ===============================
/// 판서 데이터 Provider (Socket.IO 통합)
/// 최적화: notifyListeners() 호출 최소화
/// ===============================
class DrawingProvider extends ChangeNotifier {
  static const platform = MethodChannel('pentalk/drawing');

  // Socket.IO 서비스
  final SocketService _socketService = SocketService();

  // 내 펜 (로컬에서 그린 선들)
  final Map<int, Stroke> _myStrokes = {};
  final Map<int, Stroke> _myActiveStrokes = {};

  // 상대 펜 (다른 사람이 그린 선들)
  final Map<int, Stroke> _othersStrokes = {};
  final Map<int, Stroke> _othersActiveStrokes = {};

  // 배경 이미지 URL
  String? _backgroundUrl;

  // 그리기 모드 (교사용)
  bool _isDrawingMode = false;
  Color _currentColor = Colors.black;
  double _currentWidth = 2.5;

  // 사용자 정보
  String? _userId;
  String? _roomId;
  bool _isTeacher = false;

  // 소켓 연결 상태
  bool _isSocketConnected = false;

  // Getters
  Map<int, Stroke> get myStrokes => _myStrokes;
  Map<int, Stroke> get myActiveStrokes => _myActiveStrokes;
  Map<int, Stroke> get othersStrokes => _othersStrokes;
  Map<int, Stroke> get othersActiveStrokes => _othersActiveStrokes;
  String? get backgroundUrl => _backgroundUrl;
  bool get isDrawingMode => _isDrawingMode;
  Color get currentColor => _currentColor;
  double get currentWidth => _currentWidth;
  bool get isSocketConnected => _isSocketConnected;
  String? get userId => _userId;
  String? get roomId => _roomId;

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
    _setupMethodChannel();
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
    String? jwtToken, // JWT 토큰 추가
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
        jwtToken: jwtToken, // JWT 전달
      );

      _isSocketConnected = true;
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

    // 사용자 입/퇴장
    _socketService.onUserJoined = (userId) {
      debugPrint('👤 User joined: $userId');
    };

    _socketService.onUserLeft = (userId) {
      debugPrint('👋 User left: $userId');
    };
  }

  /// ===============================
  /// MethodChannel 설정
  /// ===============================
  void _setupMethodChannel() {
    platform.setMethodCallHandler((call) async {
      try {
        if (call.method == 'onDrawEvent') {
          final data = Map<String, dynamic>.from(call.arguments);
          final event = DrawEvent.fromJson(data);
          _handleReceivedDrawEvent(event);
        }
      } catch (e) {
        debugPrint('MethodChannel error: $e');
      }
    });
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
    final removed = _othersStrokes.remove(event.strokeId) != null ||
        _othersActiveStrokes.remove(event.strokeId) != null;

    if (removed) {
      notifyListeners();
    }
  }

  /// ===============================
  /// 내 판서 이벤트 처리 (로컬)
  /// ===============================
  void _handleMyDrawStart(DrawEvent event) {
    if (event.point == null) return;

    final stroke = Stroke(
      strokeId: event.strokeId,
      color: event.color ?? Colors.black,
      width: event.width ?? 2.5,
      points: [event.point!],
    );

    _myActiveStrokes[event.strokeId] = stroke;
    notifyListeners();
  }

  void _handleMyDrawMove(DrawEvent event) {
    if (event.point == null) return;

    final stroke = _myActiveStrokes[event.strokeId];
    if (stroke == null) return;

    final updatedPoints = [...stroke.points, event.point!];
    _myActiveStrokes[event.strokeId] = stroke.copyWith(points: updatedPoints);

    if (updatedPoints.length % 3 == 0) {
      notifyListeners();
    }
  }

  void _handleMyDrawEnd(DrawEvent event) {
    final stroke = _myActiveStrokes.remove(event.strokeId);
    if (stroke == null) return;

    final finalStroke = event.points != null && event.points!.isNotEmpty
        ? stroke.withRefinedPoints(event.points!)
        : stroke;

    _myStrokes[event.strokeId] = finalStroke;
    notifyListeners();
  }

  void _handleMyUndo(DrawEvent event) {
    final removed = _myStrokes.remove(event.strokeId) != null ||
        _myActiveStrokes.remove(event.strokeId) != null;

    if (removed) {
      notifyListeners();
    }
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

  void setDrawingMode(bool enabled) {
    if (_isDrawingMode != enabled) {
      _isDrawingMode = enabled;
      notifyListeners();
    }
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

  /// ===============================
  /// 내가 그릴 때: 로컬 + 소켓 전송
  /// ===============================
  int sendDrawStart(DrawPoint point) {
    final strokeId = DateTime.now().millisecondsSinceEpoch;

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
    }

    // MethodChannel로도 전송 (네이티브)
    try {
      platform.invokeMethod('sendDrawEvent', event.toJson());
    } catch (e) {
      // 네이티브 실패해도 무시
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
      platform.invokeMethod('sendDrawEvent', event.toJson());
    } catch (e) {
      // 네이티브 실패해도 무시
    }
  }

  void sendDrawEnd(int strokeId, List<DrawPoint> points) {
    final event = DrawEvent(
      eventType: DrawEventType.drawEnd,
      strokeId: strokeId,
      points: points,
    );

    // 로컬에 먼저 표시
    _handleMyDrawEnd(event);

    // Socket.IO로 전송
    if (_isSocketConnected && _userId != null) {
      _socketService.sendDrawEvent(event, _userId!);
    }

    // MethodChannel로도 전송
    try {
      platform.invokeMethod('sendDrawEvent', event.toJson());
    } catch (e) {
      // 네이티브 실패해도 무시
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
    }

    // MethodChannel로도 전송
    try {
      platform.invokeMethod('sendDrawEvent', event.toJson());
    } catch (e) {
      // 네이티브 실패해도 무시
    }
  }

  /// 전체 초기화
  void clear() {
    _myStrokes.clear();
    _myActiveStrokes.clear();
    _othersStrokes.clear();
    _othersActiveStrokes.clear();
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

  @override
  void dispose() {
    disconnectSocket();
    super.dispose();
  }
}