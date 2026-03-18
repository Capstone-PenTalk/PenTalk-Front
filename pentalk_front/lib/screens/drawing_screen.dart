
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/drawing_provider.dart';
import '../providers/personal_drawing_provider.dart';
import '../providers/participants_provider.dart';
import '../widgets/drawing_canvas_widget.dart';
import '../widgets/session_ended_dialog.dart';
import '../widgets/participants_button.dart';
import '../services/api_service.dart';

class DrawingScreen extends StatefulWidget {
  final String materialTitle;
  final String? backgroundUrl;
  final bool isTeacher;
  final String? serverUrl;
  final String? roomId;
  final String? userId;
  final bool isReadOnly;  // ✅ 읽기 전용 모드
  final String? sessionId;  // ✅ 저장된 세션 ID (읽기 전용 시 사용)

  const DrawingScreen({
    Key? key,
    required this.materialTitle,
    this.backgroundUrl,
    this.isTeacher = false,
    this.serverUrl,
    this.roomId,
    this.userId,
    this.isReadOnly = false,  // ✅ 기본값: 편집 가능
    this.sessionId,  // ✅ 읽기 전용 시 필수
  }) : super(key: key);

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDrawing();
      _setupSessionEndedListener();
      _setupPresenceCallbacks(); // ✅ 이미 추가되어 있음
    });
  }

  Future<void> _initializeDrawing() async {
    final provider = context.read<DrawingProvider>();

    // 배경 설정
    provider.setBackgroundUrl(widget.backgroundUrl);

    // ========================================
    // ✅ 읽기 전용 모드: 저장된 판서 데이터 로드
    // ========================================
    if (widget.isReadOnly && widget.sessionId != null) {
      debugPrint('📖 Loading saved whiteboard: ${widget.sessionId}');

      try {
        setState(() {
          _isConnecting = true;
        });

        final response = await ApiService.getWhiteboard(
          sessionId: widget.sessionId!,
        );

        if (response.success && response.data != null) {
          // 판서 데이터 로드
          provider.loadSavedStrokes(response.data!.strokes);

          debugPrint('✅ Whiteboard loaded: ${response.data!.strokes.length} strokes');
          debugPrint('📖 Read-only mode: ${response.data!.readOnly}');
        } else {
          debugPrint('❌ Failed to load whiteboard: ${response.message}');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('판서 데이터 로드 실패: ${response.message ?? "알 수 없는 오류"}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('❌ Load whiteboard error: $e');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('오류: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isConnecting = false;
          });
        }
      }

      return; // 읽기 전용 모드는 여기서 종료
    }

    // ========================================
    // 편집 가능 모드 (기존 로직)
    // ========================================

    // 그리기 모드 (교사는 기본 활성화)
    if (widget.isTeacher) {
      provider.setDrawingMode(true);
      debugPrint('Drawing mode enabled for teacher');
    } else {
      // 학생: 개인 필기 로드
      final personalProvider = context.read<PersonalDrawingProvider>();
      await personalProvider.loadPage(widget.materialTitle);
      debugPrint('✅ Personal strokes loaded for: ${widget.materialTitle}');
    }

    // Socket.IO 연결
    if (widget.serverUrl != null &&
        widget.roomId != null &&
        widget.userId != null) {
      await _connectSocket();
    } else {
      debugPrint('Socket.IO connection skipped: missing parameters');
      debugPrint('serverUrl: ${widget.serverUrl}');
      debugPrint('roomId: ${widget.roomId}');
      debugPrint('userId: ${widget.userId}');
    }
  }

  /// 세션 종료 이벤트 리스너 설정
  void _setupSessionEndedListener() {
    final provider = context.read<DrawingProvider>();

    provider.onSessionEnded = (data) {
      _handleSessionEnded(data);
    };
  }

  /// ===============================
  /// ✅ Presence 콜백 설정 (신규 메서드!)
  /// ===============================
  void _setupPresenceCallbacks() {
    final drawingProvider = context.read<DrawingProvider>();
    final participantsProvider = context.read<ParticipantsProvider>();

    final socketService = drawingProvider.socketService;

    // PRESENCE_STATE 콜백
    socketService.onPresenceState = (participants) {
      participantsProvider.setParticipants(participants);
      debugPrint('👥 Presence state updated: ${participants.length} participants');
    };

    // PRESENCE_JOIN 콜백
    socketService.onPresenceJoin = (participant) {
      participantsProvider.addParticipant(participant);
      debugPrint('✅ Participant joined: ${participant.userId} (${participant.role})');
    };

    // PRESENCE_LEAVE 콜백
    socketService.onPresenceLeave = (userId, role) {
      participantsProvider.removeParticipant(userId, role);
      debugPrint('❌ Participant left: $userId ($role)');
    };

    debugPrint('🔔 Presence callbacks setup completed');
  }

  /// 세션 종료 이벤트 처리
  void _handleSessionEnded(Map<String, dynamic> data) {
    final message = data['message'] as String? ?? '교사가 수업을 종료했습니다';

    if (widget.isTeacher) {
      // 교사: 팝업 없이 바로 홈으로
      _cleanupAndGoHome();
    } else {
      // 학생: 알림 팝업 표시
      SessionEndedDialog.showStudentNotification(
        context,
        message: message,
        onConfirm: _cleanupAndGoHome,
      );
    }
  }

  /// 정리 후 홈 화면으로 이동
  void _cleanupAndGoHome() {
    final provider = context.read<DrawingProvider>();

    // 소켓 연결 해제
    provider.disconnectSocket();

    // 상태 초기화
    provider.clear();

    // 홈으로 이동
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  Future<void> _connectSocket() async {
    setState(() {
      _isConnecting = true;
    });

    try {
      final provider = context.read<DrawingProvider>();

      await provider.connectSocket(
        serverUrl: widget.serverUrl!,
        userId: widget.userId!,
        roomId: widget.roomId!,
        isTeacher: widget.isTeacher,
        materialTitle: widget.materialTitle,  // ✅ 세션 저장용
        backgroundUrl: widget.backgroundUrl,  // ✅ 세션 저장용
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
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  /// 세션 종료 (교사 전용)
  Future<void> _endSession() async {
    if (!widget.isTeacher) return;

    // 확인 팝업
    final confirmed = await SessionEndedDialog.showEndConfirmation(context);
    if (!confirmed) return;

    // 로딩 팝업 표시
    SessionEndedDialog.showEndingProgress(context);

    try {
      // API 호출
      final response = await ApiService.endSession(
        sessionId: widget.roomId!,
      );

      if (!mounted) return;

      // 로딩 팝업 닫기
      Navigator.pop(context);

      if (response.success) {
        debugPrint('✅ Session ended successfully');
        // session:ended 이벤트를 받으면 자동으로 처리됨
      } else {
        // 에러 처리
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('세션 종료 실패: ${response.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      // 로딩 팝업 닫기
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('오류: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    // Socket 연결 해제
    context.read<DrawingProvider>().disconnectSocket();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(child: Text(widget.materialTitle)),
            // ✅ 읽기 전용 배지
            if (widget.isReadOnly)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          // ========================================
          // ✅ 읽기 전용 모드에서는 편집 버튼 모두 숨김!
          // ========================================
          if (!widget.isReadOnly) ...[
            // 교사용 컨트롤
            if (widget.isTeacher) ...[
              // 펜 색상 선택
              IconButton(
                icon: Consumer<DrawingProvider>(
                  builder: (context, provider, child) {
                    return Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: provider.currentColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey),
                      ),
                    );
                  },
                ),
                onPressed: _showColorPicker,
                tooltip: '색상 선택',
              ),
              // 펜 굵기 선택
              IconButton(
                icon: const Icon(Icons.line_weight),
                onPressed: _showWidthPicker,
                tooltip: '굵기 선택',
              ),
              // Undo (최근 선 삭제)
              IconButton(
                icon: const Icon(Icons.undo),
                onPressed: _handleUndo,
                tooltip: '실행 취소',
              ),
              // 전체 지우기
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _handleClear,
                tooltip: '전체 지우기',
              ),
            ],

            // 참여자 버튼 (편집 모드에서만)
            const ParticipantsButton(),

            // 세션 종료 버튼 (교사만)
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
          : DrawingCanvasWidget(
        isTeacher: widget.isTeacher,
      ),
      // 교사용: 그리기/이동 모드 토글
      // 학생용: 내 필기 보기/끄기 + 그리기/이동 모드 토글
      // ✅ 읽기 전용: 버튼 없음 (스크롤/줌만 가능)
      floatingActionButton: widget.isReadOnly
          ? null  // ✅ 읽기 전용 모드에서는 버튼 없음
          : widget.isTeacher
          ? Consumer<DrawingProvider>(
        builder: (context, provider, child) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 그리기/이동 모드 토글
              FloatingActionButton(
                heroTag: 'drawing_mode',
                onPressed: () {
                  provider.setDrawingMode(!provider.isDrawingMode);
                },
                backgroundColor: provider.isDrawingMode
                    ? Colors.blue
                    : Colors.grey,
                tooltip: provider.isDrawingMode ? '이동 모드로 전환' : '그리기 모드로 전환',
                child: Icon(
                  provider.isDrawingMode ? Icons.edit : Icons.pan_tool,
                ),
              ),
              const SizedBox(height: 12),
              // 모드 안내 텍스트
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
        builder: (context, drawingProvider, personalProvider, child) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 내 필기 보기/끄기 토글
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
              // 그리기/이동 모드 토글
              FloatingActionButton(
                heroTag: 'drawing_mode',
                onPressed: () {
                  drawingProvider.setDrawingMode(!drawingProvider.isDrawingMode);
                },
                backgroundColor: drawingProvider.isDrawingMode
                    ? Colors.blue
                    : Colors.grey,
                tooltip: drawingProvider.isDrawingMode
                    ? '이동 모드로 전환'
                    : '그리기 모드로 전환',
                child: Icon(
                  drawingProvider.isDrawingMode ? Icons.edit : Icons.pan_tool,
                ),
              ),
              const SizedBox(height: 12),
              // 모드 안내 텍스트
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
                  drawingProvider.isDrawingMode ? '✏️ 내 필기' : '👆 이동/줌',
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
    );
  }

  void _showColorPicker() {
    final provider = context.read<DrawingProvider>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('펜 색상 선택'),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Colors.black,
              Colors.red,
              Colors.blue,
              Colors.green,
              Colors.orange,
              Colors.purple,
              Colors.brown,
              Colors.pink,
            ].map((color) {
              return InkWell(
                onTap: () {
                  provider.setColor(color);
                  Navigator.pop(context);
                },
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: provider.currentColor == color
                          ? Colors.white
                          : Colors.grey,
                      width: 3,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showWidthPicker() {
    final provider = context.read<DrawingProvider>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('펜 굵기 선택'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [1.0, 2.5, 5.0, 8.0, 12.0].map((width) {
              return ListTile(
                leading: Container(
                  width: 40,
                  height: width,
                  color: Colors.black,
                ),
                title: Text('${width}px'),
                selected: provider.currentWidth == width,
                onTap: () {
                  provider.setWidth(width);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _handleUndo() {
    final provider = context.read<DrawingProvider>();
    final strokes = provider.myStrokes;

    if (strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('실행 취소할 내용이 없습니다')),
      );
      return;
    }

    // 마지막 선의 ID 가져오기
    final lastStrokeId = strokes.keys.last;
    provider.sendUndo(lastStrokeId);
  }

  void _handleClear() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('전체 지우기'),
          content: const Text('모든 판서 내용을 지우시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                context.read<DrawingProvider>().clear();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('지우기'),
            ),
          ],
        );
      },
    );
  }
}