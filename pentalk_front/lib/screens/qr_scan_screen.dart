import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/deep_link_service.dart';
import 'join_session_screen.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    facing: CameraFacing.back,
  );
  final TextEditingController _manualController = TextEditingController();
  final DeepLinkService _deepLinkService = DeepLinkService();
  bool _isHandlingCode = false;

  @override
  void dispose() {
    _controller.dispose();
    _manualController.dispose();
    super.dispose();
  }

  void _handleCapture(BarcodeCapture capture) {
    if (_isHandlingCode) return;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue?.trim();
      if (rawValue != null && rawValue.isNotEmpty) {
        _openJoinSession(rawValue);
        return;
      }
    }
  }

  void _openJoinSession(String rawValue) {
    final sessionId =
        _deepLinkService.parseJoinSessionId(rawValue) ?? rawValue.trim();
    final classId = _deepLinkService.parseJoinClassId(rawValue);
    final materialId = _deepLinkService.parseJoinMaterialId(rawValue);
    if (sessionId.isEmpty) {
      _showError('세션 ID를 인식하지 못했습니다.');
      return;
    }

    _isHandlingCode = true;
    _controller.stop();

    _showPasswordEntry(
      sessionId: sessionId,
      classId: classId,
      materialId: materialId,
    );
  }

  void _showPasswordEntry({
    required String sessionId,
    String? classId,
    String? materialId,
  }) {
    final passwordController = TextEditingController();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('세션 비밀번호'),
          content: TextField(
            controller: passwordController,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '비밀번호 입력',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              _submitPassword(
                dialogContext: dialogContext,
                sessionId: sessionId,
                classId: classId,
                materialId: materialId,
                password: passwordController.text,
                onDispose: passwordController.dispose,
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                passwordController.dispose();
                Navigator.pop(dialogContext);
                _isHandlingCode = false;
                _controller.start();
              },
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                _submitPassword(
                  dialogContext: dialogContext,
                  sessionId: sessionId,
                  classId: classId,
                  materialId: materialId,
                  password: passwordController.text,
                  onDispose: passwordController.dispose,
                );
              },
              child: const Text('입장'),
            ),
          ],
        );
      },
    );
  }

  void _submitPassword({
    required BuildContext dialogContext,
    required String sessionId,
    required String? classId,
    required String? materialId,
    required String password,
    required VoidCallback onDispose,
  }) {
    final trimmedPassword = password.trim();
    if (trimmedPassword.isEmpty) {
      _showError('비밀번호를 입력해주세요.');
      return;
    }

    onDispose();
    Navigator.pop(dialogContext);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => JoinSessionScreen(
          sessionId: sessionId,
          classId: classId,
          materialId: materialId,
          password: trimmedPassword,
        ),
      ),
    );
  }

  void _showManualEntry() {
    _manualController.clear();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '세션 링크 또는 ID 입력',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _manualController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '예: 세션 링크 또는 sessionId',
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submitManualEntry(context),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _submitManualEntry(context),
                  child: const Text('입장'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _submitManualEntry(BuildContext sheetContext) {
    final value = _manualController.text.trim();
    if (value.isEmpty) return;
    Navigator.pop(sheetContext);
    _openJoinSession(value);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR 코드 스캔'),
        actions: [
          IconButton(
            tooltip: '손전등',
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: '카메라 전환',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleCapture,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '카메라를 시작할 수 없습니다.\n${error.errorDetails?.message ?? error.errorCode.name}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _showManualEntry,
                    icon: const Icon(Icons.keyboard),
                    label: const Text('링크 또는 세션 ID 직접 입력'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
