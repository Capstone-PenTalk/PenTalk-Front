import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/student_session_model.dart';
import '../providers/student_session_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'drawing_screen.dart';
import 'material_list_screen.dart';
import 'student_home_screen.dart';

class JoinSessionScreen extends StatefulWidget {
  final String sessionId;
  final String? classId;
  final String? materialId;
  final String? password;

  const JoinSessionScreen({
    super.key,
    required this.sessionId,
    this.password,
    this.classId,
    this.materialId,
  });

  @override
  State<JoinSessionScreen> createState() => _JoinSessionScreenState();
}

class _JoinSessionScreenState extends State<JoinSessionScreen> {
  String _message = '세션에 입장하는 중...';
  String? _errorMessage;
  String? _password;

  @override
  void initState() {
    super.initState();
    _password = widget.password;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_password == null || _password!.trim().isEmpty) {
        _showPasswordDialog();
      } else {
        _joinSession();
      }
    });
  }

  void _showPasswordDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('세션 비밀번호'),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '비밀번호 입력',
            ),
            onSubmitted: (_) => _submitPassword(dialogContext, controller),
          ),
          actions: [
            TextButton(
              onPressed: () {
                controller.dispose();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const StudentHomeScreen()),
                );
              },
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => _submitPassword(dialogContext, controller),
              child: const Text('입장'),
            ),
          ],
        );
      },
    );
  }

  void _submitPassword(
    BuildContext dialogContext,
    TextEditingController controller,
  ) {
    final password = controller.text.trim();
    if (password.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('비밀번호를 입력해주세요.')));
      return;
    }

    controller.dispose();
    Navigator.pop(dialogContext);
    setState(() => _password = password);
    _joinSession();
  }

  Future<void> _joinSession() async {
    final sessionId = widget.sessionId.trim();
    if (sessionId.isEmpty) {
      setState(() => _errorMessage = '세션 ID가 비어 있습니다.');
      return;
    }

    try {
      await _ensureStudentLogin();

      setState(() {
        _errorMessage = null;
        _message = '세션에 참여하는 중...';
      });
      final joinResponse = await ApiService.joinSession(
        sessionId: sessionId,
        password: _password!.trim(),
        materialId: widget.materialId,
      );

      if (joinResponse.error == 'SESSION_JOIN_UNAVAILABLE') {
        debugPrint('Session join endpoint unavailable, continuing join.');
      } else if (!joinResponse.success) {
        throw Exception(joinResponse.message ?? '세션 참여에 실패했습니다.');
      }

      if (!mounted) return;
      final joinedClassId = joinResponse.data?.classId ?? widget.classId;
      final joinedMaterialId =
          joinResponse.data?.materialId ?? widget.materialId;
      final joinedMaterial = joinResponse.data?.material;
      context.read<StudentSessionProvider>().addJoinedSession(
        sessionId,
        classId: joinedClassId,
      );

      await _openJoinedDestination(
        sessionId: sessionId,
        classId: joinedClassId,
        materialId: joinedMaterialId,
        material: joinedMaterial,
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _errorMessage = e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> _openJoinedDestination({
    required String sessionId,
    required String? classId,
    required String? materialId,
    required SessionJoinMaterial? material,
  }) async {
    final trimmedClassId = classId?.trim();
    final fallbackMaterialId = materialId?.trim();

    if ((material == null || material.id.trim().isEmpty) &&
        (fallbackMaterialId == null || fallbackMaterialId.isEmpty)) {
      _openMaterialList(sessionId: sessionId, classId: trimmedClassId);
      return;
    }

    try {
      if (mounted) {
        setState(() => _message = '자료를 불러오는 중...');
      }

      final selectedMaterialId = material?.id.trim().isNotEmpty == true
          ? material!.id.trim()
          : fallbackMaterialId!;
      final selectedMaterialName = material?.name.trim().isNotEmpty == true
          ? material!.name.trim()
          : '자료';
      final materialType = material == null
          ? FileMaterialType.pdf
          : FileMaterialType.fromString(material.type);
      final backgroundUrl = material?.url.trim() ?? '';
      final documentPages = material?.pages ?? const [];
      final currentUserId = await AuthService.getUserId();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DrawingScreen(
            materialTitle: selectedMaterialName,
            backgroundUrl: backgroundUrl.isEmpty ? null : backgroundUrl,
            isPdfDocument: materialType == FileMaterialType.pdf,
            materialId: selectedMaterialId,
            documentPages: documentPages,
            classId: trimmedClassId,
            isTeacher: false,
            serverUrl: AppConfig.resolveSocketUrl(isTeacher: false),
            roomId: sessionId,
            userId: currentUserId,
            sessionId: sessionId,
            materials: [
              MaterialModel(
                id: selectedMaterialId,
                title: selectedMaterialName,
                fileName: selectedMaterialName,
                url: backgroundUrl,
                sizeInBytes: 0,
                uploadedAt: DateTime.now(),
                type: materialType,
                pages: documentPages,
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ Failed to open joined material: $e');
      if (!mounted) return;
      _openMaterialList(sessionId: sessionId, classId: trimmedClassId);
    }
  }

  void _openMaterialList({
    required String sessionId,
    required String? classId,
  }) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MaterialListScreen(sessionId: sessionId, classId: classId),
      ),
    );
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
    final loginResponse = await ApiService.devLogin(
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
