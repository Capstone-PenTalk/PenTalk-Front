import 'dart:async';

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
    autoStart: false,
    facing: CameraFacing.back,
  );
  final TextEditingController _manualController = TextEditingController();
  final DeepLinkService _deepLinkService = DeepLinkService();
  bool _isHandlingCode = false;
  bool _showScanner = true;
  bool _isControllerDisposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showScanner) return;
      unawaited(_controller.start());
    });
  }

  @override
  void dispose() {
    unawaited(_disposeScannerController());
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _disposeScannerController() async {
    if (_isControllerDisposed) return;
    _isControllerDisposed = true;
    try {
      await _controller.stop();
    } catch (_) {}
    try {
      await _controller.dispose();
    } catch (_) {}
  }

  void _handleCapture(BarcodeCapture capture) {
    if (_isHandlingCode) return;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue?.trim();
      if (rawValue != null && rawValue.isNotEmpty) {
        unawaited(_openJoinSession(rawValue));
        return;
      }
    }
  }

  Future<void> _openJoinSession(String rawValue) async {
    if (_isHandlingCode) return;
    final sessionId =
        _deepLinkService.parseJoinSessionId(rawValue) ?? rawValue.trim();
    final classId = _deepLinkService.parseJoinClassId(rawValue);
    final materialId = _deepLinkService.parseJoinMaterialId(rawValue);
    if (sessionId.isEmpty) {
      _showError('세션 ID를 인식하지 못했습니다.');
      return;
    }

    _isHandlingCode = true;
    if (mounted) {
      setState(() => _showScanner = false);
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    try {
      await _controller.stop();
    } catch (_) {}

    await _showPasswordEntry(
      sessionId: sessionId,
      classId: classId,
      materialId: materialId,
    );
  }

  Future<void> _showPasswordEntry({
    required String sessionId,
    String? classId,
    String? materialId,
  }) async {
    final passwordController = TextEditingController();
    String? password;
    try {
      password = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          void submit() {
            final value = passwordController.text.trim();
            if (value.isEmpty) {
              _showError('비밀번호를 입력해주세요.');
              return;
            }
            FocusScope.of(dialogContext).unfocus();
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.pop(dialogContext, value);
          }

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
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('취소'),
              ),
              FilledButton(onPressed: submit, child: const Text('입장')),
            ],
          );
        },
      );
    } finally {
      passwordController.dispose();
    }

    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;

    if (password == null) {
      _isHandlingCode = false;
      if (mounted) {
        setState(() => _showScanner = true);
      }
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) {
        await _controller.start();
      }
      return;
    }

    await _disposeScannerController();
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => JoinSessionScreen(
          sessionId: sessionId,
          classId: classId,
          materialId: materialId,
          password: password,
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_openJoinSession(value));
    });
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
          if (_showScanner)
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
            )
          else
            const ColoredBox(color: Colors.black),
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
