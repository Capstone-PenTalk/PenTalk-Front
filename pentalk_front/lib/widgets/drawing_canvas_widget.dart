
import 'dart:ui' as ui;

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
  final bool enableTouchInput;
  final bool showMyStrokes;
  final ValueChanged<Size>? onCanvasSize;

  const DrawingCanvasWidget({
    Key? key,
    required this.isTeacher,
    required this.enableTouchInput,
    required this.showMyStrokes,
    this.onCanvasSize,
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onCanvasSize?.call(canvasSize);
        });

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
            if (widget.showMyStrokes)
              RepaintBoundary(
                child: _MyDrawingLayer(canvasSize: canvasSize),
              ),

            if (!widget.isTeacher)
              RepaintBoundary(
                child: _StudentPrivateDrawingLayer(canvasSize: canvasSize),
              ),

            // ====================================
            // 레이어 4: 터치 입력 (교사 전용)
            // ====================================
            if (widget.enableTouchInput)
              _TouchInputLayer(
                canvasSize: canvasSize,
                requireDrawingMode: widget.isTeacher,
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

    if (widget.isTeacher) {
      _currentStrokeId = provider.sendDrawStart(point);
    } else {
      _currentStrokeId = provider.startStudentPrivateStroke(point);
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size canvasSize, DrawingProvider provider) {
    if (_currentStrokeId == null) return;

    final point = DrawPoint.fromPixelOffset(details.localPosition, canvasSize);
    _currentPoints.add(point);

    if (widget.isTeacher) {
      provider.sendDrawMove(_currentStrokeId!, point);
    } else {
      provider.appendStudentPrivatePoint(_currentStrokeId!, point);
    }
  }

  void _onPanEnd(Size canvasSize, DrawingProvider provider) {
    if (_currentStrokeId == null) return;

    final points = List<DrawPoint>.from(_currentPoints);
    if (widget.isTeacher) {
      provider.sendDrawEnd(_currentStrokeId!, points);
    } else {
      provider.endStudentPrivateStroke(_currentStrokeId!, points);
    }

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
          return SizedBox.expand(
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

        return const SizedBox.expand(
          child: ColoredBox(color: Colors.white),
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
    return Stack(
      children: [
        Selector<DrawingProvider, List<Stroke>>(
          selector: (context, provider) => provider.othersCompletedStrokes,
          builder: (context, strokes, child) {
            return _RasterizedStrokeLayer(
              canvasSize: canvasSize,
              strokes: strokes,
            );
          },
        ),
        Selector<DrawingProvider, List<Stroke>>(
          selector: (context, provider) => provider.othersActiveStrokeList,
          builder: (context, strokes, child) {
            return SizedBox.expand(
              child: CustomPaint(
                painter: DrawingPainter(
                  strokes: strokes,
                  canvasSize: canvasSize,
                ),
              ),
            );
          },
        ),
      ],
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
    return Stack(
      children: [
        Selector<DrawingProvider, List<Stroke>>(
          selector: (context, provider) => provider.myCompletedStrokes,
          builder: (context, strokes, child) {
            return _RasterizedStrokeLayer(
              canvasSize: canvasSize,
              strokes: strokes,
            );
          },
        ),
        Selector<DrawingProvider, List<Stroke>>(
          selector: (context, provider) => provider.myActiveStrokeList,
          builder: (context, strokes, child) {
            return SizedBox.expand(
              child: CustomPaint(
                painter: DrawingPainter(
                  strokes: strokes,
                  canvasSize: canvasSize,
                ),
              ),
            );
          },
        ),
      ],
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

class _StudentPrivateDrawingLayer extends StatelessWidget {
  final Size canvasSize;

  const _StudentPrivateDrawingLayer({required this.canvasSize});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Selector<DrawingProvider, List<Stroke>>(
          selector: (context, provider) => provider.studentPrivateCompletedStrokes,
          builder: (context, strokes, child) {
            return _RasterizedStrokeLayer(
              canvasSize: canvasSize,
              strokes: strokes,
            );
          },
        ),
        Selector<DrawingProvider, List<Stroke>>(
          selector: (context, provider) => provider.studentPrivateActiveStrokeList,
          builder: (context, strokes, child) {
            return SizedBox.expand(
              child: CustomPaint(
                painter: DrawingPainter(
                  strokes: strokes,
                  canvasSize: canvasSize,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _RasterizedStrokeLayer extends StatefulWidget {
  final List<Stroke> strokes;
  final Size canvasSize;

  const _RasterizedStrokeLayer({
    required this.strokes,
    required this.canvasSize,
  });

  @override
  State<_RasterizedStrokeLayer> createState() => _RasterizedStrokeLayerState();
}

class _RasterizedStrokeLayerState extends State<_RasterizedStrokeLayer> {
  ui.Image? _image;
  int _signature = 0;
  int _renderedSignature = -1;
  Size? _lastSize;
  bool _isRendering = false;

  @override
  void didUpdateWidget(covariant _RasterizedStrokeLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rasterizeIfNeeded();
  }

  @override
  void initState() {
    super.initState();
    _rasterizeIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.canvasSize.isEmpty) {
      return const SizedBox.shrink();
    }
    final useVectorFallback = _image == null ||
        _isRendering ||
        _renderedSignature != _signature;
    return Stack(
      children: [
        if (_image != null)
          SizedBox.expand(
            child: RawImage(
              image: _image,
              filterQuality: FilterQuality.low,
            ),
          ),
        if (useVectorFallback)
          SizedBox.expand(
            child: CustomPaint(
              painter: DrawingPainter(
                strokes: widget.strokes,
                canvasSize: widget.canvasSize,
              ),
            ),
          ),
      ],
    );
  }

  void _rasterizeIfNeeded() {
    if (widget.canvasSize.isEmpty) return;
    final signature = _computeSignature(widget.strokes);
    if (_image != null &&
        _lastSize == widget.canvasSize &&
        _signature == signature) {
      return;
    }
    _signature = signature;
    _lastSize = widget.canvasSize;
    _rasterize();
  }

  int _computeSignature(List<Stroke> strokes) {
    var sum = strokes.length;
    for (final stroke in strokes) {
      sum = 31 * sum + stroke.strokeId.hashCode;
      sum = 31 * sum + stroke.points.length;
      sum = 31 * sum + (stroke.refinedPoints?.length ?? 0);
    }
    return sum;
  }

  Future<void> _rasterize() async {
    _isRendering = true;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final painter = DrawingPainter(
      strokes: widget.strokes,
      canvasSize: widget.canvasSize,
    );
    painter.paint(canvas, widget.canvasSize);
    final picture = recorder.endRecording();
    final width = widget.canvasSize.width.ceil();
    final height = widget.canvasSize.height.ceil();
    if (width == 0 || height == 0) return;
    final image = await picture.toImage(width, height);
    if (!mounted) return;
    setState(() {
      _image = image;
      _renderedSignature = _signature;
      _isRendering = false;
    });
  }
}

/// ===============================
/// 터치 입력 레이어
/// ===============================
class _TouchInputLayer extends StatelessWidget {
  final Size canvasSize;
  final bool requireDrawingMode;
  final int? currentStrokeId;
  final List<DrawPoint> currentPoints;
  final Function(DragStartDetails, Size, DrawingProvider) onPanStart;
  final Function(DragUpdateDetails, Size, DrawingProvider) onPanUpdate;
  final Function(Size, DrawingProvider) onPanEnd;

  const _TouchInputLayer({
    required this.canvasSize,
    required this.requireDrawingMode,
    required this.currentStrokeId,
    required this.currentPoints,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  Widget _buildDetector(BuildContext context) {
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
  }

  @override
  Widget build(BuildContext context) {
    if (!requireDrawingMode) {
      return _buildDetector(context);
    }

    return Selector<DrawingProvider, bool>(
      selector: (context, provider) => provider.isDrawingMode,
      builder: (context, isDrawingMode, child) {
        if (!isDrawingMode) return const SizedBox.shrink();
        return _buildDetector(context);
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
        if (isConnected) {
          return const SizedBox.shrink();
        }
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
