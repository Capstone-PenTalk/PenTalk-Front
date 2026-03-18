import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../models/drawing_models.dart';
import '../services/socket_service.dart';
import '../services/session_storage.dart';

/// ===============================
/// 판서 데이터 Provider (Socket.IO 통합)
/// 최적화: notifyListeners() 호출 최소화
/// ===============================
class DrawingProvider extends ChangeNotifier {
  static const platform = MethodChannel('pentalk/drawing');

  // Socket.IO 서비스
  final SocketService _socketService = SocketService();

  // ✅ SocketService getter 추가 (DrawingScreen에서 접근용)
  SocketService get socketService => _socketService;

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

  // ✅ lastTick 관리 (자동 재join용)
  int? _lastTick;
  Timer? _tickSaveTimer;

  int? get lastTick => _lastTick;

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
    String? jwtToken,
    String? materialTitle,  // ✅ 세션 저장용
    String? backgroundUrl,  // ✅ 세션 저장용
  }) async {
    _userId = userId;
    _roomId = roomId;
    _isTeacher = isTeacher;

    // ✅ 저장된 lastTick 로드 (자동 재join용)
    final session = await SessionStorage.getLastSession();
    if (session?.lastTick != null) {
      _lastTick = session!.lastTick;
      debugPrint('📥 LastTick loaded from storage: $_lastTick');
    }

    try {
      await _socketService.connect(
        serverUrl: serverUrl,
        userId: userId,
        roomId: roomId,
        isTeacher: isTeacher,
        jwtToken: jwtToken,
      );

      _isSocketConnected = true;
      notifyListeners();

      // ✅ Presence 리스너 설정
      _setupPresenceListeners();

      // ✅ 세션 정보 저장 (자동 재join용)
      if (materialTitle != null) {
        await SessionStorage.saveSession(
          sessionId: roomId,  // sessionId = roomId
          roomId: roomId,
          role: isTeacher ? 'teacher' : 'student',
          materialTitle: materialTitle,
          backgroundUrl: backgroundUrl,
          serverUrl: serverUrl,
          lastTick: _lastTick,
        );
        debugPrint('✅ Session info saved for auto-rejoin');
      }

      // ✅ lastTick 주기적 저장 시작 (5초마다)
      _startTickSaveTimer();

    } catch (e) {
      debugPrint('Failed to connect socket: $e');
      _isSocketConnected = false;
      notifyListeners();
    }
  }

  /// ===============================
  /// ✅ lastTick 저장 타이머 시작 (5초마다)
  /// ===============================
  void _startTickSaveTimer() {
    _tickSaveTimer?.cancel();

    _tickSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_lastTick != null) {
        SessionStorage.updateLastTick(_lastTick!);
      }
    });

    debugPrint('🔄 Tick save timer started (5s interval)');
  }

  /// ===============================
  /// ✅ lastTick 저장 타이머 중지
  /// ===============================
  void _stopTickSaveTimer() {
    _tickSaveTimer?.cancel();
    _tickSaveTimer = null;
    debugPrint('⏹️ Tick save timer stopped');
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

      // ✅ 재접속 시 동기화 요청 (lastTick과 함께)
      Future.delayed(const Duration(milliseconds: 100), () {
        _socketService.requestSync(lastTick: _lastTick);
      });
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

    // 세션 종료 알림
    _socketService.onSessionEnded = (data) {
      _handleSessionEnded(data);
    };
  }

  /// ===============================
  /// ✅ Presence 리스너 설정 (신규 추가!)
  /// ===============================
  void _setupPresenceListeners() {
    // SocketService에 Presence 리스너 설정
    // 실제 콜백 연결은 DrawingScreen에서 수행
    _socketService.setupPresenceListeners();

    debugPrint('🔔 Presence listeners setup completed');
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

    // ✅ tick 업데이트 (de 이벤트에만 tick이 있음)
    if (event.tick != null) {
      _lastTick = event.tick;
      debugPrint('🔄 LastTick updated: $_lastTick');
    }

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

  /// ===============================
  /// 저장된 판서 데이터 로드 (읽기 전용 뷰어용)
  /// ===============================
  void loadSavedStrokes(List<Map<String, dynamic>> strokesData) {
    debugPrint('📥 Loading ${strokesData.length} saved strokes');

    _othersStrokes.clear();
    _othersActiveStrokes.clear();

    for (final strokeData in strokesData) {
      try {
        final strokeId = strokeData['sId'] as int;

        // 좌표 파싱
        final x = (strokeData['x'] as num?)?.toDouble() ?? 0.0;
        final y = (strokeData['y'] as num?)?.toDouble() ?? 0.0;

        // 점들 파싱
        final ptsData = strokeData['pts'] as List?;
        final points = <DrawPoint>[];

        if (ptsData != null) {
          for (final pt in ptsData) {
            if (pt is Map) {
              final ptX = (pt['x'] as num?)?.toDouble() ?? 0.0;
              final ptY = (pt['y'] as num?)?.toDouble() ?? 0.0;
              final pressure = (pt['p'] as num?)?.toDouble();

              points.add(DrawPoint(
                x: ptX,
                y: ptY,
                pressure: pressure,
              ));
            }
          }
        }

        // 시작점도 추가
        if (points.isEmpty) {
          points.add(DrawPoint(x: x, y: y));
        }

        // 색상 파싱 (hex string → Color)
        Color color = Colors.black;
        final colorStr = strokeData['c'] as String?;
        if (colorStr != null && colorStr.startsWith('#')) {
          try {
            final hex = colorStr.substring(1);
            final colorInt = int.parse(hex, radix: 16);
            color = Color(0xFF000000 | colorInt);
          } catch (e) {
            debugPrint('Failed to parse color: $colorStr');
          }
        }

        // 굵기 파싱
        final width = (strokeData['w'] as num?)?.toDouble() ?? 2.5;

        // Stroke 생성
        final stroke = Stroke(
          strokeId: strokeId,
          color: color,
          width: width,
          points: points,
        );

        _othersStrokes[strokeId] = stroke;

      } catch (e) {
        debugPrint('❌ Failed to parse stroke: $e');
      }
    }

    debugPrint('✅ Loaded ${_othersStrokes.length} strokes');
    notifyListeners();
  }

  /// Socket 연결 해제
  void disconnectSocket() {
    _socketService.disconnect();
    _isSocketConnected = false;
    notifyListeners();
  }

  /// ===============================
  /// 세션 종료 처리 (session:ended 이벤트 수신)
  /// ===============================
  void _handleSessionEnded(Map<String, dynamic> data) {
    debugPrint('📥 Session ended: $data');

    // sessionEnded 콜백 호출 (UI에서 처리)
    onSessionEnded?.call(data);
  }

  // 세션 종료 콜백 (DrawingScreen에서 설정)
  Function(Map<String, dynamic>)? onSessionEnded;

  @override
  void dispose() {
    // ✅ 마지막 tick 저장 (dispose 시)
    if (_lastTick != null) {
      SessionStorage.updateLastTick(_lastTick!);
      debugPrint('💾 LastTick saved on dispose: $_lastTick');
    }

    // ✅ Timer 정리
    _stopTickSaveTimer();

    disconnectSocket();
    super.dispose();
  }
}