// lib/screens/drawing_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/drawing_provider.dart';
import '../providers/personal_drawing_provider.dart';
import '../widgets/drawing_canvas_widget.dart';

class DrawingScreen extends StatefulWidget {
  final String materialTitle;
  final String? backgroundUrl; // PDF/이미지 URL (선택)
  final bool isTeacher;
  final String? serverUrl; // Socket.IO 서버 URL
  final String? roomId; // 방 ID
  final String? userId; // 사용자 ID

  const DrawingScreen({
    Key? key,
    required this.materialTitle,
    this.backgroundUrl,
    this.isTeacher = false,
    this.serverUrl,
    this.roomId,
    this.userId,
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
    });
  }

  Future<void> _initializeDrawing() async {
    final provider = context.read<DrawingProvider>();

    // 배경 설정
    provider.setBackgroundUrl(widget.backgroundUrl);

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
        title: Text(widget.materialTitle),
        actions: [
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
      floatingActionButton: widget.isTeacher
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