import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'student_home_screen.dart';
import 'teacher_home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _primary = Color(0xFF5264E5);
  static const _background = Color(0xFFF7F5F1);
  static const _muted = Color(0xFF8A8782);

  final _loginFormKey = GlobalKey<FormState>();
  final _signupFormKey = GlobalKey<FormState>();

  final _loginIdController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  final _signupIdController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  final _signupPasswordConfirmController = TextEditingController();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  String? _handledOAuthCode;

  bool _isSignup = false;
  bool _isLoading = false;
  bool _obscureLoginPassword = true;
  bool _obscureSignupPassword = true;
  bool _obscureSignupPasswordConfirm = true;
  String _signupRole = 'teacher';

  @override
  void initState() {
    super.initState();
    _listenOAuthCallback();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _loginIdController.dispose();
    _loginPasswordController.dispose();
    _signupIdController.dispose();
    _signupPasswordController.dispose();
    _signupPasswordConfirmController.dispose();
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
    if (!(_loginFormKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);

    final response = await ApiService.login(
      loginId: _loginIdController.text.trim(),
      password: _loginPasswordController.text,
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

  Future<void> _handleSignup() async {
    if (!(_signupFormKey.currentState?.validate() ?? false)) return;

    final profile = await _showProfileDialog(role: _signupRole);
    if (!mounted || profile == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    setState(() => _isLoading = true);
    var didNavigate = false;

    try {
      final loginId = _signupIdController.text.trim();
      final availability = await ApiService.checkLoginId(loginId);
      if (!availability.success) {
        throw _AuthFlowException(_signupErrorMessage(availability.error));
      }
      if (availability.data != true) {
        throw const _AuthFlowException('이미 사용 중인 아이디입니다.');
      }

      final response = await ApiService.signup(
        loginId: loginId,
        password: _signupPasswordController.text,
        name: profile.name,
        role: _signupRole,
        studentNumber: profile.studentNumber,
      );
      if (!response.success || response.data == null) {
        throw _AuthFlowException(_signupErrorMessage(response.error));
      }

      final signup = response.data!;
      await _saveLoginResponse(signup);
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
    } on _AuthFlowException catch (error) {
      if (!mounted) return;
      _showError(error.message);
    } catch (_) {
      if (!mounted) return;
      _showError('회원가입 처리 중 오류가 발생했습니다.');
    } finally {
      if (mounted && !didNavigate) setState(() => _isLoading = false);
    }
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

    final profile = await _showProfileDialog(
      role: role,
      initialName: exchange.user.name,
    );
    if (!mounted || profile == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final response = await ApiService.setOAuthRole(
      setupToken: exchange.token,
      role: role,
      studentNumber: profile.studentNumber,
    );
    if (!mounted) return;
    if (!response.success || response.data == null) {
      setState(() => _isLoading = false);
      _showError(_roleErrorMessage(response.error));
      return;
    }

    await _saveLoginResponse(response.data!);
    await AuthService.saveProfile(
      displayName: profile.name,
      studentNumber: response.data!.studentNumber?.trim().isNotEmpty == true
          ? response.data!.studentNumber!.trim()
          : profile.studentNumber,
    );
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
              leading: const Icon(Icons.co_present_outlined),
              title: const Text('교사'),
              onTap: () => Navigator.pop(dialogContext, 'teacher'),
            ),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('학생'),
              onTap: () => Navigator.pop(dialogContext, 'student'),
            ),
          ],
        ),
      ),
    );
  }

  Future<_ProfileInput?> _showProfileDialog({
    required String role,
    String? initialName,
  }) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: initialName?.trim());
    final studentNumberController = TextEditingController();

    final profile = await showDialog<_ProfileInput>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('프로필 정보를 입력해 주세요'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '이름',
                    hintText: '이름',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateName,
                ),
                if (role == 'student') ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: studentNumberController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: '학번',
                      hintText: '숫자만, 최소 4자리',
                      prefixIcon: Icon(Icons.confirmation_number_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateStudentNumber,
                  ),
                ],
              ],
            ),
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
                _ProfileInput(
                  name: nameController.text.trim(),
                  studentNumber: role == 'student'
                      ? studentNumberController.text.trim()
                      : null,
                ),
              );
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );

    nameController.dispose();
    studentNumberController.dispose();
    return profile;
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
            validator: (value) => _validateStudentNumber(value),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildBrand(),
                  const SizedBox(height: 32),
                  _buildModeTabs(),
                  const SizedBox(height: 28),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _isSignup ? _buildSignupForm() : _buildLoginForm(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrand() {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: _primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.edit_outlined, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 14),
        const Text(
          'PenTalk',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF202124),
            fontSize: 28,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '실시간 비대면 수업, 손끝으로 잇다',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildModeTabs() {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEAE4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildModeTab(label: '로그인', active: !_isSignup),
          _buildModeTab(label: '회원가입', active: _isSignup),
        ],
      ),
    );
  }

  Widget _buildModeTab({required String label, required bool active}) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _isLoading
            ? null
            : () => setState(() => _isSignup = label == '회원가입'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? const Color(0xFF202124) : _muted,
              fontSize: 14,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        key: const ValueKey('login_form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFieldLabel('아이디'),
          _buildTextField(
            controller: _loginIdController,
            hintText: '이메일 또는 아이디',
            prefixIcon: Icons.person_outline,
            textInputAction: TextInputAction.next,
            validator: (value) =>
                value == null || value.trim().isEmpty ? '아이디를 입력해 주세요.' : null,
          ),
          const SizedBox(height: 16),
          _buildFieldLabel('비밀번호'),
          _buildTextField(
            controller: _loginPasswordController,
            hintText: '••••••••',
            prefixIcon: Icons.lock_outline,
            obscureText: _obscureLoginPassword,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _handleLogin(),
            suffixIcon: _passwordToggle(
              obscure: _obscureLoginPassword,
              onPressed: () => setState(
                () => _obscureLoginPassword = !_obscureLoginPassword,
              ),
            ),
            validator: (value) =>
                value == null || value.isEmpty ? '비밀번호를 입력해 주세요.' : null,
          ),
          const SizedBox(height: 24),
          _buildPrimaryButton(label: '로그인', onPressed: _handleLogin),
          const SizedBox(height: 18),
          _buildSocialDivider(),
          const SizedBox(height: 16),
          _buildSocialButtons(),
          const SizedBox(height: 16),
          _buildBottomSwitch(text: '계정이 없으신가요?', action: '회원가입', signup: true),
        ],
      ),
    );
  }

  Widget _buildSignupForm() {
    return Form(
      key: _signupFormKey,
      child: Column(
        key: const ValueKey('signup_form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFieldLabel('아이디'),
          _buildTextField(
            controller: _signupIdController,
            hintText: '이메일 또는 아이디',
            prefixIcon: Icons.person_outline,
            textInputAction: TextInputAction.next,
            validator: _validateLoginId,
          ),
          const SizedBox(height: 16),
          _buildFieldLabel('비밀번호'),
          _buildTextField(
            controller: _signupPasswordController,
            hintText: '영문과 숫자 포함 8~30자',
            prefixIcon: Icons.lock_outline,
            obscureText: _obscureSignupPassword,
            textInputAction: TextInputAction.next,
            suffixIcon: _passwordToggle(
              obscure: _obscureSignupPassword,
              onPressed: () => setState(
                () => _obscureSignupPassword = !_obscureSignupPassword,
              ),
            ),
            validator: _validatePassword,
          ),
          const SizedBox(height: 16),
          _buildFieldLabel('비밀번호 확인'),
          _buildTextField(
            controller: _signupPasswordConfirmController,
            hintText: '비밀번호를 한 번 더 입력',
            prefixIcon: Icons.lock_reset_outlined,
            obscureText: _obscureSignupPasswordConfirm,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _handleSignup(),
            suffixIcon: _passwordToggle(
              obscure: _obscureSignupPasswordConfirm,
              onPressed: () => setState(
                () => _obscureSignupPasswordConfirm =
                    !_obscureSignupPasswordConfirm,
              ),
            ),
            validator: (value) => value != _signupPasswordController.text
                ? '비밀번호가 일치하지 않습니다.'
                : null,
          ),
          const SizedBox(height: 18),
          _buildFieldLabel('역할 선택'),
          _buildRoleSelector(),
          const SizedBox(height: 24),
          _buildPrimaryButton(label: '가입하고 시작하기', onPressed: _handleSignup),
          const SizedBox(height: 16),
          _buildBottomSwitch(text: '이미 계정이 있나요?', action: '로그인', signup: false),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF5D5A55),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    required String? Function(String?) validator,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputAction? textInputAction,
    TextInputType? keyboardType,
    ValueChanged<String>? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      enabled: !_isLoading,
      obscureText: obscureText,
      textInputAction: textInputAction,
      keyboardType: keyboardType,
      onFieldSubmitted: onFieldSubmitted,
      autocorrect: false,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: Color(0xFFB6B1AA)),
        prefixIcon: Icon(prefixIcon, size: 20, color: _muted),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0DCD5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0DCD5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary, width: 1.3),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      ),
      validator: validator,
    );
  }

  Widget _passwordToggle({
    required bool obscure,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: _isLoading ? null : onPressed,
      icon: Icon(
        obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: _muted,
      ),
    );
  }

  Widget _buildRoleSelector() {
    return Row(
      children: [
        Expanded(
          child: _buildRoleOption(
            role: 'teacher',
            label: '교사',
            icon: Icons.person_outline,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildRoleOption(
            role: 'student',
            label: '학생',
            icon: Icons.school_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildRoleOption({
    required String role,
    required String label,
    required IconData icon,
  }) {
    final selected = _signupRole == role;
    return GestureDetector(
      onTap: _isLoading ? null : () => setState(() => _signupRole = role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 52,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF0F2FF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _primary : const Color(0xFFE0DCD5),
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? _primary : _muted, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? _primary : const Color(0xFF5D5A55),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return FilledButton(
      onPressed: _isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _primary.withValues(alpha: 0.55),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          : Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
    );
  }

  Widget _buildSocialDivider() {
    return const Row(
      children: [
        Expanded(child: Divider(color: Color(0xFFE0DCD5))),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('또는', style: TextStyle(color: _muted, fontSize: 12)),
        ),
        Expanded(child: Divider(color: Color(0xFFE0DCD5))),
      ],
    );
  }

  Widget _buildSocialButtons() {
    return Row(
      children: [
        Expanded(
          child: _buildSocialButton(
            label: 'Google',
            icon: Icons.g_mobiledata,
            onPressed: () => _handleSocialLogin('google'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildSocialButton(
            label: 'Kakao',
            icon: Icons.chat_bubble_outline,
            backgroundColor: const Color(0xFFFEE500),
            foregroundColor: Colors.black87,
            onPressed: () => _handleSocialLogin('kakao'),
          ),
        ),
      ],
    );
  }

  Widget _buildSocialButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    Color backgroundColor = Colors.white,
    Color foregroundColor = const Color(0xFF202124),
  }) {
    return OutlinedButton.icon(
      onPressed: _isLoading ? null : onPressed,
      icon: Icon(icon, size: 22),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: foregroundColor,
        backgroundColor: backgroundColor,
        side: const BorderSide(color: Color(0xFFE0DCD5)),
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildBottomSwitch({
    required String text,
    required String action,
    required bool signup,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(text, style: const TextStyle(color: _muted, fontSize: 13)),
        TextButton(
          onPressed: _isLoading
              ? null
              : () => setState(() => _isSignup = signup),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: _primary,
          ),
          child: Text(
            action,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  String? _validateLoginId(String? value) {
    final loginId = value?.trim() ?? '';
    if (loginId.isEmpty) return '아이디를 입력해 주세요.';
    final looksLikeEmail = RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(loginId);
    final looksLikeLoginId = RegExp(r'^\w{4,20}$').hasMatch(loginId);
    if (!looksLikeEmail && !looksLikeLoginId) {
      return '이메일 또는 영문/숫자/밑줄 4~20자로 입력해 주세요.';
    }
    return null;
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return '이름을 입력해 주세요.';
    if (name.length > 20) return '이름은 20자 이하로 입력해 주세요.';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return '비밀번호를 입력해 주세요.';
    if (value.length < 8 || value.length > 30) {
      return '비밀번호는 8~30자로 입력해 주세요.';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(value) ||
        !RegExp(r'\d').hasMatch(value)) {
      return '영문과 숫자를 각각 1자 이상 포함해 주세요.';
    }
    return null;
  }

  String? _validateStudentNumber(String? value) {
    final studentNumber = value?.trim() ?? '';
    if (studentNumber.isEmpty) return '학번을 입력해 주세요.';
    if (!RegExp(r'^\d{4,}$').hasMatch(studentNumber)) {
      return '학번은 숫자만 사용해 4자리 이상으로 입력해 주세요.';
    }
    return null;
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

  String _signupErrorMessage(String? code) {
    switch (code) {
      case 'INVALID_LOGIN_ID':
        return '아이디는 이메일 또는 영문/숫자/밑줄 4~20자로 입력해 주세요.';
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
}

class _AuthFlowException implements Exception {
  const _AuthFlowException(this.message);

  final String message;
}

class _ProfileInput {
  const _ProfileInput({required this.name, this.studentNumber});

  final String name;
  final String? studentNumber;
}
