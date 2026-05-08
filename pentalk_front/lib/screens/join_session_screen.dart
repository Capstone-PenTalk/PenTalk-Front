import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../providers/student_session_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'material_list_screen.dart';
import 'student_home_screen.dart';

class JoinSessionScreen extends StatefulWidget {
  final String sessionId;

  const JoinSessionScreen({super.key, required this.sessionId});

  @override
  State<JoinSessionScreen> createState() => _JoinSessionScreenState();
}

class _JoinSessionScreenState extends State<JoinSessionScreen> {
  String _message = '세션에 입장하는 중...';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _joinSession());
  }

  Future<void> _joinSession() async {
    final sessionId = widget.sessionId.trim();
    if (sessionId.isEmpty) {
      setState(() => _errorMessage = '세션 ID가 비어 있습니다.');
      return;
    }

    try {
      await _ensureStudentLogin();

      setState(() => _message = '세션 상태를 확인하는 중...');
      final statusResponse = await ApiService.getSessionStatus(
        sessionId: sessionId,
      );

      if (!statusResponse.success || statusResponse.data == null) {
        throw Exception(statusResponse.message ?? '세션을 찾을 수 없습니다.');
      }
      if (!statusResponse.data!.isActive) {
        throw Exception('입장할 수 없는 세션입니다. (${statusResponse.data!.status})');
      }

      if (!mounted) return;
      context.read<StudentSessionProvider>().addJoinedSession(sessionId);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MaterialListScreen(sessionId: sessionId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _errorMessage = e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> _ensureStudentLogin() async {
    final token = await AuthService.getToken();
    final role = await AuthService.getRole();
    if (token != null && token.isNotEmpty && role == 'student') return;

    if (!AppConfig.shouldUseServerLogin) {
      await AuthService.saveUserInfo(
        userId: 'student1',
        role: 'student',
        token: token ?? 'local-student-token',
      );
      return;
    }

    setState(() => _message = '학생 계정으로 접속하는 중...');
    final loginResponse = await ApiService.login(
      userId: 'student1',
      role: 'student',
    );
    if (!loginResponse.success || loginResponse.data == null) {
      throw Exception(loginResponse.message ?? '학생 로그인에 실패했습니다.');
    }

    final login = loginResponse.data!;
    await AuthService.saveUserInfo(
      userId: login.userId,
      role: login.role,
      token: login.token,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('세션 입장')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _errorMessage == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                    Text(_message, textAlign: TextAlign.center),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(_errorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _joinSession,
                      child: const Text('다시 시도'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const StudentHomeScreen(),
                          ),
                        );
                      },
                      child: const Text('학생 홈으로 이동'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
