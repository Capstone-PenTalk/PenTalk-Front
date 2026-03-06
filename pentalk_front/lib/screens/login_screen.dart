import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// ===============================
/// 로그인 화면
/// ===============================
class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userIdController = TextEditingController();
  String _selectedRole = 'student'; // 기본값: 학생
  bool _isLoading = false;

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final userId = _userIdController.text.trim();

    if (userId.isEmpty) {
      _showError('사용자 ID를 입력해주세요');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 로그인 API 호출
      final response = await ApiService.login(
        userId: userId,
        role: _selectedRole,
      );

      if (!mounted) return;

      if (response.success && response.data != null) {
        // 토큰 저장
        await AuthService.saveUserInfo(
          userId: response.data!.userId,
          role: response.data!.role,
          token: response.data!.token,
        );

        // 홈 화면으로 이동
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        _showError(response.message ?? '로그인 실패');
      }
    } catch (e) {
      if (!mounted) return;
      _showError('네트워크 오류: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 로고/제목
                const Icon(
                  Icons.school,
                  size: 80,
                  color: Colors.blue,
                ),
                const SizedBox(height: 24),
                const Text(
                  'PenTalk',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '하이브리드 교실',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 48),

                // 사용자 ID 입력
                TextField(
                  controller: _userIdController,
                  decoration: InputDecoration(
                    labelText: '사용자 ID',
                    hintText: 'teacher_test 또는 student_01',
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  enabled: !_isLoading,
                  onSubmitted: (_) => _handleLogin(),
                ),
                const SizedBox(height: 24),

                // 역할 선택
                const Text(
                  '역할 선택',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('학생'),
                        value: 'student',
                        groupValue: _selectedRole,
                        onChanged: _isLoading
                            ? null
                            : (value) {
                          setState(() => _selectedRole = value!);
                        },
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: _selectedRole == 'student'
                                ? Colors.blue
                                : Colors.grey[300]!,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('교사'),
                        value: 'teacher',
                        groupValue: _selectedRole,
                        onChanged: _isLoading
                            ? null
                            : (value) {
                          setState(() => _selectedRole = value!);
                        },
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: _selectedRole == 'teacher'
                                ? Colors.blue
                                : Colors.grey[300]!,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // 로그인 버튼
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Text(
                    '로그인',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 안내 문구
                Text(
                  '개발 모드: 비밀번호 없이 로그인',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}