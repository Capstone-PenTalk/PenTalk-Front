import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/session_storage.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'drawing_screen.dart';

/// ===============================
/// Splash Screen
/// 자동 로그인 및 세션 복구 처리
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

  /// ===============================
  /// 초기화 로직
  /// ===============================
  Future<void> _initialize() async {
    try {
      // 1. JWT 토큰 확인
      setState(() {
        _statusMessage = '로그인 확인 중...';
      });

      await Future.delayed(const Duration(milliseconds: 500));

      final token = await AuthService.getToken();

      if (token == null) {
        // 토큰 없음 → 로그인 화면
        debugPrint('❌ No token found → LoginScreen');
        _navigateToLogin();
        return;
      }

      debugPrint('✅ Token found');

      // 2. 저장된 세션 정보 확인
      setState(() {
        _statusMessage = '이전 세션 확인 중...';
      });

      await Future.delayed(const Duration(milliseconds: 500));

      final session = await SessionStorage.getLastSession();

      if (session == null) {
        // 세션 정보 없음 → 로그인 화면
        debugPrint('❌ No session found → LoginScreen');
        _navigateToLogin();
        return;
      }

      debugPrint('✅ Session found: ${session.sessionId}');

      // 3. 세션 상태 확인 (ACTIVE인지)
      setState(() {
        _statusMessage = '세션 상태 확인 중...';
      });

      await Future.delayed(const Duration(milliseconds: 500));

      final statusResponse = await ApiService.getSessionStatus(
        sessionId: session.sessionId,
      );

      if (!statusResponse.success || statusResponse.data == null) {
        // 세션 상태 확인 실패 → 세션 정보 삭제 → 알림 → 로그인 화면
        debugPrint('❌ Session status check failed: ${statusResponse.error}');
        await SessionStorage.clearSession();

        if (mounted) {
          _showSessionExpiredDialog('세션을 찾을 수 없습니다.');
        }
        return;
      }

      final status = statusResponse.data!;
      debugPrint('✅ Session status: ${status.status}');

      if (!status.isActive) {
        // 세션이 종료됨 → 세션 정보 삭제 → 알림 → 로그인 화면
        debugPrint('❌ Session not active → Clear & LoginScreen');
        await SessionStorage.clearSession();

        if (mounted) {
          _showSessionExpiredDialog('이전 세션이 종료되었습니다.');
        }
        return;
      }

      // 4. 세션이 ACTIVE → 자동 재join
      debugPrint('✅ Session is active → Auto rejoin');

      setState(() {
        _statusMessage = '세션에 다시 연결 중...';
      });

      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        _navigateToDrawingScreen(session);
      }

    } catch (e) {
      debugPrint('❌ Splash error: $e');

      // 에러 발생 → 세션 정보 삭제 → 로그인 화면
      await SessionStorage.clearSession();

      if (mounted) {
        _showSessionExpiredDialog('오류가 발생했습니다: $e');
      }
    }
  }

  /// ===============================
  /// 로그인 화면으로 이동
  /// ===============================
  void _navigateToLogin() {
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const LoginScreen(),
      ),
    );
  }

  /// ===============================
  /// DrawingScreen으로 이동 (자동 재join)
  /// ===============================
  void _navigateToDrawingScreen(SessionInfo session) {
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => DrawingScreen(
          materialTitle: session.materialTitle,
          backgroundUrl: session.backgroundUrl,
          isTeacher: session.isTeacher,
          serverUrl: session.serverUrl,
          roomId: session.roomId,
          userId: null,  // AuthService에서 가져옴
          // 자동 재join 시 lastTick 전달은 DrawingProvider에서 처리
        ),
      ),
    );
  }

  /// ===============================
  /// 세션 만료 알림 다이얼로그
  /// ===============================
  void _showSessionExpiredDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text('세션 종료'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);  // 다이얼로그 닫기
              _navigateToLogin();
            },
            child: const Text('확인'),
          ),
        ],
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
            // 로고
            const Icon(
              Icons.edit_note,
              size: 80,
              color: Colors.blue,
            ),
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
            // 로딩 인디케이터
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            // 상태 메시지
            Text(
              _statusMessage,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}