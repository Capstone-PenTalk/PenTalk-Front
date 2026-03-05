import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/drawing_models.dart';

/// ===============================
/// Socket.IO 서비스
/// 실시간 판서 데이터 송수신
/// ===============================
class SocketService {
  IO.Socket? _socket;
  String? _currentRoomId;
  String? _currentUserId;
  bool? _isTeacher; // 재접속 시 필요

  // 콜백 함수들
  Function(DrawEvent)? onDrawEventReceived;
  Function(String)? onUserJoined;
  Function(String)? onUserLeft;
  Function()? onConnected;
  Function()? onDisconnected;
  Function(dynamic)? onError;
  Function(List<dynamic>)? onSyncState; // 동기화 데이터 수신

  bool get isConnected => _socket?.connected ?? false;
  String? get currentRoomId => _currentRoomId;
  String? get currentUserId => _currentUserId;

  /// ===============================
  /// Socket.IO 연결
  /// ===============================
  Future<void> connect({
    required String serverUrl,
    required String userId,
    required String roomId,
    bool isTeacher = false,
    String? jwtToken, // JWT 토큰 추가
  }) async {
    try {
      _currentUserId = userId;
      _currentRoomId = roomId;
      _isTeacher = isTeacher; // 재접속 시 사용

      debugPrint('Connecting to Socket.IO: $serverUrl');
      debugPrint('User ID: $userId, Room ID: $roomId, isTeacher: $isTeacher');

      // Socket.IO 옵션 설정
      final optionsBuilder = IO.OptionBuilder()
          .setTransports(['websocket']) // WebSocket 우선 사용
          .disableAutoConnect(); // 수동 연결

      // JWT 토큰이 있으면 인증 설정
      if (jwtToken != null && jwtToken.isNotEmpty) {
        optionsBuilder.setAuth({
          'token': jwtToken, // 명세서 방식: JWT 인증
        });
        debugPrint('🔐 JWT token added to auth');
      }

      _socket = IO.io(serverUrl, optionsBuilder.build());

      // 이벤트 리스너 등록
      _setupEventListeners();

      // 연결 시작
      _socket!.connect();

      // 연결 대기 (최대 5초)
      await Future.delayed(const Duration(milliseconds: 500));

      if (_socket!.connected) {
        // 방 참여
        _joinRoom(roomId, userId, isTeacher);
      }
    } catch (e) {
      debugPrint('Socket connection error: $e');
      onError?.call(e);
    }
  }

  /// ===============================
  /// 이벤트 리스너 설정
  /// ===============================
  void _setupEventListeners() {
    if (_socket == null) return;

    // 연결 성공 (재접속 포함)
    _socket!.on('connect', (_) {
      debugPrint('✅ Socket.IO connected: ${_socket!.id}');

      // 재접속 시 자동으로 방 다시 참여 (명세서 요구사항)
      if (_currentRoomId != null && _currentUserId != null) {
        final isTeacher = _isTeacher ?? false;
        _joinRoom(_currentRoomId!, _currentUserId!, isTeacher);
        debugPrint('🔄 Re-joined room after reconnection');

        // 동기화 요청 (이전 판서 복구)
        Future.delayed(const Duration(milliseconds: 100), () {
          requestSync();
        });
      }

      onConnected?.call();
    });

    // 연결 끊김
    _socket!.on('disconnect', (_) {
      debugPrint('❌ Socket.IO disconnected');
      onDisconnected?.call();
    });

    // 연결 에러
    _socket!.on('connect_error', (error) {
      debugPrint('❌ Socket.IO connection error: $error');
      onError?.call(error);
    });

    // 판서 이벤트 수신
    _socket!.on('draw_event', (data) {
      try {
        debugPrint('📥 Received draw_event: ${data['e']}');
        final event = DrawEvent.fromJson(Map<String, dynamic>.from(data));
        onDrawEventReceived?.call(event);
      } catch (e) {
        debugPrint('Error parsing draw_event: $e');
      }
    });

    // 사용자 입장
    _socket!.on('user_joined', (data) {
      final userId = data['userId'] as String;
      debugPrint('👤 User joined: $userId');
      onUserJoined?.call(userId);
    });

    // 사용자 퇴장
    _socket!.on('user_left', (data) {
      final userId = data['userId'] as String;
      debugPrint('👋 User left: $userId');
      onUserLeft?.call(userId);
    });

    // 방 참여 확인
    _socket!.on('room_joined', (data) {
      debugPrint('✅ Joined room: ${data['roomId']}');
    });

    // 동기화 데이터 수신 (재접속 시)
    _socket!.on('sync_state', (data) {
      debugPrint('📥 Received sync_state');
      if (data is List) {
        onSyncState?.call(data);
      }
    });

    // 에러
    _socket!.on('error', (error) {
      debugPrint('❌ Socket error: $error');
      onError?.call(error);
    });
  }

  /// ===============================
  /// 방 참여
  /// ===============================
  void _joinRoom(String roomId, String userId, bool isTeacher) {
    if (_socket == null || !_socket!.connected) {
      debugPrint('Cannot join room: Socket not connected');
      return;
    }

    // 명세서 방식: role 사용, timestamp 제거
    final role = isTeacher ? 'teacher' : 'student';

    _socket!.emit('join_room', {
      'roomId': roomId,
      'userId': userId,
      'role': role,
    });

    debugPrint('📤 Sent join_room: $roomId (role: $role)');
  }

  /// ===============================
  /// 판서 이벤트 전송
  /// ===============================
  void sendDrawEvent(DrawEvent event, String senderId) {
    if (_socket == null || !_socket!.connected) {
      debugPrint('Cannot send draw event: Socket not connected');
      return;
    }

    final data = {
      ...event.toJson(),
      'roomId': _currentRoomId,
      'senderId': senderId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _socket!.emit('draw_event', data);

    // draw_move는 너무 많이 로그되므로 제외
    if (event.eventType != DrawEventType.drawMove) {
      debugPrint('📤 Sent draw_event: ${event.eventType.code}');
    }
  }

  /// ===============================
  /// Undo 이벤트 전송
  /// ===============================
  void sendUndo(int strokeId, String senderId) {
    if (_socket == null || !_socket!.connected) {
      debugPrint('Cannot send undo: Socket not connected');
      return;
    }

    _socket!.emit('draw_event', {
      'e': 'un',
      'sId': strokeId,
      'roomId': _currentRoomId,
      'senderId': senderId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    debugPrint('📤 Sent undo: $strokeId');
  }

  /// ===============================
  /// 전체 캔버스 클리어 (교사 전용)
  /// ===============================
  void sendClearAll(String senderId) {
    if (_socket == null || !_socket!.connected) {
      debugPrint('Cannot send clear: Socket not connected');
      return;
    }

    _socket!.emit('draw:clear', {
      'roomId': _currentRoomId,
      'senderId': senderId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    debugPrint('📤 Sent clear_all');
  }

  /// ===============================
  /// 방 나가기
  /// ===============================
  void leaveRoom() {
    if (_socket == null || !_socket!.connected || _currentRoomId == null) {
      return;
    }

    _socket!.emit('leave_room', {
      'roomId': _currentRoomId,
      'userId': _currentUserId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    debugPrint('📤 Sent leave_room: $_currentRoomId');
  }

  /// ===============================
  /// 연결 종료
  /// ===============================
  void disconnect() {
    leaveRoom();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _currentRoomId = null;
    _currentUserId = null;
    debugPrint('🔌 Socket.IO disconnected and disposed');
  }

  /// ===============================
  /// 재연결 시도
  /// ===============================
  Future<void> reconnect() async {
    if (_socket?.connected == true) {
      debugPrint('Already connected, no need to reconnect');
      return;
    }

    debugPrint('Attempting to reconnect...');
    _socket?.connect();
  }

  /// ===============================
  /// 동기화 요청 (재접속 시 이전 판서 복구)
  /// ===============================
  void requestSync() {
    if (_socket == null || !_socket!.connected) {
      debugPrint('Cannot request sync: Socket not connected');
      return;
    }

    _socket!.emit('sync_request', {
      'roomId': _currentRoomId,
    });

    debugPrint('📤 Sent sync_request for room: $_currentRoomId');
  }
}