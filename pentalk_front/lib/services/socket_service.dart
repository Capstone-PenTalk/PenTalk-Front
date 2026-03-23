import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/drawing_models.dart';

/// ===============================
/// Socket.IO 서비스
/// 실시간 판서 데이터 송수신
/// ===============================
class SocketService {
  static const String _tokenStoragePrefix = 'dev_socket_jwt';
  IO.Socket? _socket;
  String? _currentRoomId;
  String? _currentUserId;
  String? _currentMaterialId;
  String? _currentClassId;
  bool _currentIsTeacher = false;
  bool _isRoomJoined = false;
  final List<Map<String, dynamic>> _pendingEmits = [];

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
    String? classId,
    String? materialId,
  }) async {
    try {
      _currentUserId = userId;
      _currentRoomId = roomId;
      _currentMaterialId = materialId;
      _currentClassId = classId;
      _currentIsTeacher = isTeacher;
      _isRoomJoined = false;
      _pendingEmits.clear();

      final normalizedUrl = serverUrl.replaceFirst(RegExp(r'^hhttps'), 'https');
      debugPrint('[socket] Connecting to $normalizedUrl');
      debugPrint('[socket] userId=$userId roomId=$roomId materialId=$materialId isTeacher=$isTeacher');

      final uri = Uri.parse(normalizedUrl);
      final role = isTeacher ? 'teacher' : 'student';
      final explicitToken = uri.queryParameters['token'];
      final token = (explicitToken != null && explicitToken.isNotEmpty)
          ? explicitToken
          : await _getOrCreateDevToken(
              uri: uri,
              userId: userId,
              role: role,
            );
      final queryParams = Map<String, String>.from(uri.queryParameters);
      queryParams.remove('token');
      final effectivePort =
          (uri.hasPort && uri.port > 0) ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      final baseUrl = StringBuffer()
        ..write(uri.scheme)
        ..write('://')
        ..write(uri.host)
        ..write(':')
        ..write(effectivePort);
      if (uri.path.isNotEmpty && uri.path != '/') {
        baseUrl.write(uri.path);
      }
      debugPrint('[socket] baseUrl=${baseUrl.toString()}');

      final options = IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setExtraHeaders({
            'bypass-tunnel-reminder': 'true',
            'user-id': userId,
            if (token.isNotEmpty)
              'Authorization': 'Bearer $token',
          });
      if (queryParams.isNotEmpty) {
        options.setQuery(queryParams);
      }
      if (token.isNotEmpty) {
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

  Future<String> _getOrCreateDevToken({
    required Uri uri,
    required String userId,
    required String role,
  }) async {
    final effectivePort =
        (uri.hasPort && uri.port > 0) ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final storageKey = [
      _tokenStoragePrefix,
      uri.scheme,
      uri.host,
      '$effectivePort',
      role,
      userId,
    ].join(':');

    final prefs = await SharedPreferences.getInstance();
    final cachedToken = prefs.getString(storageKey);
    if (cachedToken != null && cachedToken.isNotEmpty) {
      debugPrint('[socket][auth] using cached token role=$role userId=$userId');
      return cachedToken;
    }

    final authUri = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: effectivePort,
      path: '/auth/dev-login',
    );

    debugPrint('[socket][auth] requesting dev token: $authUri');
    final response = await http.post(
      authUri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': userId,
        'role': role,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'dev-login failed status=${response.statusCode} body=${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('dev-login invalid response format');
    }

    final token = decoded['token']?.toString() ?? '';
    if (token.isEmpty) {
      throw Exception('dev-login token missing in response');
    }

    await prefs.setString(storageKey, token);
    debugPrint('[socket][auth] cached token role=$role userId=$userId');
    return token;
  }

  /// ===============================
  /// 이벤트 리스너 설정
  /// ===============================
  void _setupEventListeners() {
    if (_socket == null) return;

    // 연결 성공
    _socket!.on('connect', (_) {
      debugPrint('[socket] connected id=${_socket!.id}');
      _isRoomJoined = false;
      onConnected?.call();
      if (_currentRoomId != null && _currentUserId != null) {
        _joinRoom(
          _currentRoomId!,
          _currentUserId!,
          _currentIsTeacher,
          classId: _currentClassId,
          materialId: _currentMaterialId,
        );
      }
    });

    // 연결 끊김
    _socket!.on('disconnect', (_) {
      debugPrint('[socket] disconnected');
      _isRoomJoined = false;
      _pendingEmits.clear();
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
    _socket!.on('join_success', (data) {
      debugPrint('[socket] join_success roomId=${data['roomId']} classId=${data['classId']}');
      _isRoomJoined = true;
      _flushPendingEmits();
    });

    // 에러
    _socket!.on('error', (error) {
      debugPrint('[socket][error] socket error: $error');
      onError?.call(error);
    });
    _socket!.on('server_error', (error) {
      debugPrint('[socket][error] server_error: $error');
      final map = error is Map ? Map<String, dynamic>.from(error) : null;
      final code = map?['code']?.toString();
      if (code == 'NOT_JOINED') {
        _isRoomJoined = false;
        if (_currentRoomId != null && _currentUserId != null) {
          debugPrint('[socket] server said NOT_JOINED -> rejoin');
          _joinRoom(
            _currentRoomId!,
            _currentUserId!,
            _currentIsTeacher,
            classId: _currentClassId,
            materialId: _currentMaterialId,
          );
        }
      }
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
    String? classId,
    String? materialId,
  }) {
    if (_socket == null || !_socket!.connected) {
      debugPrint('Cannot join room: Socket not connected');
      return;
    }

    debugPrint(
      '[socket][send] join_room roomId=$roomId classId=$classId userId=$userId materialId=$materialId isTeacher=$isTeacher',
    );
    _socket!.emit('join_room', {
      'roomId': roomId,
      'userId': userId,
      'isTeacher': isTeacher,
      if (classId != null && classId.isNotEmpty) 'classId': classId,
      if (materialId != null && materialId.isNotEmpty) 'materialId': materialId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// ===============================
  /// 판서 이벤트 전송
  /// ===============================
  void sendDrawEvent(DrawEvent event, String senderId) {
    final data = {
      ...event.toJson(),
      'roomId': _currentRoomId,
      'senderId': senderId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _emitOrQueue(
      'draw:append',
      data,
      summary:
          'draw:append e=${event.eventType.code} sId=${event.strokeId} room=$_currentRoomId sender=$senderId',
      suppressInReleaseForMove:
          event.eventType == DrawEventType.drawMove && !kDebugMode,
    );
  }

  /// ===============================
  /// Undo 이벤트 전송
  /// ===============================
  void sendUndo(int strokeId, String senderId) {
    _emitOrQueue(
      'draw:clear',
      {
      'e': 'un',
      'sId': strokeId,
      'roomId': _currentRoomId,
      'senderId': senderId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      summary: 'draw:clear e=un sId=$strokeId room=$_currentRoomId sender=$senderId',
    );
  }

  /// ===============================
  /// Eraser 이벤트 전송 (특정 획 삭제)
  /// ===============================
  void sendEraser(int strokeId, String senderId) {
    _emitOrQueue(
      'draw:clear',
      {
      'e': 'er',
      'sId': strokeId,
      'roomId': _currentRoomId,
      'senderId': senderId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      summary: 'draw:clear e=er sId=$strokeId room=$_currentRoomId sender=$senderId',
    );
  }

  /// ===============================
  /// 전체 캔버스 클리어 (교사 전용)
  /// ===============================
  void sendClearAll(String senderId) {
    _emitOrQueue(
      'draw:clear',
      {
      'e': 'cl',
      'roomId': _currentRoomId,
      'senderId': senderId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      summary: 'draw:clear e=cl room=$_currentRoomId sender=$senderId',
    );
  }

  /// ===============================
  /// 방 나가기
  /// ===============================
  void leaveRoom() {
    if (_socket == null || !_socket!.connected || _currentRoomId == null) {
      return;
    }
    _isRoomJoined = false;

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
    _currentClassId = null;
    _isRoomJoined = false;
    _pendingEmits.clear();
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

  void _emitOrQueue(
    String eventName,
    Map<String, dynamic> payload, {
    required String summary,
    bool suppressInReleaseForMove = false,
  }) {
    if (_socket == null) {
      debugPrint('[socket][send] skipped: socket not initialized $summary');
      return;
    }
    if (!_socket!.connected) {
      debugPrint('[socket][send] skipped: socket disconnected $summary');
      return;
    }
    if (!_isRoomJoined) {
      _pendingEmits.add({
        'event': eventName,
        'payload': payload,
        'summary': summary,
      });
      debugPrint('[socket][send] queued(not_joined) $summary');
      return;
    }

    _socket!.emit(eventName, payload);
    if (!suppressInReleaseForMove) {
      debugPrint('[socket][send] $summary');
    }
  }

  void _flushPendingEmits() {
    if (_socket == null || !_socket!.connected || !_isRoomJoined) {
      return;
    }
    if (_pendingEmits.isEmpty) return;
    debugPrint('[socket] flushing pending emits count=${_pendingEmits.length}');
    for (final queued in _pendingEmits) {
      final event = queued['event'] as String?;
      final payload = queued['payload'] as Map<String, dynamic>?;
      final summary = queued['summary'] as String?;
      if (event == null || payload == null) continue;
      _socket!.emit(event, payload);
      if (summary != null) {
        debugPrint('[socket][send] $summary');
      }
    }
    _pendingEmits.clear();
  }
}
