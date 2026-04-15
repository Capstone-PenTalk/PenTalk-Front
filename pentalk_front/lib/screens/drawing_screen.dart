import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../native_drawing.dart';
import '../models/student_session_model.dart';
import '../models/poll_model.dart';
import '../providers/drawing_provider.dart';
import '../providers/personal_drawing_provider.dart';
import '../providers/participants_provider.dart';
import '../providers/poll_provider.dart';
import '../widgets/drawing_canvas_widget.dart';
import '../widgets/session_ended_dialog.dart';
import '../widgets/participants_button.dart';
import '../widgets/color_palette_bar.dart';
import '../widgets/width_selector_bar.dart';
import '../widgets/pdf_save_complete_dialog.dart';
import '../widgets/poll_overlay.dart';
import '../widgets/poll_result_sheet.dart';
import '../widgets/poll_start_dialog.dart';
import '../services/api_service.dart';
import '../services/pdf_export_service.dart';
import '../services/pdf_file_service.dart';

class DrawingScreen extends StatefulWidget {
  final String materialTitle;
  final String? backgroundUrl;
  final bool isTeacher;
  final String? serverUrl;
  final String? roomId;
  final String? userId;
  final bool isReadOnly;
  final String? sessionId;

  /// PDF export용 자료 목록 (학생 화면에서 필요)
  /// pageId(materialTitle) → page 번호 매핑에 사용
  final String? materialId;   // 팀원 추가: 자료 ID
  final String? classId;      // 팀원 추가: 클래스 ID
  final List<MaterialModel> materials;

  const DrawingScreen({
    Key? key,
    required this.materialTitle,
    this.backgroundUrl,
    this.materialId,
    this.classId,
    this.isTeacher = false,
    this.serverUrl,
    this.roomId,
    this.userId,
    this.isReadOnly = false,
    this.sessionId,
    this.materials = const [],
  }) : super(key: key);

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  // 버그 #3 수정: dispose에서 context.read 방지용 캐싱
  late final DrawingProvider _drawingProvider;

  bool _isConnecting = false;

  /// PDF export 진행 중 여부
  /// true일 때 뒤로가기 차단 (PopScope)
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _drawingProvider = context.read<DrawingProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDrawing();
      _setupSessionEndedListener();
      _setupPresenceCallbacks();
      _setupPollCallbacks();
    });
  }

  Future<void> _initializeDrawing() async {
    final provider = _drawingProvider;

    provider.setBackgroundUrl(widget.backgroundUrl);

    // 읽기 전용 모드
    if (widget.isReadOnly && widget.sessionId != null) {
      debugPrint('📖 Loading saved whiteboard: ${widget.sessionId}');

      try {
        setState(() => _isConnecting = true);

        final response = await ApiService.getWhiteboard(
          sessionId: widget.sessionId!,
        );

        if (response.success && response.data != null) {
          provider.loadSavedStrokes(response.data!.strokes);
          debugPrint(
              '✅ Whiteboard loaded: ${response.data!.strokes.length} strokes');
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                Text('판서 데이터 로드 실패: ${response.message ?? "알 수 없는 오류"}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('오류: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isConnecting = false);
      }
      return;
    }

    // 편집 가능 모드
    if (widget.isTeacher) {
      provider.setDrawingMode(true);
    } else {
      final personalProvider = context.read<PersonalDrawingProvider>();
      await personalProvider.loadPage(widget.materialTitle);
      debugPrint('✅ Personal strokes loaded for: ${widget.materialTitle}');
    }

    if (widget.serverUrl != null &&
        widget.roomId != null &&
        widget.userId != null) {
      await _connectSocket();
    }
  }

  void _setupSessionEndedListener() {
    _drawingProvider.onSessionEnded = _handleSessionEnded;
  }

  /// ===============================
  /// Poll 콜백 설정
  /// ===============================
  void _setupPollCallbacks() {
    final pollProvider = context.read<PollProvider>();
    final socketService = _drawingProvider.socketService;

    // poll:start → PollProvider 상태 업데이트 → 오버레이 자동 표시
    socketService.onPollStart = (data) {
      final pollData = PollStartData.fromJson(data);
      pollProvider.onPollStart(pollData);
      debugPrint('📊 Poll started, showing overlay');
    };

    // poll:result → 교사 실시간 집계 업데이트
    socketService.onPollResult = (data) {
      final resultData = PollResultData.fromJson(data);
      pollProvider.onPollResult(resultData);
    };

    // poll:end → 종료 처리
    socketService.onPollEnd = (data) {
      final resultData = PollResultData.fromJson(data);
      pollProvider.onPollEnd(resultData);
    };

    debugPrint('📊 Poll callbacks setup completed');
  }

  /// ===============================
  /// 교사: Poll 시작 다이얼로그
  /// ===============================
  Future<void> _handleStartPoll() async {
    await PollStartDialog.show(
      context,
      onStart: ({
        required String question,
        required List<Map<String, dynamic>> options,
        int? duration,
      }) {
        _drawingProvider.socketService.sendPollStart(
          question: question,
          options: options,
          duration: duration,
        );
      },
    );
  }

  /// ===============================
  /// 교사: Poll 조기 종료
  /// ===============================
  void _handleEndPoll() {
    final pollState = context.read<PollProvider>().state;
    if (pollState.pollData == null) return;

    _drawingProvider.socketService.sendPollEnd(pollState.pollData!.pollId);
  }

  /// ===============================
  /// 학생: Poll 응답 전송
  /// ===============================
  void _handlePollAnswer(dynamic optionId) {
    final pollState = context.read<PollProvider>().state;
    if (pollState.pollData == null) return;

    // Provider 상태 업데이트 (고정)
    context.read<PollProvider>().selectOption(optionId);

    // 서버로 전송
    _drawingProvider.socketService.sendPollAnswer(
      pollId: pollState.pollData!.pollId,
      optionId: optionId,
    );
  }

  void _setupPresenceCallbacks() {
    final participantsProvider = context.read<ParticipantsProvider>();
    final socketService = _drawingProvider.socketService;

    socketService.onPresenceState = participantsProvider.setParticipants;
    socketService.onPresenceJoin = participantsProvider.addParticipant;
    socketService.onPresenceLeave = participantsProvider.removeParticipant;

    debugPrint('🔔 Presence callbacks setup completed');
  }

  void _handleSessionEnded(Map<String, dynamic> data) {
    final message = data['message'] as String? ?? '교사가 수업을 종료했습니다';

    if (widget.isTeacher) {
      _cleanupAndGoHome();
    } else {
      SessionEndedDialog.showStudentNotification(
        context,
        message: message,
        onConfirm: _cleanupAndGoHome,
      );
    }
  }

  void _cleanupAndGoHome() {
    _drawingProvider.disconnectSocket();
    _drawingProvider.clear();
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  Future<void> _connectSocket() async {
    setState(() => _isConnecting = true);

    try {
      await _drawingProvider.connectSocket(
        serverUrl: widget.serverUrl!,
        userId: widget.userId!,
        roomId: widget.roomId!,
        isTeacher: widget.isTeacher,
        materialTitle: widget.materialTitle,
        backgroundUrl: widget.backgroundUrl,
        classId: widget.classId,
        materialId: widget.materialId,
      );
      debugPrint('✅ Socket.IO connection initiated');
    } catch (e) {
      debugPrint('❌ Socket.IO connection failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('실시간 연결 실패: $e'),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: '재시도',
              textColor: Colors.white,
              onPressed: _connectSocket,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _endSession() async {
    if (!widget.isTeacher) return;

    final confirmed = await SessionEndedDialog.showEndConfirmation(context);
    if (!confirmed) return;

    SessionEndedDialog.showEndingProgress(context);

    try {
      final response = await ApiService.endSession(
        sessionId: widget.roomId!,
      );

      if (!mounted) return;
      Navigator.pop(context); // 로딩 팝업 닫기

      if (!response.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('세션 종료 실패: ${response.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('오류: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// ===============================
  /// PDF 내보내기 (학생 전용)
  /// ===============================
  Future<void> _handleExportPdf() async {
    final sessionId = widget.roomId ?? widget.sessionId;
    if (sessionId == null) {
      _showExportError(message: '세션 정보가 없습니다.', canRetry: false);
      return;
    }

    setState(() => _isExporting = true);
    PdfExportLoadingDialog.show(context);

    try {
      final personalProvider = context.read<PersonalDrawingProvider>();

      final saveResult = await PdfExportService.export(
        sessionId: sessionId,
        materials: widget.materials,
        personalProvider: personalProvider,
      );

      if (!mounted) return;
      PdfExportLoadingDialog.dismiss(context);
      await PdfSaveCompleteDialog.show(context, saveResult: saveResult);

      // ① 클라이언트 사이드 에러 (stroke 수 초과 등) → 재시도 불가
    } on PdfExportException catch (e) {
      if (!mounted) return;
      PdfExportLoadingDialog.dismiss(context);
      _showExportError(message: e.message, canRetry: false);

      // ② 서버 에러 → 상태코드별 분기
    } on PdfExportApiException catch (e) {
      if (!mounted) return;
      PdfExportLoadingDialog.dismiss(context);

      switch (e.statusCode) {
        case 400: // 데이터 문제 → 재시도해도 의미 없음
          _showExportError(message: e.message, canRetry: false);
          break;
        case 401: // 인증 만료 → 재로그인 유도
          _showExportError(
            message: '로그인이 만료됐습니다. 다시 로그인해주세요.',
            canRetry: false,
          );
          break;
        case 404: // 세션 없음
          _showExportError(
            message: '세션을 찾을 수 없습니다. 수업이 종료됐을 수 있습니다.',
            canRetry: false,
          );
          break;
        default: // 5xx 등 서버 일시 오류 → 재시도 가능
          _showExportError(
            message: '서버 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
            canRetry: true,
          );
      }

      // ③ 네트워크 / 타임아웃 / 파일 저장 오류 → 재시도 가능
    } catch (e) {
      if (!mounted) return;
      PdfExportLoadingDialog.dismiss(context);
      _showExportError(
        message: _resolveUnknownError(e),
        canRetry: true,
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// 알 수 없는 예외 → 원인에 맞는 사용자 메시지 반환
  String _resolveUnknownError(Object e) {
    final msg = e.toString().toLowerCase();

    if (msg.contains('timeout')) {
      return 'PDF 생성 시간이 초과됐습니다. 네트워크 상태를 확인 후 다시 시도해주세요.';
    }
    if (msg.contains('socketexception') ||
        msg.contains('network') ||
        msg.contains('connection')) {
      return '네트워크 연결을 확인해주세요.';
    }
    if (msg.contains('file') ||
        msg.contains('path') ||
        msg.contains('permission') ||
        msg.contains('storage')) {
      return '파일 저장에 실패했습니다. 저장 공간을 확인해주세요.';
    }

    return 'PDF 생성 중 오류가 발생했습니다. 다시 시도해주세요.';
  }

  /// 에러 스낵바 표시
  /// [canRetry]: true면 재시도 버튼 포함
  void _showExportError({
    required String message,
    required bool canRetry,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
        duration: Duration(seconds: canRetry ? 6 : 4),
        action: canRetry
            ? SnackBarAction(
          label: '재시도',
          textColor: Colors.white,
          onPressed: _handleExportPdf,
        )
            : null,
      ),
    );
  }

  @override
  void dispose() {
    _drawingProvider.disconnectSocket();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // export 중 뒤로가기 차단
    return PopScope(
      canPop: !_isExporting,
      onPopInvoked: (didPop) {
        if (!didPop && _isExporting) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF를 생성하는 중입니다. 잠시만 기다려주세요.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Expanded(child: Text(widget.materialTitle)),
              if (widget.isReadOnly)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility, size: 16, color: Colors.orange[800]),
                      const SizedBox(width: 4),
                      Text(
                        '읽기 전용',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[800],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            if (!widget.isReadOnly) ...[
              // 교사용 컨트롤
              if (widget.isTeacher) ...[
                const ColorPaletteBar(),
                const SizedBox(width: 8),
                const WidthSelectorBar(),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.undo),
                  onPressed: _handleUndo,
                  tooltip: '실행 취소',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _handleClear,
                  tooltip: '전체 지우기',
                ),

                // 교사 전용: 이해도 체크 버튼
                Consumer<PollProvider>(
                  builder: (context, pollProvider, _) {
                    final isActive = pollProvider.state.isActive;
                    return IconButton(
                      icon: Icon(
                        isActive ? Icons.poll : Icons.poll_outlined,
                        color: isActive ? Colors.amber : Colors.white,
                      ),
                      onPressed: isActive ? _handleEndPoll : _handleStartPoll,
                      tooltip: isActive ? '이해도 체크 종료' : '이해도 체크 시작',
                    );
                  },
                ),
              ],

              const ParticipantsButton(),

              // 학생 전용: PDF 내보내기 버튼
              if (!widget.isTeacher)
                _isExporting
                    ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                      AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                )
                    : IconButton(
                  icon: const Icon(Icons.picture_as_pdf),
                  onPressed: _handleExportPdf,
                  tooltip: 'PDF 내보내기',
                ),

              // 교사 전용: 세션 종료
              if (widget.isTeacher)
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: _endSession,
                  tooltip: '세션 종료',
                  color: Colors.red,
                ),
            ],
          ],
        ),
        body: _isConnecting
            ? const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('실시간 연결 중...'),
            ],
          ),
        )
            : Stack(
          children: [
            DrawingCanvasWidget(
                isTeacher: widget.isTeacher,
                enableTouchInput: true,     // 👈 추가 (터치 입력 켜기)
                showMyStrokes: true,        // 👈 추가 (내 필기 보이기)
            ),

            // 학생: 이해도 체크 오버레이
            if (!widget.isTeacher)
              Consumer<PollProvider>(
                builder: (context, pollProvider, _) {
                  final state = pollProvider.state;
                  if (!state.isActive && !state.isAnswered) {
                    return const SizedBox.shrink();
                  }
                  return PollOverlay(
                    pollState: state,
                    remainingSeconds: pollProvider.remainingSeconds,
                    onAnswer: _handlePollAnswer,
                  );
                },
              ),

            // 교사: 실시간 집계 결과 표시
            if (widget.isTeacher)
              Consumer<PollProvider>(
                builder: (context, pollProvider, _) {
                  final state = pollProvider.state;
                  if (!state.isActive && !state.isEnded) {
                    return const SizedBox.shrink();
                  }
                  return PollResultSheet(
                    pollState: state,
                    remainingSeconds: pollProvider.remainingSeconds,
                    onClose: () => pollProvider.reset(),
                  );
                },
              ),
          ],
        ),
        floatingActionButton: widget.isReadOnly
            ? null
            : widget.isTeacher
            ? Consumer<DrawingProvider>(
          builder: (context, provider, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton(
                  heroTag: 'drawing_mode',
                  onPressed: () {
                    provider.setDrawingMode(!provider.isDrawingMode);
                  },
                  backgroundColor: provider.isDrawingMode
                      ? Colors.blue
                      : Colors.grey,
                  tooltip: provider.isDrawingMode
                      ? '이동 모드로 전환'
                      : '그리기 모드로 전환',
                  child: Icon(
                    provider.isDrawingMode
                        ? Icons.edit
                        : Icons.pan_tool,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: provider.isDrawingMode
                        ? Colors.blue.withOpacity(0.9)
                        : Colors.grey.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    provider.isDrawingMode ? '✏️ 그리기' : '👆 이동/줌',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        )
            : Consumer2<DrawingProvider, PersonalDrawingProvider>(
          builder:
              (context, drawingProvider, personalProvider, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton(
                  heroTag: 'personal_layer',
                  onPressed: () {
                    personalProvider.togglePersonalLayer();
                  },
                  backgroundColor: personalProvider.showPersonalLayer
                      ? Colors.green
                      : Colors.grey,
                  tooltip: personalProvider.showPersonalLayer
                      ? '내 필기 숨기기'
                      : '내 필기 보기',
                  child: Icon(
                    personalProvider.showPersonalLayer
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'drawing_mode',
                  onPressed: () {
                    drawingProvider
                        .setDrawingMode(!drawingProvider.isDrawingMode);
                  },
                  backgroundColor: drawingProvider.isDrawingMode
                      ? Colors.blue
                      : Colors.grey,
                  tooltip: drawingProvider.isDrawingMode
                      ? '이동 모드로 전환'
                      : '그리기 모드로 전환',
                  child: Icon(
                    drawingProvider.isDrawingMode
                        ? Icons.edit
                        : Icons.pan_tool,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: drawingProvider.isDrawingMode
                        ? Colors.blue.withOpacity(0.9)
                        : Colors.grey.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    drawingProvider.isDrawingMode
                        ? '✏️ 내 필기'
                        : '👆 이동/줌',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _handleUndo() {
    final strokes = _drawingProvider.myStrokes;
    if (strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('실행 취소할 내용이 없습니다')),
      );
      return;
    }
    final lastStrokeId = strokes.keys.last;
    _drawingProvider.sendUndo(lastStrokeId);
  }

  void _handleClear() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('전체 지우기'),
        content: const Text('모든 판서 내용을 지우시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              _drawingProvider.clear();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('지우기'),
          ),
        ],
      ),
    );
  }
}