import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/document_source.dart';
import '../models/student_session_model.dart';
import '../models/poll_model.dart';
import '../models/question_model.dart';
import '../config/app_config.dart';
import '../native_drawing.dart';
import '../providers/drawing_provider.dart';
import '../providers/personal_drawing_provider.dart';
import '../providers/participants_provider.dart';
import '../providers/poll_provider.dart';
import '../providers/question_provider.dart';
import '../providers/quiz_provider.dart';
import '../widgets/drawing_canvas_widget.dart';
import '../widgets/session_ended_dialog.dart';
import '../widgets/participants_button.dart';
import '../widgets/color_palette_bar.dart';
import '../widgets/width_selector_bar.dart';
import '../widgets/pdf_save_complete_dialog.dart';
import '../widgets/poll_overlay.dart';
import '../widgets/poll_result_sheet.dart';
import '../widgets/poll_start_dialog.dart';
import '../widgets/qr_view.dart';
import '../widgets/quiz_editor_widget.dart';
import '../widgets/questions_panel.dart';
import '../widgets/question_ask_dialog.dart';
import '../services/api_service.dart';
import '../services/deep_link_service.dart';
import '../services/pdf_export_service.dart';
import '../services/pdf_file_service.dart';
import '../theme/app_colors.dart';
import 'student_home_screen.dart';
import 'teacher_home_screen.dart';
import 'quiz_screen.dart';

class DrawingScreen extends StatefulWidget {
  final String materialTitle;
  final String? backgroundUrl;
  final bool isPdfDocument;
  final bool isTeacher;
  final String? serverUrl;
  final String? roomId;
  final String? userId;
  final bool isReadOnly;
  final String? sessionId;

  /// PDF export용 자료 목록 (학생 화면에서 필요)
  /// pageId(materialTitle) → page 번호 매핑에 사용
  final String? materialId; // 팀원 추가: 자료 ID
  final String? classId; // 팀원 추가: 클래스 ID
  final List<MaterialModel> materials;
  final List<DocumentPageSource> documentPages;

  const DrawingScreen({
    Key? key,
    required this.materialTitle,
    this.backgroundUrl,
    this.isPdfDocument = false,
    this.materialId,
    this.classId,
    this.isTeacher = false,
    this.serverUrl,
    this.roomId,
    this.userId,
    this.isReadOnly = false,
    this.sessionId,
    this.materials = const [],
    this.documentPages = const [],
  }) : super(key: key);

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  // 버그 #3 수정: dispose에서 context.read 방지용 캐싱
  late final DrawingProvider _drawingProvider;
  DocumentSource? _documentSource;

  bool _isConnecting = false;
  bool _isPreparingDocument = false;

  /// PDF export 진행 중 여부
  /// true일 때 뒤로가기 차단 (PopScope)
  bool _isExporting = false;

  /// 학생이 이해도 체크에 답변 후 팝업을 수동으로 닫은 상태
  bool _pollOverlayDismissed = false;

  /// 교사: 질문 패널 표시 여부 (로컬 UI 토글)
  bool _showQuestionsPanel = false;

  bool get _usesNativeTeacherDrawing =>
      AppConfig.enableNativeTeacherDrawing &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      widget.isTeacher;

  String? get _shareableSessionId {
    final sessionId = widget.sessionId?.trim();
    if (sessionId != null && sessionId.isNotEmpty) return sessionId;

    final roomId = widget.roomId?.trim();
    if (roomId != null && roomId.isNotEmpty) return roomId;
    return null;
  }

  @override
  void initState() {
    super.initState();
    _drawingProvider = context.read<DrawingProvider>();
    _drawingProvider.onRoomJoinedPayload = _handleRoomJoinedPayload;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDrawing();
      _setupSessionEndedListener();
      _setupPresenceCallbacks();
      _setupPollCallbacks();
      _setupQuestionCallbacks();
    });
  }

  Future<void> _initializeDrawing() async {
    final provider = _drawingProvider;

    if (widget.isPdfDocument) {
      debugPrint(
        '[drawing] init pdf materialId=${widget.materialId} '
        'documentPages=${widget.documentPages.length}',
      );
      final initialized = await _prepareServerRenderedDocument(
        pages: widget.documentPages,
      );
      if (!initialized) {
        provider.clearPdfPageSize();
        provider.setBackgroundUrl(null);
        if (widget.materialId != null && widget.materialId!.isNotEmpty) {
          provider.updatePageContext(
            materialId: widget.materialId!,
            pageNumber: 1,
          );
          await _syncNativePageContext(
            materialId: widget.materialId!,
            pageNumber: 1,
          );
          await _loadPersonalPageIfNeeded(
            _personalPageKeyFor(materialId: widget.materialId!, pageNumber: 1),
          );
        } else {
          await _loadPersonalPageIfNeeded(
            _personalPageKeyForTitle(widget.materialTitle),
          );
        }
      }
    } else {
      provider.clearPdfPageSize();
      provider.setBackgroundUrl(widget.backgroundUrl);
      if (widget.materialId != null && widget.materialId!.isNotEmpty) {
        provider.updatePageContext(
          materialId: widget.materialId!,
          pageNumber: 1,
        );
        await _syncNativePageContext(
          materialId: widget.materialId!,
          pageNumber: 1,
        );
      }
      await _loadPersonalPageIfNeeded(
        _personalPageKeyForTitle(widget.materialTitle),
      );
    }

    // 그리기 모드 기본 활성화
    provider.setDrawingMode(true);
    debugPrint(
      widget.isTeacher
          ? 'Drawing mode enabled for teacher'
          : 'Drawing mode enabled for student personal drawing',
    );

    if (widget.serverUrl != null &&
        widget.roomId != null &&
        widget.userId != null) {
      await _connectSocket();
    }
  }

  Future<bool> _prepareServerRenderedDocument({
    required List<DocumentPageSource> pages,
    String? materialIdOverride,
  }) async {
    final materialId = materialIdOverride?.trim().isNotEmpty == true
        ? materialIdOverride!.trim()
        : widget.materialId?.trim();
    if (materialId == null || materialId.isEmpty || pages.isEmpty) {
      debugPrint(
        '[drawing] prepare skipped materialId=$materialId pages=${pages.length}',
      );
      return false;
    }

    final normalizedPages = pages
        .where((page) => (page.imagePath?.trim().isNotEmpty ?? false))
        .toList();
    if (normalizedPages.isEmpty) {
      debugPrint('[drawing] prepare skipped no imageUrl pages=${pages.length}');
      return false;
    }

    setState(() => _isPreparingDocument = true);
    try {
      final pageNumbers = normalizedPages
          .map((page) => page.pageNumber)
          .toSet();
      final currentPage = _documentSource?.materialId == materialId
          ? _documentSource?.currentPage
          : null;
      final initialPage =
          currentPage != null && pageNumbers.contains(currentPage)
          ? currentPage
          : pageNumbers.contains(1)
          ? 1
          : normalizedPages.first.pageNumber;
      final document = DocumentSource(
        materialId: materialId,
        pdfUrl: widget.backgroundUrl ?? '',
        localPdfPath: '',
        pageCount: normalizedPages.length,
        currentPage: initialPage,
        pages: normalizedPages,
      );
      await _applyDocumentPage(
        document: document,
        pageNumber: initialPage,
        persistCurrentDraft: false,
      );
      return true;
    } finally {
      if (mounted) {
        setState(() => _isPreparingDocument = false);
      }
    }
  }

  Future<void> _loadPersonalPageIfNeeded(String pageKey) async {
    if (widget.isTeacher) return;
    await context.read<PersonalDrawingProvider>().loadPage(pageKey);
  }

  String _personalPageKeyFor({
    required String materialId,
    required int pageNumber,
  }) {
    return '${_personalStorageScope()}:$materialId:$pageNumber';
  }

  String _personalPageKeyForTitle(String title) {
    return '${_personalStorageScope()}:$title';
  }

  String _personalStorageScope() {
    final roomId = widget.roomId?.trim();
    if (roomId != null && roomId.isNotEmpty) return roomId;

    final sessionId = widget.sessionId?.trim();
    if (sessionId != null && sessionId.isNotEmpty) return sessionId;

    final materialId = widget.materialId?.trim();
    if (materialId != null && materialId.isNotEmpty) return materialId;

    return 'local';
  }

  Map<String, int> _createPersonalExportPageMapping() {
    final document = _documentSource;
    if (document != null) {
      return {
        for (final page in document.pages)
          _personalPageKeyFor(
            materialId: document.materialId,
            pageNumber: page.pageNumber,
          ): page.pageNumber,
      };
    }

    return {
      for (int i = 0; i < widget.materials.length; i++)
        _personalPageKeyForTitle(widget.materials[i].title): i + 1,
    };
  }

  Future<void> _syncNativePageContext({
    required String materialId,
    required int pageNumber,
  }) async {
    if (!_usesNativeTeacherDrawing) return;
    try {
      await NativeDrawingBridge.setPageContext(
        materialId: materialId,
        pageNumber: pageNumber,
      );
    } catch (e) {
      debugPrint('Failed to sync native page context: $e');
    }
  }

  Future<void> _switchTeacherPageDraft(String draftKey) async {
    if (!widget.isTeacher) return;
    await _drawingProvider.switchLocalDraft(draftKey: draftKey);
  }

  Future<void> _captureCurrentTeacherPage() async {
    try {
      await _drawingProvider.persistCurrentDraft();
    } catch (e) {
      debugPrint('Failed to persist current page draft: $e');
    }
  }

  Future<void> _restoreCurrentTeacherPage() async {
    if (!_usesNativeTeacherDrawing) return;
    try {
      await NativeDrawingBridge.replaceDrawingSnapshot(
        _drawingProvider.buildNativeSnapshotPayload(),
      );
    } catch (e) {
      debugPrint('Failed to restore native drawing snapshot: $e');
    }
  }

  bool get _hasPagedDocument =>
      _documentSource != null && _documentSource!.pageCount > 0;

  bool get _canGoPreviousPage =>
      _hasPagedDocument && _documentSource!.currentPage > 1;

  bool get _canGoNextPage =>
      _hasPagedDocument &&
      _documentSource!.currentPage < _documentSource!.pageCount;

  Future<void> _goToPreviousPage() async {
    if (!_canGoPreviousPage) return;
    await _goToDocumentPage(_documentSource!.currentPage - 1);
  }

  Future<void> _goToNextPage() async {
    if (!_canGoNextPage) return;
    await _goToDocumentPage(_documentSource!.currentPage + 1);
  }

  Future<void> _goToDocumentPage(int pageNumber) async {
    final document = _documentSource;
    if (document == null) return;
    if (pageNumber < 1 || pageNumber > document.pageCount) return;

    setState(() => _isPreparingDocument = true);
    try {
      await _applyDocumentPage(document: document, pageNumber: pageNumber);
    } catch (e) {
      debugPrint('Failed to change PDF page: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('페이지 이동 실패: $e'),
          backgroundColor: Colors.orange,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isPreparingDocument = false);
      }
    }
  }

  Future<void> _applyDocumentPage({
    required DocumentSource document,
    required int pageNumber,
    bool persistCurrentDraft = true,
  }) async {
    DocumentPageSource? selectedPage;
    for (final page in document.pages) {
      if (page.pageNumber == pageNumber) {
        selectedPage = page;
        break;
      }
    }
    if (selectedPage == null) {
      throw Exception('선택한 페이지를 찾을 수 없습니다.');
    }

    if (persistCurrentDraft) {
      await _captureCurrentTeacherPage();
    }

    final updatedDocument = document.copyWith(currentPage: pageNumber);
    _documentSource = updatedDocument;
    _drawingProvider.updatePageContext(
      materialId: updatedDocument.materialId,
      pageNumber: pageNumber,
    );
    await _syncNativePageContext(
      materialId: updatedDocument.materialId,
      pageNumber: pageNumber,
    );
    await _switchTeacherPageDraft(updatedDocument.pageKeyFor(pageNumber));
    _drawingProvider.setBackgroundUrl(selectedPage.imagePath);
    _drawingProvider.setPdfPageSize(
      width: selectedPage.width,
      height: selectedPage.height,
    );
    await _loadPersonalPageIfNeeded(
      _personalPageKeyFor(
        materialId: updatedDocument.materialId,
        pageNumber: pageNumber,
      ),
    );
    if (!widget.isTeacher) {
      _drawingProvider.requestActivePageSync();
    }
    await _restoreCurrentTeacherPage();
    if (mounted) {
      setState(() {});
    }
  }

  void _handleRoomJoinedPayload(Map<String, dynamic> data) {
    if (!mounted) return;
    final materialRaw = data['material'];
    if (materialRaw is! Map) return;

    final joinedMaterial = SessionJoinMaterial.fromJson(
      Map<String, dynamic>.from(materialRaw),
    );
    if (joinedMaterial.type.toLowerCase() != 'pdf') {
      return;
    }
    if (joinedMaterial.id.isEmpty || joinedMaterial.pages.isEmpty) {
      debugPrint('[drawing] join_success material has no pages');
      return;
    }
    debugPrint(
      '[drawing] join_success materialId=${joinedMaterial.id} '
      'pages=${joinedMaterial.pages.length}',
    );

    unawaited(
      _prepareServerRenderedDocument(
        pages: joinedMaterial.pages,
        materialIdOverride: joinedMaterial.id,
      ),
    );
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
      setState(() => _pollOverlayDismissed = false);
      final pollData = PollStartData.fromJson(data);
      pollProvider.onPollStart(pollData);
      debugPrint('Poll started, showing overlay');
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

    debugPrint('Poll callbacks setup completed');
  }

  /// ===============================
  /// 교사: Poll 시작 다이얼로그
  /// ===============================
  Future<void> _handleStartPoll() async {
    await PollStartDialog.show(
      context,
      onStart:
          ({
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
    debugPrint('handleEndPoll: pollData=${pollState.pollData?.pollId}');
    if (pollState.pollData == null) {
      debugPrint('pollData is null, cannot end poll');
      return;
    }
    _drawingProvider.socketService.sendPollEnd(pollState.pollData!.pollId);
  }

  /// ===============================
  /// 교사: 복습 퀴즈 관리 (모달 바텀시트)
  /// ===============================
  void _openQuizEditor() {
    final sessionId = _shareableSessionId;
    if (sessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('세션 정보가 없어 퀴즈를 관리할 수 없습니다.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.only(top: 8),
          child: QuizEditorWidget(
            key: ValueKey(sessionId),
            sessionId: sessionId,
          ),
        ),
      ),
    );
  }

  void _showQrCodeDialog() {
    final sessionId = _shareableSessionId;
    if (sessionId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('공유할 세션 ID가 없습니다.')));
      return;
    }

    final joinUrl = DeepLinkService().generateJoinWebLink(
      sessionId,
      classId: widget.classId,
      materialId: widget.materialId,
    );

    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.qr_code_2),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'QR 코드 공유',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                QrView(url: joinUrl),
                const SizedBox(height: 16),
                Text(
                  joinUrl,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: joinUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('링크가 복사되었습니다')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('링크 복사'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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

    debugPrint('Presence callbacks setup completed');
  }

  /// ===============================
  /// 질문하기(Q&A) 콜백 설정
  /// 교사: 새 질문 수신 / 학생: 전송 확인
  /// ===============================
  void _setupQuestionCallbacks() {
    final socketService = _drawingProvider.socketService;

    if (widget.isTeacher) {
      final questionProvider = context.read<QuestionProvider>();

      socketService.onQuestionNew = (data) {
        questionProvider.addQuestion(QuestionModel.fromJson(data));
      };

      socketService.onQuestionListResult = (data) {
        final questions = data
            .whereType<Map>()
            .map((e) => QuestionModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        questionProvider.setQuestions(questions);
      };

      // 재입장 시 기존에 쌓인 질문 목록 요청
      socketService.requestQuestionList();
    } else {
      socketService.onQuestionAck = (data) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('질문이 전송됐습니다')));
      };
    }

    debugPrint('Question callbacks setup completed');
  }

  /// ===============================
  /// 학생: 질문하기 다이얼로그
  /// ===============================
  void _openAskQuestionDialog() {
    QuestionAskDialog.show(
      context,
      onSend: (content) {
        _drawingProvider.socketService.askQuestion(
          content: content,
          isAnonymous: true,
        );
      },
    );
  }

  void _handleSessionEnded(Map<String, dynamic> data) {
    final message = data['message'] as String? ?? '교사가 수업을 종료했습니다';

    if (widget.isTeacher) {
      _cleanupAndGoHome();
    } else {
      SessionEndedDialog.showStudentNotification(
        context,
        message: message,
        onConfirm: () {
          final sessionId =
              _drawingProvider.roomId ?? widget.roomId ?? widget.sessionId;
          debugPrint(
            '🎯 QuizScreen sessionId: $sessionId (roomId=${_drawingProvider.roomId}, widgetRoomId=${widget.roomId}, widgetSessionId=${widget.sessionId})',
          );
          if (sessionId == null) {
            debugPrint('❌ sessionId is null, skipping quiz');
            _cleanupAndGoHome();
            return;
          }
          QuizScreen.show(
            context,
            sessionId: sessionId,
            onPassed: () async {
              await _handleExportPdf();
              if (mounted) _cleanupAndGoHome();
            },
            onClose: () {
              if (mounted) _cleanupAndGoHome();
            },
          );
        },
      );
    }
  }

  void _cleanupAndGoHome() {
    _drawingProvider.disconnectSocket();
    _drawingProvider.clear();
    if (widget.isTeacher) {
      context.read<QuestionProvider>().clear();
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => widget.isTeacher
            ? const TeacherHomeScreen()
            : const StudentHomeScreen(),
      ),
      (route) => false,
    );
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
      debugPrint('Socket.IO connection initiated');
    } catch (e) {
      debugPrint('Socket.IO connection failed: $e');
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

    final sessionId = widget.roomId ?? widget.sessionId;
    if (sessionId == null || sessionId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('세션 정보가 없어 종료할 수 없습니다.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final canEnd = await _ensureRequiredQuizCountBeforeEnd(sessionId.trim());
    if (!mounted || !canEnd) return;

    final confirmed = await SessionEndedDialog.showEndConfirmation(context);
    if (!mounted) return;
    if (!confirmed) return;

    SessionEndedDialog.showEndingProgress(context);

    try {
      final response = await ApiService.endSession(sessionId: sessionId.trim());

      if (!mounted) return;
      Navigator.pop(context); // 로딩 팝업 닫기

      if (!response.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('세션 종료 실패: ${response.message}'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      _cleanupAndGoHome();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<bool> _ensureRequiredQuizCountBeforeEnd(String sessionId) async {
    try {
      final questions = await ApiService.getQuizQuestions(sessionId: sessionId);
      if (questions.length == QuizProvider.requiredQuestionCount) {
        return true;
      }

      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '복습퀴즈는 반드시 ${QuizProvider.requiredQuestionCount}개 등록해야 세션을 종료할 수 있습니다. '
            '현재 ${questions.length}개입니다.',
          ),
          backgroundColor: Colors.orange,
          action: SnackBarAction(
            label: '등록',
            textColor: Colors.white,
            onPressed: _openQuizEditor,
          ),
        ),
      );
      return false;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('복습퀴즈 확인 실패: $e'), backgroundColor: Colors.red),
      );
      return false;
    }
  }

  /// ===============================
  /// PDF 내보내기 (학생 전용)
  /// ===============================
  Future<void> _handleExportPdf() async {
    final sessionId =
        _drawingProvider.roomId ?? widget.roomId ?? widget.sessionId;
    if (sessionId == null) {
      _showExportError(message: '세션 정보가 없습니다.', canRetry: false);
      return;
    }

    debugPrint(
      'Export requested: '
      'providerRoomId=${_drawingProvider.roomId} '
      'widgetRoomId=${widget.roomId} '
      'widgetSessionId=${widget.sessionId} '
      'resolvedSessionId=$sessionId',
    );

    setState(() => _isExporting = true);
    PdfExportLoadingDialog.show(context);

    try {
      final personalProvider = context.read<PersonalDrawingProvider>();

      final saveResult = await PdfExportService.export(
        sessionId: sessionId,
        materials: widget.materials,
        personalProvider: personalProvider,
        documentSource: _documentSource,
        pageMapping: _createPersonalExportPageMapping(),
      );

      if (!mounted) return;
      PdfExportLoadingDialog.dismiss(context);
      final savedLocation = await PdfFileService.saveWithPicker(
        bytes: saveResult.bytes,
        fileName: saveResult.fileName,
        dialogTitle: '합성된 PDF 저장 위치를 선택하세요',
      );
      if (!mounted) return;

      if (savedLocation == null || savedLocation.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('PDF 저장이 취소되었습니다.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${saveResult.fileName} 저장 완료'),
            duration: const Duration(seconds: 3),
          ),
        );
      }

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
      _showExportError(message: _resolveUnknownError(e), canRetry: true);
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
  void _showExportError({required String message, required bool canRetry}) {
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
    _drawingProvider.onRoomJoinedPayload = null;
    super.dispose();
  }

  Widget _buildSidebar() {
    return Container(
      width: 64,
      color: AppColors.surface,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            if (widget.isTeacher)
              Consumer<PollProvider>(
                builder: (context, pollProvider, _) {
                  final isActive = pollProvider.state.isActive;
                  return _SidebarNavItem(
                    icon: isActive ? Icons.poll : Icons.poll_outlined,
                    label: '이해도체크',
                    isActive: isActive,
                    onTap: isActive ? _handleEndPoll : _handleStartPoll,
                  );
                },
              ),
            if (widget.isTeacher)
              _SidebarNavItem(
                icon: Icons.quiz_outlined,
                label: '복습퀴즈',
                isActive: false,
                onTap: _openQuizEditor,
              ),
            if (widget.isTeacher)
              Consumer<QuestionProvider>(
                builder: (context, questionProvider, _) {
                  return _SidebarNavItem(
                    icon: Icons.chat_bubble_outline,
                    label: '질문들',
                    isActive: _showQuestionsPanel,
                    badgeCount: questionProvider.unreadCount,
                    onTap: () => setState(
                      () => _showQuestionsPanel = !_showQuestionsPanel,
                    ),
                  );
                },
              ),
            if (!widget.isTeacher)
              _SidebarNavItem(
                icon: Icons.chat_bubble_outline,
                label: '질문하기',
                isActive: false,
                onTap: _openAskQuestionDialog,
              ),
            const SizedBox(height: 4),
            const ParticipantsButton(),
            const Spacer(),
            _SidebarNavItem(
              icon: Icons.logout,
              label: '나가기',
              isActive: false,
              isDanger: true,
              onTap: widget.isTeacher
                  ? _endSession
                  : () => Navigator.maybePop(context),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 44,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _documentSource != null
                  ? '${widget.materialTitle} (${_documentSource!.currentPage}/${_documentSource!.pageCount})'
                  : widget.materialTitle,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.isReadOnly)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accentLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accent, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.visibility,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '읽기 전용',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          if (_hasPagedDocument) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _isPreparingDocument ? null : _goToPreviousPage,
              tooltip: '이전 페이지',
            ),
            Text(
              '${_documentSource!.currentPage}/${_documentSource!.pageCount}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _isPreparingDocument ? null : _goToNextPage,
              tooltip: '다음 페이지',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (!_usesNativeTeacherDrawing) ...[
              const ColorPaletteBar(),
              const SizedBox(width: 12),
              const WidthSelectorBar(),
              const SizedBox(width: 12),
            ],
            if (widget.isTeacher) ...[
              if (_shareableSessionId != null)
                IconButton(
                  icon: const Icon(Icons.qr_code_2),
                  onPressed: _showQrCodeDialog,
                  tooltip: 'QR 코드 공유',
                ),
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
            ] else ...[
              IconButton(
                icon: const Icon(Icons.undo),
                onPressed: _handleStudentUndo,
                tooltip: '내 필기 실행 취소',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _handleStudentClear,
                tooltip: '내 필기 전체 지우기',
              ),
              _isExporting
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primary,
                          ),
                        ),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.picture_as_pdf),
                      onPressed: _handleExportPdf,
                      tooltip: 'PDF 내보내기',
                    ),
            ],
          ],
        ),
      ),
    );
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
        backgroundColor: AppColors.background,
        body: (_isConnecting || _isPreparingDocument)
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text('문서 및 실시간 연결 준비 중...'),
                  ],
                ),
              )
            : Row(
                children: [
                  if (!widget.isReadOnly) _buildSidebar(),
                  Expanded(
                    child: Column(
                      children: [
                        _buildTopBar(),
                        if (!widget.isReadOnly) _buildToolbar(),
                        Expanded(
                          child: Stack(
                            children: [
                              DrawingCanvasWidget(
                                isTeacher: widget.isTeacher,
                                enableTouchInput: true, // 👈 추가 (터치 입력 켜기)
                                showMyStrokes: true, // 👈 추가 (내 필기 보이기)
                              ),

                              if (_hasPagedDocument)
                                Positioned(
                                  bottom: 14,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.72),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Text(
                                        '${_documentSource!.currentPage} / ${_documentSource!.pageCount}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                              // 학생: 이해도 체크 팝업 (캔버스 중앙)
                              if (!widget.isTeacher)
                                Positioned.fill(
                                  child: Consumer<PollProvider>(
                                    builder: (context, pollProvider, _) {
                                      final state = pollProvider.state;
                                      if ((!state.isActive &&
                                              !state.isAnswered) ||
                                          _pollOverlayDismissed) {
                                        return const SizedBox.shrink();
                                      }
                                      return PollOverlay(
                                        pollState: state,
                                        remainingSeconds:
                                            pollProvider.remainingSeconds,
                                        onAnswer: _handlePollAnswer,
                                        onDismiss: state.isAnswered
                                            ? () => setState(
                                                () => _pollOverlayDismissed =
                                                    true,
                                              )
                                            : null,
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 교사: 실시간 집계 결과 좌측 고정 패널
                  if (widget.isTeacher)
                    Consumer<PollProvider>(
                      builder: (context, pollProvider, _) {
                        final state = pollProvider.state;
                        if (!state.isActive && !state.isEnded) {
                          return const SizedBox.shrink();
                        }
                        return SizedBox(
                          width: 170,
                          child: PollResultSheet(
                            pollState: state,
                            remainingSeconds: pollProvider.remainingSeconds,
                            onClose: () => pollProvider.reset(),
                          ),
                        );
                      },
                    ),

                  // 교사: 질문 수신함 좌측 고정 패널
                  if (widget.isTeacher && _showQuestionsPanel)
                    SizedBox(
                      width: 170,
                      child: Consumer<QuestionProvider>(
                        builder: (context, questionProvider, _) {
                          return QuestionsPanel(
                            questions: questionProvider.questions,
                            onDismiss: questionProvider.dismiss,
                          );
                        },
                      ),
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
                            ? AppColors.primary
                            : Colors.grey,
                        tooltip: provider.isDrawingMode
                            ? '이동 모드로 전환'
                            : '그리기 모드로 전환',
                        child: Icon(
                          provider.isDrawingMode ? Icons.edit : Icons.pan_tool,
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
                              ? AppColors.primary.withOpacity(0.9)
                              : Colors.grey.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          provider.isDrawingMode ? '그리기' : '이동/줌',
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
                builder: (context, drawingProvider, personalProvider, child) {
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
                          drawingProvider.setDrawingMode(
                            !drawingProvider.isDrawingMode,
                          );
                        },
                        backgroundColor: drawingProvider.isDrawingMode
                            ? AppColors.primary
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
                              ? AppColors.primary.withOpacity(0.9)
                              : Colors.grey.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          drawingProvider.isDrawingMode ? '내 필기' : '이동/줌',
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

  Future<void> _handleUndo() async {
    final strokes = _drawingProvider.myStrokes;
    if (strokes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('실행 취소할 내용이 없습니다')));
      return;
    }
    final lastStrokeId = strokes.keys.last;
    if (_usesNativeTeacherDrawing) {
      try {
        await NativeDrawingBridge.undoLastStroke();
      } catch (e) {
        debugPrint('Failed to undo native stroke: $e');
      }
    }
    _drawingProvider.sendUndo(lastStrokeId);
  }

  Future<void> _handleClear() async {
    await showDialog(
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
            onPressed: () async {
              if (_usesNativeTeacherDrawing) {
                try {
                  await NativeDrawingBridge.clearDrawing();
                } catch (e) {
                  debugPrint('Failed to clear native drawing: $e');
                }
              }
              _drawingProvider.clear();
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('지우기'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleStudentUndo() async {
    final personalProvider = context.read<PersonalDrawingProvider>();
    if (personalProvider.personalStrokes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('실행 취소할 내 필기가 없습니다')));
      return;
    }
    await personalProvider.undoLastStroke();
  }

  Future<void> _handleStudentClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('내 필기 지우기'),
        content: const Text('현재 페이지의 내 필기를 모두 지우시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('지우기'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await context.read<PersonalDrawingProvider>().clearCurrentPage();
  }
}

/// ===============================
/// 판서 화면 좌측 사이드바 내비게이션 아이템
/// ===============================
class _SidebarNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isDanger;
  final int? badgeCount;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.isDanger = false,
    this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDanger
        ? AppColors.danger
        : isActive
        ? AppColors.primary
        : AppColors.textSecondary;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.primaryLight
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                if (badgeCount != null && badgeCount! > 0)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(minWidth: 14),
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        badgeCount! > 9 ? '9+' : '$badgeCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
