import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

/// ===============================
/// 인증 서비스 (보안 강화)
/// flutter_secure_storage 사용
/// ===============================
class AuthService {
  static const _storage = FlutterSecureStorage();

  // Key 상수
  static const String _tokenKey = 'jwt_token';
  static const String _userIdKey = 'user_id';
  static const String _roleKey = 'user_role';
  static const String _displayNameKey = 'display_name';
  static const String _studentNumberKey = 'student_number';

  /// JWT 토큰 저장
  static Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
    debugPrint('✅ JWT Token saved (secure)');
  }

  /// JWT 토큰 가져오기
  static Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  /// 사용자 정보 저장 (로그인 시)
  static Future<void> saveUserInfo({
    required String userId,
    required String role,
    required String token,
  }) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userIdKey, value: userId);
    await _storage.write(key: _roleKey, value: role);
    debugPrint('✅ User info saved (secure): $userId ($role)');
  }

  /// 사용자 ID 가져오기
  static Future<String?> getUserId() async {
    return await _storage.read(key: _userIdKey);
  }

  /// 사용자 Role 가져오기 (teacher/student)
  static Future<String?> getRole() async {
    return await _storage.read(key: _roleKey);
  }

  /// 회원가입에서 입력한 프로필 저장
  static Future<void> saveProfile({
    required String displayName,
    String? studentNumber,
  }) async {
    await _storage.write(key: _displayNameKey, value: displayName);
    if (studentNumber != null) {
      final userId = await getUserId();
      final key = _studentNumberStorageKey(userId);
      if (studentNumber.isEmpty) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: studentNumber);
      }
    }
  }

  static Future<String?> getDisplayName() async {
    return await _storage.read(key: _displayNameKey);
  }

  static Future<String?> getStudentNumber() async {
    final userId = await getUserId();
    final stored = await _storage.read(key: _studentNumberStorageKey(userId));
    return stored ?? await _storage.read(key: _studentNumberKey);
  }

  static String _studentNumberStorageKey(String? userId) {
    final normalized = userId?.trim();
    return normalized == null || normalized.isEmpty
        ? _studentNumberKey
        : '${_studentNumberKey}_$normalized';
  }

  /// 로그인 여부 확인
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// 로그아웃 (토큰 삭제)
  static Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _roleKey);
    await _storage.delete(key: _displayNameKey);
    await _storage.delete(key: _studentNumberKey);
    debugPrint('✅ Logged out (secure)');
  }

  /// 전체 삭제 (앱 초기화용)
  static Future<void> clearAll() async {
    await _storage.deleteAll();
    debugPrint('✅ All data cleared (secure)');
  }
}
