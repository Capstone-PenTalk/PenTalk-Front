import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/drawing_models.dart';
import '../models/participant_model.dart';

class SocketService {
  static const String _tokenStoragePrefix = 'dev_socket_jwt';

  IO.Socket? _socket;
  String? _currentRoomId;
  String? _currentUserId;
  String? _currentMaterialId;
  int? _currentPageNumber;
  String? _currentClassId;
  bool _currentIsTeacher = false;
  bool _isRoomJoined = false;
  final List<Map<String, dynamic>> _pendingEmits = [];

  // 인증 실패 시 캐시 토큰 갱신 후 1회 재연결하기 위한 상태
  String? _lastServerUrl;
  bool _authRetryInProgress = false;
  bool _hasRetriedAuth = false;

  Function(DrawEvent)? onDrawEventReceived;
  Function(String)? onUserJoined;
  Function(String)? onUserLeft;
  Function()? onConnected;
  Function()? onDisconnected;
  Function(dynamic)? onError;
  Function(List<dynamic>)? onSyncState;
  Function(Map<String, dynamic>)? onSessionEnded;
  Function(Map<String, dynamic>)? onRoomJoined;
  Function(Map<String, dynamic>)? onPollStart;
  Function(Map<String, dynamic>)? onPollResult;
  Function(Map<String, dynamic>)? onPollEnd;
  Function(Map<String, dynamic>)? onSyncStateRaw;
  Function(Map<String, dynamic>)? onChatMessage;
  Function(Map<String, dynamic>)? onDirectMessage;
  Function(Map<String, dynamic>)? onQuestionAck;
  Function(Map<String, dynamic>)? onQuestionNew;
  Function(List<dynamic>)? onQuestionListResult;
  Function(Map<String, dynamic>)? onQuestionAnswered;
  // 자료 업로드 실시간 알림 (수업 중)
  Function(Map<String, dynamic>)? onMaterialUploaded;
  Function(List<Participant>)? onPresenceState;
  Function(Participant)? onPresenceJoin;
  Function(String userId, String role)? onPresenceLeave;

  bool get isConnected => _socket?.connected ?? false;
  String? get currentRoomId => _currentRoomId;
  String? get currentUserId => _currentUserId;

  Future<void> connect({
    required String serverUrl,
    required String userId,
    required String roomId,
    bool isTeacher = false,
    String? classId,
    String? materialId,
    int? pageNumber,
    bool isInternalRetry = false,
    }) async {
    try {
      _currentUserId = userId;
      _currentRoomId = roomId;
      _currentMaterialId = materialId;
      _currentPageNumber = pageNumber;
      _currentClassId = classId;
      _currentIsTeacher = isTeacher;
      _isRoomJoined = false;
      _pendingEmits.clear();
      _lastServerUrl = serverUrl;
      if (!isInternalRetry) _hasRetriedAuth = false;

      final normalizedUrl = _normalizeServerUrl(serverUrl);
      debugPrint('[socket] Connecting to $normalizedUrl');

      final uri = Uri.parse(normalizedUrl);
      final role = isTeacher ? 'teacher' : 'student';
      final explicitToken = uri.queryParameters['token'];
      final token = (explicitToken != null && explicitToken.isNotEmpty)
          ? explicitToken
          : await _getOrCreateDevToken(uri: uri, userId: userId, role: role);

      final queryParams = Map<String, String>.from(uri.queryParameters)
        ..remove('token');
      final effectivePort = (uri.hasPort && uri.port > 0)
          ? uri.port
          : (uri.scheme == 'https' ? 443 : 80);
      // Socket.IO는 기본 네임스페이스('/')로만 연결한다.
      // 잘못된 API 경로(/materials/pdf 등)가 들어오면 namespace 에러가 나므로 path는 버린다.
      final baseUrl = StringBuffer()
        ..write(uri.scheme)
        ..write('://')
        ..write(uri.host)
        ..write(':')
        ..write(effectivePort);

      final options = IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setExtraHeaders({
        'bypass-tunnel-reminder': 'true',
        'user-id': userId,
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      });
      if (queryParams.isNotEmpty) options.setQuery(queryParams);
      if (token.isNotEmpty) options.setAuth({'token': token});

      _socket = IO.io(baseUrl.toString(), options.build());
      _setupEventListeners();
      _socket!.connect();
    } catch (e) {
      debugPrint('[socket][error] connect threw: $e');
      onError?.call(e);
    }
  }

  String _normalizeServerUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    final typoFixed = trimmed
        .replaceFirst(RegExp(r'^hhttps://'), 'https://')
        .replaceFirst(RegExp(r'^hhttp://'), 'http://');
    if (typoFixed.startsWith('http://') || typoFixed.startsWith('https://')) {
      return typoFixed;
    }
    return 'https://$typoFixed';
  }

  Future<String> _getOrCreateDevToken({
    required Uri uri,
    required String userId,
    required String role,
    bool forceRefresh = false,
  }) async {
    final effectivePort = (uri.hasPort && uri.port > 0)
        ? uri.port
        : (uri.scheme == 'https' ? 443 : 80);
    final storageKey = [
      _tokenStoragePrefix, uri.scheme, uri.host, '$effectivePort', role, userId
    ].join(':');

    final prefs = await SharedPreferences.getInstance();

    if (forceRefresh) {
      await prefs.remove(storageKey);
      debugPrint('[socket][auth] cleared cached token role=$role userId=$userId');
    } else {
      final cachedToken = prefs.getString(storageKey);
      if (cachedToken != null && cachedToken.isNotEmpty) {
        debugPrint('[socket][auth] using cached token role=$role userId=$userId');
        return cachedToken;
      }
    }

    final authUri = Uri(
        scheme: uri.scheme, host: uri.host, port: effectivePort, path: '/auth/dev-login');
    final response = await http.post(authUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId, 'role': role}));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('dev-login failed status=${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) throw Exception('dev-login invalid response');
    final token = decoded['token']?.toString() ?? '';
    if (token.isEmpty) throw Exception('dev-login token missing');
    await prefs.setString(storageKey, token);
    debugPrint('[socket][auth] fetched fresh token role=$role userId=$userId');
    return token;
  }

  /// 캐시된 토큰이 서버에서 거부(UNAUTHORIZED)됐을 때 1회 한정으로
  /// 토큰을 새로 발급받아 재연결한다.
  bool _isAuthError(dynamic error) {
    final text = error is Map ? error['message']?.toString() : error?.toString();
    if (text == null) return false;
    final normalized = text.toUpperCase();
    return normalized.contains('UNAUTHORIZED') ||
        normalized.contains('INVALID_TOKEN') ||
        normalized.contains('JWT');
  }

  Future<void> _retryConnectionWithFreshToken() async {
    final serverUrl = _lastServerUrl;
    final userId = _currentUserId;
    final roomId = _currentRoomId;
    if (serverUrl == null || userId == null || roomId == null) return;
    if (_authRetryInProgress || _hasRetriedAuth) return;

    _authRetryInProgress = true;
    _hasRetriedAuth = true;
    debugPrint('[socket][auth] retrying connection with fresh token');

    try {
      final normalizedUrl = _normalizeServerUrl(serverUrl);
      final uri = Uri.parse(normalizedUrl);
      final role = _currentIsTeacher ? 'teacher' : 'student';
      await _getOrCreateDevToken(
        uri: uri,
        userId: userId,
        role: role,
        forceRefresh: true,
      );

      _socket?.dispose();
      _socket = null;

      await connect(
        serverUrl: serverUrl,
        userId: userId,
        roomId: roomId,
        isTeacher: _currentIsTeacher,
        classId: _currentClassId,
        materialId: _currentMaterialId,
        pageNumber: _currentPageNumber,
        isInternalRetry: true,
      );
    } catch (e) {
      debugPrint('[socket][auth] retry failed: $e');
    } finally {
      _authRetryInProgress = false;
    }
  }

  void _setupEventListeners() {
    if (_socket == null) return;

    _socket!.on('connect', (_) {
      debugPrint('[socket] connected id=${_socket!.id}');
      _isRoomJoined = false;
      onConnected?.call();
      if (_currentRoomId != null && _currentUserId != null) {
        _joinRoom(_currentRoomId!, _currentUserId!, _currentIsTeacher,
            classId: _currentClassId, materialId: _currentMaterialId);
      }
    });

    _socket!.on('disconnect', (_) {
      debugPrint('[socket] disconnected');
      _isRoomJoined = false;
      _pendingEmits.clear();
      onDisconnected?.call();
    });

    _socket!.on('connect_error', (error) {
      debugPrint('[socket][error] connect_error: $error');
      if (_isAuthError(error)) {
        _retryConnectionWithFreshToken();
      }
      onError?.call(error);
    });

    _socket!.on('draw:append', (data) {
      debugPrint('[socket][recv] draw:append from=${data is Map ? data['userId'] : null}');
      try {
        onDrawEventReceived?.call(DrawEvent.fromJson(Map<String, dynamic>.from(data)));
      } catch (e) {
        debugPrint('[socket][error] draw:append: $e');
      }
    });

    _socket!.on('draw:clear', (data) {
      final payload = data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
      onDrawEventReceived?.call(
        DrawEvent.fromJson({
          'e': 'cl',
          'sId': 0,
          ...payload,
        }),
      );
    });

    _socket!.on('user_joined', (data) => onUserJoined?.call(data['userId'] as String));
    _socket!.on('user_left', (data) => onUserLeft?.call(data['userId'] as String));

    // JOIN_SUCCESS → pending emit flush → DrawingProvider에서 sync:request 전송
    _socket!.on('join_success', (data) {
      debugPrint('[socket] join_success roomId=${data['roomId']}');
      _isRoomJoined = true;
      _flushPendingEmits();
      onRoomJoined?.call(Map<String, dynamic>.from(data));
    });

    _socket!.on('sync:state', (data) {
      if (data is Map) {
        onSyncStateRaw?.call(Map<String, dynamic>.from(data));
      }
      if (data is Map) {
        final strokes = data['strokes'] as List?;
        if (strokes != null) onSyncState?.call(strokes);
      } else if (data is List) {
        onSyncState?.call(data);
      }
    });

    // 하위 호환: 구 이벤트명
    _socket!.on('sync_state', (data) {
      if (data is Map) {
        final strokes = data['strokes'] as List?;
        if (strokes != null) onSyncState?.call(strokes);
      } else if (data is List) {
        onSyncState?.call(data);
      }
    });

    _socket!.on('session:ended', (data) {
      if (data is Map) onSessionEnded?.call(Map<String, dynamic>.from(data));
    });

    _socket!.on('server_error', (error) {
      debugPrint('[socket][error] server_error: $error');
      final map = error is Map ? Map<String, dynamic>.from(error) : null;
      if (map?['code']?.toString() == 'NOT_JOINED') {
        _isRoomJoined = false;
        if (_currentRoomId != null && _currentUserId != null) {
          _joinRoom(_currentRoomId!, _currentUserId!, _currentIsTeacher,
              classId: _currentClassId, materialId: _currentMaterialId);
        }
      }
      onError?.call(error);
    });

    _socket!.on('error', (error) {
      if (_isAuthError(error)) {
        _retryConnectionWithFreshToken();
      }
      onError?.call(error);
    });

    // Poll 이벤트
    _socket!.on('poll:start', (data) {
      if (data is Map) onPollStart?.call(Map<String, dynamic>.from(data));
    });
    _socket!.on('poll:result', (data) {
      if (data is Map) onPollResult?.call(Map<String, dynamic>.from(data));
    });
    _socket!.on('poll:end', (data) {
      if (data is Map) onPollEnd?.call(Map<String, dynamic>.from(data));
    });

    // material:uploaded → 수업 중 자료 추가 시 실시간 반영
    _socket!.on('material:uploaded', (data) {
      debugPrint('[socket] material:uploaded received: $data');
      if (data is Map) onMaterialUploaded?.call(Map<String, dynamic>.from(data));
    });

    // Chat / DM
    _socket!.on('receive_message', (data) {
      if (data is Map) onChatMessage?.call(Map<String, dynamic>.from(data));
    });
    _socket!.on('receive_dm', (data) {
      if (data is Map) onDirectMessage?.call(Map<String, dynamic>.from(data));
    });

    // Q&A
    _socket!.on('question:ack', (data) {
      if (data is Map) onQuestionAck?.call(Map<String, dynamic>.from(data));
    });
    _socket!.on('question:new', (data) {
      if (data is Map) onQuestionNew?.call(Map<String, dynamic>.from(data));
    });
    _socket!.on('question:list:result', (data) {
      if (data is! Map) return;
      final questions = data['questions'] as List?;
      if (questions != null) onQuestionListResult?.call(questions);
    });
    _socket!.on('question:answered', (data) {
      if (data is Map) {
        onQuestionAnswered?.call(Map<String, dynamic>.from(data));
      }
    });

    // Presence 이벤트
    _socket!.on('presence:state', (data) {
      debugPrint('[socket][recv] presence:state: $data');
      if (data is! Map) return;
      final usersList = data['users'];
      if (usersList is! List) return;
      onPresenceState?.call(usersList
          .where((u) => u is Map)
          .map((u) => Participant.fromJson(Map<String, dynamic>.from(u)))
          .toList());
    });
    _socket!.on('presence:join', (data) {
      debugPrint('[socket][recv] presence:join: $data');
      if (data is! Map) return;
      try {
        onPresenceJoin?.call(Participant.fromJson(Map<String, dynamic>.from(data)));
      } catch (e) {
        debugPrint('[socket][error] presence:join: $e');
      }
    });
    _socket!.on('presence:leave', (data) {
      debugPrint('[socket][recv] presence:leave: $data');
      if (data is! Map) return;
      final userId = data['userId'] as String?;
      final role = data['role'] as String?;
      if (userId != null && role != null) onPresenceLeave?.call(userId, role);
    });
  }

  void setupPresenceListeners() {}

  void removePresenceListeners() {
    if (_socket == null) return;
    _socket!..off('presence:state')..off('presence:join')..off('presence:leave');
    onPresenceState = null;
    onPresenceJoin = null;
    onPresenceLeave = null;
  }

  void _joinRoom(String roomId, String userId, bool isTeacher,
      {String? classId, String? materialId}) {
    if (_socket == null || !_socket!.connected) return;
    final payload = {
      'roomId': roomId,
      if (materialId != null && materialId.isNotEmpty) 'materialId': materialId,
    };
    _socket!.emit('join_room', payload);
    debugPrint('[socket][send] join_room payload=${jsonEncode(payload)} '
        'userId=$userId role=${isTeacher ? 'teacher' : 'student'} '
        'classId=$classId');
  }

  void sendDrawEvent(DrawEvent event) {
    _currentMaterialId = event.materialId ?? _currentMaterialId;
    _currentPageNumber = event.pageNumber ?? _currentPageNumber;
    final payload = {
      ...event.toJson(),
    };
    _emitOrQueue(
      'draw:append',
      payload,
      summary: _drawAppendSummary(payload),
    );
  }

  void sendUndo(int strokeId) {
    // 서버 스펙에는 undo 이벤트가 없어 네트워크 송신하지 않음.
    debugPrint('[socket][send] skipped undo(not in server spec) sId=$strokeId');
  }

  void sendClearAll({
    required String? materialId,
    required int? pageNumber,
    required String scope,
  }) {
    final payload = {
      if (materialId != null && materialId.isNotEmpty) 'materialId': materialId,
      if (pageNumber != null) 'pageNumber': pageNumber,
      'scope': scope,
    };
    _emitOrQueue(
      'draw:clear',
      payload,
      summary: 'draw:clear payload=${jsonEncode(payload)}',
    );
  }

  void sendPollAnswer({required String pollId, required dynamic optionId}) {
    _emitOrQueue('poll:answer', {
      'pollId': pollId,
      'optionId': optionId,
    }, summary: 'poll:answer pollId=$pollId');
  }

  void sendPollStart({
    required String question,
    required List<Map<String, dynamic>> options,
    int? duration,
  }) {
    final formattedOptions = options
        .asMap()
        .entries
        .map((entry) => {
      'id': (entry.key + 1).toString(),
      'text': entry.value['text']?.toString() ?? '',
    })
        .where((o) => (o['text'] as String).isNotEmpty)
        .toList();

    _emitOrQueue('poll:start', {
      'question': question,
      'options': formattedOptions,
      if (duration != null) 'duration': duration.toInt(),
    }, summary: 'poll:start');
  }

  void sendPollEnd(String pollId) {
    _emitOrQueue('poll:end', {
      'pollId': pollId,
    }, summary: 'poll:end pollId=$pollId');
  }

  void requestSync({int? lastTick, String? materialId, int? pageNumber}) {
    if (_socket == null || !_socket!.connected) return;
    final payload = {
      if (lastTick != null) 'lastTick': lastTick,
      if (materialId != null && materialId.isNotEmpty) 'materialId': materialId,
      if (pageNumber != null) 'pageNumber': pageNumber,
    };
    _socket!.emit('sync:request', payload);
    debugPrint('[socket][send] sync:request payload=${jsonEncode(payload)}');
  }

  void sendMessage(String content) {
    _emitOrQueue(
      'send_message',
      {'content': content},
      summary: 'send_message',
    );
  }

  void sendTeacherDm(String message) {
    _emitOrQueue(
      'teacher_send_dm',
      {'message': message},
      summary: 'teacher_send_dm',
    );
  }

  void askQuestion({required String content, bool isAnonymous = false}) {
    _emitOrQueue(
      'question:ask',
      {'content': content, 'isAnonymous': isAnonymous},
      summary: 'question:ask',
    );
  }

  void requestQuestionList() {
    _emitOrQueue(
      'question:list',
      const {},
      summary: 'question:list',
    );
  }

  void answerQuestion({required String questionId, required String answer}) {
    _emitOrQueue(
      'question:answer',
      {'questionId': questionId, 'answer': answer},
      summary: 'question:answer',
    );
  }

  void leaveRoom() {
    if (_socket == null || !_socket!.connected || _currentRoomId == null) return;
    _isRoomJoined = false;
    _socket!.emit('leave_room', {
      'roomId': _currentRoomId, 'userId': _currentUserId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void disconnect() {
    leaveRoom();
    removePresenceListeners();
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

  Future<void> reconnect() async {
    if (_socket?.connected == true) return;
    _socket?.connect();
  }

  void _emitOrQueue(String eventName, Map<String, dynamic> payload,
      {required String summary}) {
    if (_socket == null || !_socket!.connected) {
      debugPrint('[socket][send] skipped(not connected) $summary');
      return;
    }
    if (!_isRoomJoined) {
      _pendingEmits.add({'event': eventName, 'payload': payload, 'summary': summary});
      debugPrint('[socket][send] queued(not_joined) $summary');
      return;
    }
    _socket!.emit(eventName, payload);
    debugPrint('[socket][send] $summary');
  }

  void _flushPendingEmits() {
    if (_socket == null || !_socket!.connected || !_isRoomJoined) return;
    if (_pendingEmits.isEmpty) return;
    debugPrint('[socket] flushing ${_pendingEmits.length} pending emits');
    for (final q in _pendingEmits) {
      final event = q['event'] as String?;
      final payload = q['payload'] as Map<String, dynamic>?;
      final summary = q['summary'] as String?;
      if (event != null && payload != null) {
        _socket!.emit(event, payload);
        if (summary != null) {
          debugPrint('[socket][send] flushed $summary');
        }
      }
    }
    _pendingEmits.clear();
  }

  String _drawAppendSummary(Map<String, dynamic> payload) {
    return 'draw:append payload=${jsonEncode(payload)}';
  }
}
