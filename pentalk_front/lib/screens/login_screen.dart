import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'signup_screen.dart';
import 'student_home_screen.dart';
import 'teacher_home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  String? _handledOAuthCode;
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _listenOAuthCallback();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _loginIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _listenOAuthCallback() {
    _appLinks
        .getInitialLink()
        .then((uri) {
          if (!mounted || uri == null) return;
          _handleOAuthCallback(uri);
        })
        .catchError((_) {});
    _linkSubscription = _appLinks.uriLinkStream.listen(_handleOAuthCallback);
  }

  Future<void> _handleLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);

    final response = await ApiService.login(
      loginId: _loginIdController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;
    if (!response.success || response.data == null) {
      setState(() => _isLoading = false);
      _showError(_loginErrorMessage(response.error));
      return;
    }

    final login = response.data!;
    try {
      await _saveLoginResponse(login);
      if (login.role == 'student' && login.requiresProfileCompletion) {
        final completed = await _completeStudentProfile();
        if (!completed) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('로그인 정보를 저장하지 못했습니다: $error');
      return;
    }

    if (!mounted) return;
    _goHome(login.role);
  }

  Future<void> _saveLoginResponse(LoginResponse login) async {
    await AuthService.saveUserInfo(
      userId: login.userId,
      role: login.role,
      token: login.token,
    );
    final name = login.name?.trim();
    final studentNumber = login.studentNumber?.trim();
    if ((name != null && name.isNotEmpty) ||
        (studentNumber != null && studentNumber.isNotEmpty)) {
      await AuthService.saveProfile(
        displayName: name?.isNotEmpty == true ? name! : login.userId,
        studentNumber: studentNumber,
      );
    }
  }

  Future<void> _handleSocialLogin(String provider) async {
    final startUrl = provider == 'google'
        ? AppConfig.googleOAuthStartUrl
        : AppConfig.kakaoOAuthStartUrl;
    final uri = Uri.parse(startUrl);
    setState(() => _isLoading = true);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('OAuth start failed');
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('소셜 로그인을 시작할 수 없습니다.');
    }
  }

  Future<void> _handleOAuthCallback(Uri uri) async {
    if (uri.scheme != 'pentalk' ||
        uri.host != 'auth' ||
        uri.path != '/callback') {
      return;
    }

    final error = uri.queryParameters['error']?.trim();
    if (error != null && error.isNotEmpty) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(_oauthErrorMessage(error));
      return;
    }

    final code = uri.queryParameters['code']?.trim();
    if (code == null || code.isEmpty || code == _handledOAuthCode) return;
    _handledOAuthCode = code;

    if (mounted) setState(() => _isLoading = true);
    final response = await ApiService.exchangeOAuthCode(code);
    if (!mounted) return;
    if (!response.success || response.data == null) {
      setState(() => _isLoading = false);
      _showError(_oauthExchangeErrorMessage(response.error));
      return;
    }

    final exchange = response.data!;
    if (exchange.requiresRoleSelection) {
      await _handleOAuthRoleSelection(exchange);
      return;
    }

    final role = exchange.user.role!;
    final login = LoginResponse(
      token: exchange.token,
      userId: exchange.user.userId,
      role: role,
      loginId: exchange.user.loginId,
      name: exchange.user.name,
      email: exchange.user.email,
      studentNumber: exchange.user.studentNumber,
      requiresProfileCompletion: exchange.requiresProfileCompletion == true,
    );
    await _saveLoginResponse(login);
    if (role == 'student' && login.requiresProfileCompletion) {
      final completed = await _completeStudentProfile();
      if (!completed) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
    }
    if (!mounted) return;
    _goHome(role);
  }

  Future<void> _handleOAuthRoleSelection(OAuthExchangeResponse exchange) async {
    final role = await _showRoleDialog();
    if (!mounted || role == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final studentNumber = role == 'student'
        ? await _showStudentNumberDialog(title: '학생 정보 입력')
        : null;
    if (!mounted || (role == 'student' && studentNumber == null)) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final response = await ApiService.setOAuthRole(
      setupToken: exchange.token,
      role: role,
      studentNumber: studentNumber,
    );
    if (!mounted) return;
    if (!response.success || response.data == null) {
      setState(() => _isLoading = false);
      _showError(_roleErrorMessage(response.error));
      return;
    }

    await _saveLoginResponse(response.data!);
    if (!mounted) return;
    _goHome(response.data!.role);
  }

  Future<bool> _completeStudentProfile() async {
    final studentNumber = await _showStudentNumberDialog(title: '학번 입력');
    if (!mounted || studentNumber == null) return false;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return false;

    final response = await ApiService.updateStudentNumber(studentNumber);
    if (!mounted) return false;
    if (!response.success || response.data == null) {
      _showError(_profileErrorMessage(response.error));
      return false;
    }
    await _saveLoginResponse(response.data!);
    return true;
  }

  Future<String?> _showRoleDialog() {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
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
      ),
    );
  }

  Future<String?> _showStudentNumberDialog({required String title}) async {
    final formKey = GlobalKey<FormState>();
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
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
        ),
        actions: [
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(dialogContext, controller.text.trim());
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
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

  String _loginErrorMessage(String? code) {
    switch (code) {
      case 'LOGIN_FAILED':
        return '아이디 또는 비밀번호를 확인해 주세요.';
      case 'PAYLOAD_INVALID':
        return '아이디와 비밀번호를 모두 입력해 주세요.';
      case 'INVALID_STUDENT_NUMBER':
        return '학번은 숫자만 사용해 4자리 이상으로 입력해 주세요.';
      case 'NETWORK_ERROR':
        return '서버에 연결할 수 없습니다. 잠시 후 다시 시도해 주세요.';
      case 'INVALID_RESPONSE':
        return '서버 로그인 응답 형식이 올바르지 않습니다.';
      default:
        return '로그인에 실패했습니다.';
    }
  }

  String _oauthErrorMessage(String code) {
    switch (code) {
      case 'ACCESS_DENIED':
        return '소셜 로그인이 취소되었습니다.';
      case 'INVALID_STATE':
        return '인증 정보가 만료되었습니다. 다시 시도해 주세요.';
      case 'EMAIL_ALREADY_REGISTERED':
        return '이미 일반 계정으로 가입된 이메일입니다.';
      case 'PROVIDER_ERROR':
        return '소셜 로그인 제공자 인증에 실패했습니다.';
      default:
        return '소셜 로그인에 실패했습니다.';
    }
  }

  String _oauthExchangeErrorMessage(String? code) {
    switch (code) {
      case 'CODE_INVALID_OR_EXPIRED':
      case 'EXCHANGE_FAILED':
        return '로그인 코드가 만료되었습니다. 다시 시도해 주세요.';
      case 'PAYLOAD_INVALID':
        return '로그인 코드가 누락되었습니다. 다시 시도해 주세요.';
      case 'NETWORK_ERROR':
        return '서버에 연결할 수 없습니다. 잠시 후 다시 시도해 주세요.';
      case 'INVALID_RESPONSE':
        return '서버 소셜 로그인 응답 형식이 올바르지 않습니다.';
      default:
        return '소셜 로그인에 실패했습니다.';
    }
  }

  String _roleErrorMessage(String? code) {
    switch (code) {
      case 'INVALID_ROLE':
      case 'PAYLOAD_INVALID':
        return '역할 또는 학번 입력값을 확인해 주세요.';
      case 'ROLE_ALREADY_SET':
        return '이미 역할이 설정된 계정입니다. 다시 로그인해 주세요.';
      case 'ROLE_SETUP_TOKEN_REQUIRED':
      case 'FORBIDDEN':
        return '역할 설정 인증이 만료되었습니다. 다시 로그인해 주세요.';
      case 'NETWORK_ERROR':
        return '서버에 연결할 수 없습니다. 잠시 후 다시 시도해 주세요.';
      default:
        return '역할 설정에 실패했습니다.';
    }
  }

  String _profileErrorMessage(String? code) {
    switch (code) {
      case 'INVALID_STUDENT_NUMBER':
      case 'PAYLOAD_INVALID':
        return '학번은 숫자만 사용해 4자리 이상으로 입력해 주세요.';
      case 'FORBIDDEN':
        return '학생 계정만 학번을 저장할 수 있습니다.';
      case 'NETWORK_ERROR':
        return '서버에 연결할 수 없습니다. 잠시 후 다시 시도해 주세요.';
      default:
        return '학번 저장에 실패했습니다.';
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    const Icon(Icons.school, size: 80, color: Colors.blue),
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
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 48),
                    TextFormField(
                      controller: _loginIdController,
                      enabled: !_isLoading,
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
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '아이디를 입력해 주세요.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      enabled: !_isLoading,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _handleLogin(),
                      decoration: InputDecoration(
                        labelText: '비밀번호',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: _isLoading
                              ? null
                              : () => setState(
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
                      validator: (value) => value == null || value.isEmpty
                          ? '비밀번호를 입력해 주세요.'
                          : null,
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: FilledButton.styleFrom(
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
                    const SizedBox(height: 18),
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            '또는',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _handleSocialLogin('google'),
                      icon: const Icon(Icons.g_mobiledata, size: 28),
                      label: const Text('Google로 로그인'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _handleSocialLogin('kakao'),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Kakao로 로그인'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: Colors.black87,
                        backgroundColor: const Color(0xFFFEE500),
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SignupScreen(),
                                ),
                              ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          '회원가입',
                          style: TextStyle(fontSize: 13),
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
