import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// ===============================
/// 세션 정보 저장/불러오기 서비스
/// SharedPreferences 사용
/// ===============================
class SessionStorage {
  static const String _keySessionId = 'last_session_id';
  static const String _keyRoomId = 'last_room_id';
  static const String _keyRole = 'last_role';
  static const String _keyMaterialTitle = 'last_material_title';
  static const String _keyBackgroundUrl = 'last_background_url';
  static const String _keyServerUrl = 'last_server_url';
  static const String _keyLastTick = 'last_tick';
  static const String _keyJoinedAt = 'last_joined_at';

  /// ===============================
  /// 세션 정보 저장
  /// ===============================
  static Future<void> saveSession({
    required String sessionId,
    required String roomId,
    required String role,
    required String materialTitle,
    String? backgroundUrl,
    required String serverUrl,
    int? lastTick,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(_keySessionId, sessionId);
      await prefs.setString(_keyRoomId, roomId);
      await prefs.setString(_keyRole, role);
      await prefs.setString(_keyMaterialTitle, materialTitle);

      if (backgroundUrl != null) {
        await prefs.setString(_keyBackgroundUrl, backgroundUrl);
      } else {
        await prefs.remove(_keyBackgroundUrl);
      }

      await prefs.setString(_keyServerUrl, serverUrl);

      if (lastTick != null) {
        await prefs.setInt(_keyLastTick, lastTick);
      }

      // 저장 시점 기록
      await prefs.setInt(_keyJoinedAt, DateTime.now().millisecondsSinceEpoch);

      debugPrint('✅ Session saved: $sessionId (tick: $lastTick)');
    } catch (e) {
      debugPrint('❌ Failed to save session: $e');
    }
  }

  /// ===============================
  /// lastTick만 업데이트 (빠른 저장)
  /// ===============================
  static Future<void> updateLastTick(int tick) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyLastTick, tick);
      debugPrint('🔄 LastTick updated: $tick');
    } catch (e) {
      debugPrint('❌ Failed to update lastTick: $e');
    }
  }

  /// ===============================
  /// 저장된 세션 정보 불러오기
  /// ===============================
  static Future<SessionInfo?> getLastSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final sessionId = prefs.getString(_keySessionId);
      final roomId = prefs.getString(_keyRoomId);
      final role = prefs.getString(_keyRole);
      final materialTitle = prefs.getString(_keyMaterialTitle);
      final serverUrl = prefs.getString(_keyServerUrl);

      // 필수 정보가 없으면 null 반환
      if (sessionId == null ||
          roomId == null ||
          role == null ||
          materialTitle == null ||
          serverUrl == null) {
        return null;
      }

      final backgroundUrl = prefs.getString(_keyBackgroundUrl);
      final lastTick = prefs.getInt(_keyLastTick);
      final joinedAt = prefs.getInt(_keyJoinedAt);

      debugPrint('📥 Session loaded: $sessionId (tick: $lastTick)');

      return SessionInfo(
        sessionId: sessionId,
        roomId: roomId,
        role: role,
        materialTitle: materialTitle,
        backgroundUrl: backgroundUrl,
        serverUrl: serverUrl,
        lastTick: lastTick,
        joinedAt: joinedAt != null
            ? DateTime.fromMillisecondsSinceEpoch(joinedAt)
            : null,
      );
    } catch (e) {
      debugPrint('❌ Failed to load session: $e');
      return null;
    }
  }

  /// ===============================
  /// 세션 정보 삭제
  /// ===============================
  static Future<void> clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.remove(_keySessionId);
      await prefs.remove(_keyRoomId);
      await prefs.remove(_keyRole);
      await prefs.remove(_keyMaterialTitle);
      await prefs.remove(_keyBackgroundUrl);
      await prefs.remove(_keyServerUrl);
      await prefs.remove(_keyLastTick);
      await prefs.remove(_keyJoinedAt);

      debugPrint('🗑️ Session cleared');
    } catch (e) {
      debugPrint('❌ Failed to clear session: $e');
    }
  }

  /// ===============================
  /// 세션 정보 존재 여부
  /// ===============================
  static Future<bool> hasSession() async {
    final session = await getLastSession();
    return session != null;
  }
}

/// ===============================
/// 세션 정보 모델
/// ===============================
class SessionInfo {
  final String sessionId;
  final String roomId;
  final String role;
  final String materialTitle;
  final String? backgroundUrl;
  final String serverUrl;
  final int? lastTick;
  final DateTime? joinedAt;

  SessionInfo({
    required this.sessionId,
    required this.roomId,
    required this.role,
    required this.materialTitle,
    this.backgroundUrl,
    required this.serverUrl,
    this.lastTick,
    this.joinedAt,
  });

  bool get isTeacher => role == 'teacher';
  bool get isStudent => role == 'student';
}