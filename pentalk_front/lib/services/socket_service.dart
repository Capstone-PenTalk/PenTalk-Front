
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
  String? _currentMaterialId;
  bool _currentIsTeacher = false;

  // 콜백 함수들
  Function(DrawEvent)? onDrawEventReceived;
  Function(String)? onUserJoined;
  Function(String)? onUserLeft;
  Function()? onConnected;
  Function()? onDisconnected;
  Function(dynamic)? onError;

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
    String? materialId,
  }) async {
    try {
      _currentUserId = userId;
      _currentRoomId = roomId;
      _currentMaterialId = materialId;
      _currentIsTeacher = isTeacher;

      final normalizedUrl = serverUrl.replaceFirst(RegExp(r'^hhttps'), 'https');
      debugPrint('[socket] Connecting to $normalizedUrl');
      debugPrint('[socket] userId=$userId roomId=$roomId materialId=$materialId isTeacher=$isTeacher');

      final uri = Uri.parse(normalizedUrl);
      final token = uri.queryParameters['token'];
      final queryParams = Map<String, String>.from(uri.queryParameters);
      queryParams.remove('token');
      final hasValidPort = uri.hasPort && uri.port > 0;
      final originUri = hasValidPort
          ? Uri(scheme: uri.scheme, host: uri.host, port: uri.port)
          : Uri(scheme: uri.scheme, host: uri.host);
      final baseUrl = StringBuffer()..write(originUri.toString());
      if (uri.path.isNotEmpty && uri.path != '/') {
        baseUrl.write(uri.path);
      }

      final options = IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setExtraHeaders({
            'user-id': userId,
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          });
      if (queryParams.isNotEmpty) {
        options.setQuery(queryParams);
      }
      if (token != null && token.isNotEmpty) {
        options.setAuth({'token': token});
      }

      // Socket.IO 옵션 설정
      _socket = IO.io(
        baseUrl.toString(),
        options.build(),
      );

      // 이벤트 리스너 등록
      _setupEventListeners();

      // 연결 시작
      _socket!.connect();
    } catch (e) {
      debugPrint('[socket][error] connect threw: $e');
      onError?.call(e);
    }
  }

  /// ===============================
  /// 이벤트 리스너 설정
  /// ===============================
  void _setupEventListeners() {
    if (_socket == null) return;

    // 연결 성공
    _socket!.on('connect', (_) {
      debugPrint('[socket] connected id=${_socket!.id}');
      onConnected?.call();
      if (_currentRoomId != null && _currentUserId != null) {
        _joinRoom(
          _currentRoomId!,
          _currentUserId!,
          _currentIsTeacher,
          materialId: _currentMaterialId,
        );
      }
    });

    // 연결 끊김
    _socket!.on('disconnect', (_) {
      debugPrint('[socket] disconnected');
      onDisconnected?.call();
    });

    // 연결 에러
    _socket!.on('connect_error', (error) {
      debugPrint('[socket][error] connect_error: $error');
      onError?.call(error);
    });

    // 판서 이벤트 수신
    _socket!.on('draw:append', (data) {
      try {
        debugPrint('[socket][recv] draw:append e=${data['e']} room=${data['roomId']} sender=${data['senderId']}');
        final event = DrawEvent.fromJson(Map<String, dynamic>.from(data));
        onDrawEventReceived?.call(event);
      } catch (e) {
        debugPrint('[socket][error] draw:append parse failed: $e');
      }
    });
    _socket!.on('draw:clear', (data) {
      try {
        debugPrint('[socket][recv] draw:clear e=${data['e']} room=${data['roomId']} sender=${data['senderId']}');
        final event = DrawEvent.fromJson(Map<String, dynamic>.from(data));
        onDrawEventReceived?.call(event);
      } catch (e) {
        debugPrint('[socket][error] draw:clear parse failed: $e');
      }
    });

    // 사용자 입장
    _socket!.on('user_joined', (data) {
      final userId = data['userId'] as String;
      debugPrint('[socket] user_joined userId=$userId');
      onUserJoined?.call(userId);
    });

    // 사용자 퇴장
    _socket!.on('user_left', (data) {
      final userId = data['userId'] as String;
      debugPrint('[socket] user_left userId=$userId');
      onUserLeft?.call(userId);
    });

    // 방 참여 확인
    _socket!.on('room_joined', (data) {
      debugPrint('[socket] room_joined roomId=${data['roomId']}');
    });

    // 에러
    _socket!.on('error', (error) {
      debugPrint('[socket][error] socket error: $error');
      onError?.call(error);
    });
    _socket!.on('server_error', (error) {
      debugPrint('[socket][error] server_error: $error');
      onError?.call(error);
    });
  }

  /// ===============================
  /// 방 참여
  /// ===============================
  void _joinRoom(
    String roomId,
    String userId,
    bool isTeacher, {
    String? materialId,
  }) {
    if (_socket == null || !_socket!.connected) {
      debugPrint('Cannot join room: Socket not connected');
      return;
    }

    debugPrint(
      '[socket][send] join_room roomId=$roomId userId=$userId materialId=$materialId isTeacher=$isTeacher',
    );
    _socket!.emit('join_room', {
      'roomId': roomId,
      'userId': userId,
      'isTeacher': isTeacher,
      if (materialId != null && materialId.isNotEmpty) 'materialId': materialId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// ===============================
  /// 판서 이벤트 전송
  /// ===============================
  void sendDrawEvent(DrawEvent event, String senderId) {
    if (_socket == null) {
      debugPrint('[socket][send] skipped: socket not initialized e=${event.eventType.code}');
      return;
    }
    if (!_socket!.connected) {
      debugPrint('[socket][send] skipped: socket disconnected e=${event.eventType.code}');
      return;
    }

    final data = {
      ...event.toJson(),
      'roomId': _currentRoomId,
      'senderId': senderId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _socket!.emit('draw:append', data);
    if (event.eventType == DrawEventType.drawMove && !kDebugMode) {
      return;
    }

    debugPrint(
      '[socket][send] draw:append e=${event.eventType.code} sId=${event.strokeId} room=$_currentRoomId sender=$senderId',
    );
  }

  /// ===============================
  /// Undo 이벤트 전송
  /// ===============================
  void sendUndo(int strokeId, String senderId) {
    if (_socket == null) {
      debugPrint('[socket][send] skipped undo: socket not initialized');
      return;
    }

    _socket!.emit('draw:clear', {
      'e': 'un',
      'sId': strokeId,
      'roomId': _currentRoomId,
      'senderId': senderId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    debugPrint('[socket][send] draw:clear e=un sId=$strokeId room=$_currentRoomId sender=$senderId');
  }

  /// ===============================
  /// 전체 캔버스 클리어 (교사 전용)
  /// ===============================
  void sendClearAll(String senderId) {
    if (_socket == null) {
      debugPrint('[socket][send] skipped clear: socket not initialized');
      return;
    }

    _socket!.emit('draw:clear', {
      'e': 'er',
      'sId': 0,
      'roomId': _currentRoomId,
      'senderId': senderId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    debugPrint('[socket][send] draw:clear e=er room=$_currentRoomId sender=$senderId');
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

    debugPrint('[socket][send] leave_room roomId=$_currentRoomId userId=$_currentUserId');
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
    _currentMaterialId = null;
    debugPrint('[socket] disposed');
  }

  /// ===============================
  /// 재연결 시도
  /// ===============================
  Future<void> reconnect() async {
    if (_socket?.connected == true) {
      debugPrint('[socket] reconnect skipped: already connected');
      return;
    }

    debugPrint('[socket] reconnecting...');
    _socket?.connect();
  }
}
