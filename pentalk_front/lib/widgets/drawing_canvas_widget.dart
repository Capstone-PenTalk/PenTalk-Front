
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/drawing_provider.dart';
import '../models/drawing_models.dart';
import 'drawing_painter.dart';

/// ===============================
/// 판서 캔버스 위젯 (레이어 분리 + 최적화)
/// ===============================
class DrawingCanvasWidget extends StatefulWidget {
  final bool isTeacher;

  const DrawingCanvasWidget({
    Key? key,
    required this.isTeacher,
  }) : super(key: key);

  @override
  State<DrawingCanvasWidget> createState() => _DrawingCanvasWidgetState();
}

class _DrawingCanvasWidgetState extends State<DrawingCanvasWidget> {
  int? _currentStrokeId;
  final List<DrawPoint> _currentPoints = [];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);

        return Stack(
          children: [
            // ====================================
            // 레이어 1: 배경 (문서/이미지/PDF)
            // RepaintBoundary로 분리 → 배경은 한 번만 렌더링
            // ====================================
            RepaintBoundary(
              child: _BackgroundLayer(canvasSize: canvasSize),
            ),

            // ====================================
            // 레이어 2: 다른 사람들의 판서 (파란색)
            // RepaintBoundary로 분리
            // ====================================
            RepaintBoundary(
              child: _OthersDrawingLayer(canvasSize: canvasSize),
            ),

            // ====================================
            // 레이어 3: 내 판서 (검은색)
            // RepaintBoundary로 분리
            // ====================================
            RepaintBoundary(
              child: _MyDrawingLayer(canvasSize: canvasSize),
            ),

            // ====================================
            // 레이어 4: 터치 입력 (교사 전용)
            // ====================================
            if (widget.isTeacher)
              _TouchInputLayer(
                canvasSize: canvasSize,
                currentStrokeId: _currentStrokeId,
                currentPoints: _currentPoints,
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
              ),

            // ====================================
            // 레이어 5: 소켓 연결 상태 표시
            // ====================================
            Positioned(
              top: 8,
              right: 8,
              child: _SocketStatusIndicator(),
            ),
          ],
        );
      },
    );
  }

  void _onPanStart(DragStartDetails details, Size canvasSize, DrawingProvider provider) {
    _currentPoints.clear();

    final point = DrawPoint.fromPixelOffset(details.localPosition, canvasSize);
    _currentPoints.add(point);

    _currentStrokeId = provider.sendDrawStart(point);
  }

  void _onPanUpdate(DragUpdateDetails details, Size canvasSize, DrawingProvider provider) {
    if (_currentStrokeId == null) return;

    final point = DrawPoint.fromPixelOffset(details.localPosition, canvasSize);
    _currentPoints.add(point);

    provider.sendDrawMove(_currentStrokeId!, point);
  }

  void _onPanEnd(Size canvasSize, DrawingProvider provider) {
    if (_currentStrokeId == null) return;

    provider.sendDrawEnd(_currentStrokeId!, _currentPoints);

    _currentStrokeId = null;
    _currentPoints.clear();
  }
}

/// ===============================
/// 배경 레이어
/// ===============================
class _BackgroundLayer extends StatelessWidget {
  final Size canvasSize;

  const _BackgroundLayer({required this.canvasSize});

  @override
  Widget build(BuildContext context) {
    return Selector<DrawingProvider, String?>(
      selector: (context, provider) => provider.backgroundUrl,
      builder: (context, backgroundUrl, child) {
        if (backgroundUrl != null && backgroundUrl.isNotEmpty) {
          return Positioned.fill(
            child: Image.network(
              backgroundUrl,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.white,
                  child: const Center(
                    child: Icon(Icons.error, color: Colors.red, size: 48),
                  ),
                );
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: Colors.white,
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              },
            ),
          );
        }

        return Positioned.fill(
          child: Container(color: Colors.white),
        );
      },
    );
  }
}

/// ===============================
/// 다른 사람들의 판서 레이어 (파란색)
/// ===============================
class _OthersDrawingLayer extends StatelessWidget {
  final Size canvasSize;

  const _OthersDrawingLayer({required this.canvasSize});

  @override
  Widget build(BuildContext context) {
    return Selector<DrawingProvider, List<Stroke>>(
      selector: (context, provider) => provider.othersAllStrokes,
      shouldRebuild: (previous, next) {
        return previous.length != next.length ||
            !_strokesEqual(previous, next);
      },
      builder: (context, strokes, child) {
        return Positioned.fill(
          child: CustomPaint(
            painter: DrawingPainter(
              strokes: strokes,
              canvasSize: canvasSize,
            ),
          ),
        );
      },
    );
  }

  bool _strokesEqual(List<Stroke> a, List<Stroke> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].strokeId != b[i].strokeId) return false;
      if (a[i].points.length != b[i].points.length) return false;
    }
    return true;
  }
}

/// ===============================
/// 내 판서 레이어 (검은색 또는 선택한 색)
/// ===============================
class _MyDrawingLayer extends StatelessWidget {
  final Size canvasSize;

  const _MyDrawingLayer({required this.canvasSize});

  @override
  Widget build(BuildContext context) {
    return Selector<DrawingProvider, List<Stroke>>(
      selector: (context, provider) => provider.myAllStrokes,
      shouldRebuild: (previous, next) {
        return previous.length != next.length ||
            !_strokesEqual(previous, next);
      },
      builder: (context, strokes, child) {
        return Positioned.fill(
          child: CustomPaint(
            painter: DrawingPainter(
              strokes: strokes,
              canvasSize: canvasSize,
            ),
          ),
        );
      },
    );
  }

  bool _strokesEqual(List<Stroke> a, List<Stroke> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].strokeId != b[i].strokeId) return false;
      if (a[i].points.length != b[i].points.length) return false;
    }
    return true;
  }
}

/// ===============================
/// 터치 입력 레이어 (교사 전용)
/// ===============================
class _TouchInputLayer extends StatelessWidget {
  final Size canvasSize;
  final int? currentStrokeId;
  final List<DrawPoint> currentPoints;
  final Function(DragStartDetails, Size, DrawingProvider) onPanStart;
  final Function(DragUpdateDetails, Size, DrawingProvider) onPanUpdate;
  final Function(Size, DrawingProvider) onPanEnd;

  const _TouchInputLayer({
    required this.canvasSize,
    required this.currentStrokeId,
    required this.currentPoints,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<DrawingProvider, bool>(
      selector: (context, provider) => provider.isDrawingMode,
      builder: (context, isDrawingMode, child) {
        if (!isDrawingMode) return const SizedBox.shrink();

        return Positioned.fill(
          child: GestureDetector(
            onPanStart: (details) {
              final provider = context.read<DrawingProvider>();
              onPanStart(details, canvasSize, provider);
            },
            onPanUpdate: (details) {
              final provider = context.read<DrawingProvider>();
              onPanUpdate(details, canvasSize, provider);
            },
            onPanEnd: (details) {
              final provider = context.read<DrawingProvider>();
              onPanEnd(canvasSize, provider);
            },
            child: Container(color: Colors.transparent),
          ),
        );
      },
    );
  }
}

/// ===============================
/// 소켓 연결 상태 표시
/// ===============================
class _SocketStatusIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Selector<DrawingProvider, bool>(
      selector: (context, provider) => provider.isSocketConnected,
      builder: (context, isConnected, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isConnected ? Colors.green : Colors.red,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                isConnected ? '연결됨' : '연결 안 됨',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}