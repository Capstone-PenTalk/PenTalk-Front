import 'dart:convert';

import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../services/session_storage.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'drawing_screen.dart';
import 'student_home_screen.dart';
import 'teacher_home_screen.dart';

/// ===============================
/// Splash Screen
/// 자동 로그인 + 역할에 따른 화면 분기
/// ===============================
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _statusMessage = '앱을 시작하는 중...';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final handledByLink = await _tryHandleUrlSessionJoin();
      if (handledByLink) return;

      setState(() => _statusMessage = '로그인 확인 중...');
      await Future.delayed(const Duration(milliseconds: 500));

      final token = await AuthService.getToken();
      if (token == null) {
        _navigateToLogin();
        return;
      }

      // 역할 확인
      final role = await AuthService.getRole();

      // 저장된 세션 확인 (자동 재join)
      setState(() => _statusMessage = '이전 세션 확인 중...');
      await Future.delayed(const Duration(milliseconds: 500));

      final session = await SessionStorage.getLastSession();

      if (session != null) {
        setState(() => _statusMessage = '세션 상태 확인 중...');
        await Future.delayed(const Duration(milliseconds: 500));

        final statusResponse = await ApiService.getSessionStatus(
          sessionId: session.sessionId,
        );

        if (statusResponse.success &&
            statusResponse.data != null &&
            statusResponse.data!.isActive) {
          // 세션이 활성 → 자동 재join
          if (mounted) _navigateToDrawingScreen(session);
          return;
        } else {
          // 세션 만료 → 세션 정보 삭제
          await SessionStorage.clearSession();
        }
      }

      // 역할에 따라 홈 화면 분기
      if (mounted) {
        if (role == 'teacher') {
          _navigateToTeacherHome();
        } else {
          _navigateToStudentHome();
        }
      }
    } catch (e) {
      debugPrint('❌ Splash error: $e');
      await SessionStorage.clearSession();
      if (mounted) _navigateToLogin();
    }
  }

  Future<bool> _tryHandleUrlSessionJoin() async {
    final uri = Uri.base;
    final roomId = uri.queryParameters['roomId']?.trim();
    final token = uri.queryParameters['token']?.trim();
    if (roomId == null || roomId.isEmpty || token == null || token.isEmpty) {
      return false;
    }

    final classId = uri.queryParameters['classId']?.trim();
    final materialId = uri.queryParameters['materialId']?.trim();
    final materialTitle =
        uri.queryParameters['materialTitle']?.trim().isNotEmpty == true
            ? uri.queryParameters['materialTitle']!.trim()
            : '실시간 수업';
    final backgroundUrl = uri.queryParameters['backgroundUrl']?.trim();
    final claims = _decodeJwtClaims(token);
    final userId = (claims?['userId']?.toString().trim().isNotEmpty == true)
        ? claims!['userId'].toString().trim()
        : 'guest';
    final role = (claims?['role']?.toString().trim().toLowerCase() == 'teacher')
        ? 'teacher'
        : 'student';
    final isTeacher = role == 'teacher';

    await AuthService.saveUserInfo(userId: userId, role: role, token: token);

    final queryServerUrl = uri.queryParameters['serverUrl']?.trim();
    final baseServerUrl = (queryServerUrl != null && queryServerUrl.isNotEmpty)
        ? queryServerUrl
        : _resolveJoinServerUrl(isTeacher: isTeacher, pageUri: uri);
    final serverUrlWithToken = '$baseServerUrl?token=$token';

    if (!mounted) return true;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DrawingScreen(
          materialTitle: materialTitle,
          backgroundUrl: (backgroundUrl != null && backgroundUrl.isNotEmpty)
              ? backgroundUrl
              : null,
          isTeacher: isTeacher,
          serverUrl: serverUrlWithToken,
          roomId: roomId,
          userId: userId,
          classId: (classId != null && classId.isNotEmpty) ? classId : null,
          materialId:
              (materialId != null && materialId.isNotEmpty) ? materialId : null,
          sessionId: roomId,
        ),
      ),
    );
    return true;
  }

  String _resolveJoinServerUrl({
    required bool isTeacher,
    required Uri pageUri,
  }) {
    final configured = AppConfig.resolveSocketUrl(isTeacher: isTeacher);
    final host = pageUri.host.toLowerCase();
    final isLocalHost = host == 'localhost' || host == '127.0.0.1';
    final usingDefaultRailway = configured.contains('up.railway.app');
    if (isLocalHost && usingDefaultRailway) {
      return 'http://localhost:3000';
    }
    return configured;
  }

  Map<String, dynamic>? _decodeJwtClaims(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final normalized = base64Url.normalize(parts[1]);
      final payload = utf8.decode(base64Url.decode(normalized));
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return null;
  }

  void _navigateToLogin() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _navigateToStudentHome() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const StudentHomeScreen()),
    );
  }

  void _navigateToTeacherHome() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const TeacherHomeScreen()),
    );
  }

  void _navigateToDrawingScreen(SessionInfo session) async {
    final userId = await AuthService.getUserId();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DrawingScreen(
          materialTitle: session.materialTitle,
          backgroundUrl: session.backgroundUrl,
          isTeacher: session.isTeacher,
          serverUrl: session.serverUrl,
          roomId: session.roomId,
          userId: userId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.edit_note, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            const Text(
              'PenTalk',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              _statusMessage,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
