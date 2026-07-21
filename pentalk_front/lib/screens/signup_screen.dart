import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'student_home_screen.dart';
import 'teacher_home_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;

  @override
  void dispose() {
    _loginIdController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final role = await _showRoleDialog();
    if (!mounted || role == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final profile = await _showProfileDialog(role);
    if (!mounted || profile == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    setState(() => _isLoading = true);
    var didNavigate = false;
    try {
      final loginId = _loginIdController.text.trim();
      final availability = await ApiService.checkLoginId(loginId);
      if (!availability.success) {
        throw _SignupException(_signupErrorMessage(availability.error));
      }
      if (availability.data != true) {
        throw const _SignupException('이미 사용 중인 아이디입니다.');
      }

      final response = await ApiService.signup(
        loginId: loginId,
        password: _passwordController.text,
        name: profile.name,
        role: role,
        studentNumber: profile.studentNumber,
      );
      if (!response.success || response.data == null) {
        throw _SignupException(_signupErrorMessage(response.error));
      }

      final signup = response.data!;
      await AuthService.saveUserInfo(
        userId: signup.userId,
        role: signup.role,
        token: signup.token,
      );
      await AuthService.saveProfile(
        displayName: signup.name?.trim().isNotEmpty == true
            ? signup.name!.trim()
            : profile.name,
        studentNumber: signup.studentNumber?.trim().isNotEmpty == true
            ? signup.studentNumber!.trim()
            : profile.studentNumber,
      );

      if (!mounted) return;
      didNavigate = true;
      _goHome(signup.role);
    } on _SignupException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: Colors.red),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('회원가입 처리 중 오류가 발생했습니다.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted && !didNavigate) setState(() => _isLoading = false);
    }
  }

  void _goHome(String role) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => role == 'teacher'
              ? const TeacherHomeScreen()
              : const StudentHomeScreen(),
        ),
        (_) => false,
      );
    });
  }

  String _signupErrorMessage(String? code) {
    switch (code) {
      case 'INVALID_LOGIN_ID':
        return '아이디는 영문, 숫자, 밑줄을 사용해 4~20자로 입력해 주세요.';
      case 'INVALID_PASSWORD':
        return '비밀번호는 영문과 숫자를 포함해 8~30자로 입력해 주세요.';
      case 'INVALID_NAME':
        return '이름은 1~20자로 입력해 주세요.';
      case 'INVALID_STUDENT_NUMBER':
        return '학번은 숫자만 사용해 4자리 이상으로 입력해 주세요.';
      case 'LOGIN_ID_TAKEN':
        return '이미 사용 중인 아이디입니다.';
      case 'NETWORK_ERROR':
        return '서버에 연결할 수 없습니다. 잠시 후 다시 시도해 주세요.';
      case 'INVALID_RESPONSE':
        return '서버 회원가입 응답 형식이 올바르지 않습니다.';
      default:
        return '회원가입에 실패했습니다.';
    }
  }

  Future<String?> _showRoleDialog() {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('역할을 선택해 주세요'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('학생'),
              onTap: () => Navigator.pop(dialogContext, 'student'),
            ),
            ListTile(
              leading: const Icon(Icons.co_present_outlined),
              title: const Text('교사'),
              onTap: () => Navigator.pop(dialogContext, 'teacher'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
        ],
      ),
    );
  }

  Future<_SignupProfile?> _showProfileDialog(String role) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final studentNumberController = TextEditingController();

    final profile = await showDialog<_SignupProfile>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(role == 'teacher' ? '교사 정보 입력' : '학생 정보 입력'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                autofocus: true,
                textInputAction: role == 'student'
                    ? TextInputAction.next
                    : TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: '이름',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) return '이름을 입력해 주세요.';
                  if (name.length > 20) return '이름은 20자 이하로 입력해 주세요.';
                  return null;
                },
              ),
              if (role == 'student') ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: studentNumberController,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '학번',
                    hintText: '숫자만, 최소 4자리',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final studentNumber = value?.trim() ?? '';
                    if (studentNumber.isEmpty) return '학번을 입력해 주세요.';
                    if (!RegExp(r'^\d{4,}$').hasMatch(studentNumber)) {
                      return '학번은 숫자만 사용해 4자리 이상으로 입력해 주세요.';
                    }
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(
                dialogContext,
                _SignupProfile(
                  name: nameController.text.trim(),
                  studentNumber: role == 'student'
                      ? studentNumberController.text.trim()
                      : null,
                ),
              );
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    nameController.dispose();
    studentNumberController.dispose();
    return profile;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.school, size: 72, color: Colors.blue),
                    const SizedBox(height: 16),
                    const Text(
                      'PenTalk 회원가입',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 40),
                    TextFormField(
                      controller: _loginIdController,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: '아이디',
                        hintText: '영문, 숫자, 밑줄 4~20자',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (value) {
                        final loginId = value?.trim() ?? '';
                        if (loginId.isEmpty) return '아이디를 입력해 주세요.';
                        if (!RegExp(r'^\w{4,20}$').hasMatch(loginId)) {
                          return '영문, 숫자, 밑줄을 사용해 4~20자로 입력해 주세요.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: '비밀번호',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '비밀번호를 입력해 주세요.';
                        }
                        if (value.length < 8 || value.length > 30) {
                          return '비밀번호는 8~30자로 입력해 주세요.';
                        }
                        if (!RegExp(r'[A-Za-z]').hasMatch(value) ||
                            !RegExp(r'\d').hasMatch(value)) {
                          return '영문과 숫자를 각각 1자 이상 포함해 주세요.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordConfirmController,
                      obscureText: _obscurePasswordConfirm,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _handleSignup(),
                      decoration: InputDecoration(
                        labelText: '비밀번호 확인',
                        prefixIcon: const Icon(Icons.lock_reset_outlined),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePasswordConfirm =
                                !_obscurePasswordConfirm,
                          ),
                          icon: Icon(
                            _obscurePasswordConfirm
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (value) => value != _passwordController.text
                          ? '비밀번호가 일치하지 않습니다.'
                          : null,
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: _isLoading ? null : _handleSignup,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              '회원가입',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignupProfile {
  const _SignupProfile({required this.name, this.studentNumber});

  final String name;
  final String? studentNumber;
}

class _SignupException implements Exception {
  const _SignupException(this.message);

  final String message;
}
