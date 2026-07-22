import 'dart:convert';

import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../models/document_source.dart';
import '../services/auth_service.dart';
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

      if (!AppConfig.enableAutoLogin) {
        _navigateToLogin();
        return;
      }

      setState(() => _statusMessage = '로그인 확인 중...');
      await Future.delayed(const Duration(milliseconds: 500));

      final token = await AuthService.getToken();
      if (token == null) {
        _navigateToLogin();
        return;
      }

      // 역할 확인
      final storedUserId = await AuthService.getUserId();
      final role = await AuthService.getRole();
      final shouldBypassServerLogin =
          role == 'teacher' && storedUserId?.trim() == 'teacher2';
      if (AppConfig.shouldUseServerLogin && !shouldBypassServerLogin) {
        final normalizedUserId = _normalizeDevLoginUserId(
          userId: storedUserId,
          role: role,
        );
        if (normalizedUserId == null ||
            normalizedUserId.isEmpty ||
            role == null ||
            role.isEmpty) {
          await AuthService.logout();
          _navigateToLogin();
          return;
        }
        setState(() => _statusMessage = '로그인 갱신 중...');
        final loginResponse = await ApiService.devLogin(
          userId: normalizedUserId,
          role: role,
        );
        if (!loginResponse.success || loginResponse.data == null) {
          await AuthService.logout();
          _navigateToLogin();
          return;
        }
        final login = loginResponse.data!;
        await AuthService.saveUserInfo(
          userId: login.userId,
          role: login.role,
          token: login.token,
        );
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
      if (mounted) _navigateToLogin();
    }
  }

  String? _normalizeDevLoginUserId({
    required String? userId,
    required String? role,
  }) {
    final normalizedRole = role?.trim().toLowerCase();
    final trimmedUserId = userId?.trim();
    if (normalizedRole == null || normalizedRole.isEmpty) return trimmedUserId;

    if (normalizedRole == 'teacher') {
      if (trimmedUserId == null ||
          trimmedUserId.isEmpty ||
          trimmedUserId == 'teacher_local') {
        return 'teacher1';
      }
      return trimmedUserId;
    }

    if (normalizedRole == 'student') {
      if (trimmedUserId == null ||
          trimmedUserId.isEmpty ||
          trimmedUserId == 'student_local') {
        return 'student1';
      }
      return trimmedUserId;
    }

    return trimmedUserId;
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
    var resolvedMaterialTitle = materialTitle;
    var resolvedBackgroundUrl = backgroundUrl;
    var resolvedMaterialId = materialId;
    var documentPages = const <DocumentPageSource>[];

    if (classId != null && classId.isNotEmpty) {
      try {
        final materials = await ApiService.getMaterials(
          classId: classId,
          sessionId: roomId,
        );
        final selectedMaterial = materials.firstWhere(
          (material) =>
              resolvedMaterialId != null &&
              resolvedMaterialId.isNotEmpty &&
              material.id == resolvedMaterialId,
          orElse: () => materials.isNotEmpty
              ? materials.first
              : throw StateError('No materials'),
        );
        resolvedMaterialId = selectedMaterial.id;
        resolvedMaterialTitle = selectedMaterial.name;
        resolvedBackgroundUrl = selectedMaterial.url.isNotEmpty
            ? selectedMaterial.url
            : resolvedBackgroundUrl;
        documentPages = selectedMaterial.pages;
      } catch (e) {
        debugPrint('Failed to hydrate web join material: $e');
      }
    }

    if (!mounted) return true;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DrawingScreen(
          materialTitle: resolvedMaterialTitle,
          backgroundUrl:
              (resolvedBackgroundUrl != null &&
                  resolvedBackgroundUrl.isNotEmpty)
              ? resolvedBackgroundUrl
              : null,
          isPdfDocument: documentPages.isNotEmpty,
          documentPages: documentPages,
          isTeacher: isTeacher,
          serverUrl: serverUrlWithToken,
          roomId: roomId,
          userId: userId,
          classId: (classId != null && classId.isNotEmpty) ? classId : null,
          materialId:
              (resolvedMaterialId != null && resolvedMaterialId.isNotEmpty)
              ? resolvedMaterialId
              : null,
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
