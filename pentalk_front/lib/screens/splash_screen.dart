import 'package:flutter/material.dart';
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