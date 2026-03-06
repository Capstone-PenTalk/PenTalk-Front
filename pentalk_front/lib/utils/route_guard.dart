import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/access_denied_dialog.dart';


/// 라우팅 가드
/// 인증 상태 확인 후 화면 이동

class RouteGuard {
  /// 세션 입장 전 인증 확인
  ///
  /// 사용 예:
  /// ```dart
  /// final canJoin = await RouteGuard.canJoinSession(context);
  /// if (canJoin) {
  ///   Navigator.push(...);
  /// }
  /// ```
  static Future<bool> canJoinSession(BuildContext context) async {
    // 1. 토큰 확인
    final token = await AuthService.getToken();

    if (token == null || token.isEmpty) {
      // 토큰 없음 → 로그인 필요 팝업
      if (context.mounted) {
        await AccessDeniedDialog.showLoginRequired(context);
      }
      return false;
    }

    // 2. 사용자 정보 확인
    final userId = await AuthService.getUserId();
    final role = await AuthService.getRole();

    if (userId == null || role == null) {
      // 정보 불완전 → 로그인 필요
      if (context.mounted) {
        await AccessDeniedDialog.showLoginRequired(context);
      }
      return false;
    }

    // 3. role 검증
    if (role != 'teacher' && role != 'student') {
      // 잘못된 role
      if (context.mounted) {
        await AccessDeniedDialog.showPermissionDenied(context);
      }
      return false;
    }

    // ✅ 모든 검증 통과
    return true;
  }

  /// 교사 전용 기능 접근 확인
  static Future<bool> requireTeacher(BuildContext context) async {
    // 1. 기본 인증 확인
    final isLoggedIn = await canJoinSession(context);
    if (!isLoggedIn) return false;

    // 2. 교사 권한 확인
    final role = await AuthService.getRole();

    if (role != 'teacher') {
      if (context.mounted) {
        await AccessDeniedDialog.showPermissionDenied(context);
      }
      return false;
    }

    return true;
  }

  /// 로그인 상태 확인 (팝업 없음)
  static Future<bool> isAuthenticated() async {
    final token = await AuthService.getToken();
    final userId = await AuthService.getUserId();
    final role = await AuthService.getRole();

    return token != null &&
        token.isNotEmpty &&
        userId != null &&
        role != null;
  }

  /// 초기 라우트 결정
  ///
  /// main.dart에서 사용:
  /// ```dart
  /// home: await RouteGuard.getInitialRoute(),
  /// ```
  static Future<String> getInitialRoute() async {
    final isAuth = await isAuthenticated();
    return isAuth ? '/home' : '/login';
  }
}