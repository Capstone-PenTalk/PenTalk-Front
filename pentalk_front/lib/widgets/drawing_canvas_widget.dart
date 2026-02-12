import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/drawing_provider.dart';
import '../providers/personal_drawing_provider.dart';
import '../models/drawing_models.dart';
import '../utils/coordinate_scaler.dart';
import 'drawing_painter.dart';

/// ===============================
/// 판서 캔버스 위젯 (레이어 분리 + 최적화 + InteractiveViewer)
/// CoordinateScaler 통합으로 정확한 좌표 변환
/// InteractiveViewer로 줌/팬 지원
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

  // 배경 이미지 크기 (로드되면 설정됨)
  Size? _backgroundImageSize;

  // InteractiveViewer 컨트롤러
  final TransformationController _transformationController =
  TransformationController();

  // 현재 줌 레벨
  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();

    // 줌 변경 감지
    _transformationController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final matrix = _transformationController.value;
    final newScale = matrix.getMaxScaleOnAxis();

    if ((_currentScale - newScale).abs() > 0.01) {
      setState(() {
        _currentScale = newScale;
      });

      debugPrint('Zoom level: ${_currentScale.toStringAsFixed(2)}x');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);

        return Consumer<DrawingProvider>(
          builder: (context, provider, child) {
            // 그리기 모드일 때는 InteractiveViewer 비활성화
            final isDrawingMode = provider.isDrawingMode && widget.isTeacher;

            return Stack(
              children: [
                // ====================================
                // InteractiveViewer로 전체 감싸기
                // ====================================
                InteractiveViewer(
                  transformationController: _transformationController,
                  panEnabled: !isDrawingMode, // 그리기 모드에서는 팬 비활성화
                  scaleEnabled: !isDrawingMode, // 그리기 모드에서는 줌 비활성화
                  minScale: 0.5,
                  maxScale: 4.0,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  child: SizedBox(
                    width: canvasSize.width,
                    height: canvasSize.height,
                    child: Stack(
                      children: [
                        // ====================================
                        // 레이어 1: 배경 (문서/이미지/PDF)
                        // ====================================
                        RepaintBoundary(
                          child: _BackgroundLayer(
                            canvasSize: canvasSize,
                            onImageLoaded: (size) {
                              setState(() {
                                _backgroundImageSize = size;
                              });
                            },
                          ),
                        ),

                        // ====================================
                        // 레이어 2: 다른 사람들의 판서 (파란색)
                        // ====================================
                        RepaintBoundary(
                          child: _OthersDrawingLayer(
                            canvasSize: canvasSize,
                            backgroundImageSize: _backgroundImageSize,
                            scale: _currentScale,
                          ),
                        ),

                        // ====================================
                        // 레이어 3: 내 판서 (검은색) - 교사 공용 판서
                        // ====================================
                        if (widget.isTeacher)
                          RepaintBoundary(
                            child: _MyDrawingLayer(
                              canvasSize: canvasSize,
                              backgroundImageSize: _backgroundImageSize,
                              scale: _currentScale,
                            ),
                          ),

                        // ====================================
                        // 레이어 3.5: 개인 필기 레이어 (학생 전용)
                        // ====================================
                        if (!widget.isTeacher)
                          RepaintBoundary(
                            child: _PersonalDrawingLayer(
                              canvasSize: canvasSize,
                              backgroundImageSize: _backgroundImageSize,
                              scale: _currentScale,
                            ),
                          ),

                        // ====================================
                        // 레이어 4: 터치 입력
                        // ====================================
                        // 교사: 공용 판서용
                        if (widget.isTeacher && isDrawingMode)
                          _TouchInputLayer(
                            canvasSize: canvasSize,
                            backgroundImageSize: _backgroundImageSize,
                            currentStrokeId: _currentStrokeId,
                            currentPoints: _currentPoints,
                            transformationController: _transformationController,
                            onPanStart: _onPanStart,
                            onPanUpdate: _onPanUpdate,
                            onPanEnd: _onPanEnd,
                          ),

                        // 학생: 개인 필기용
                        if (!widget.isTeacher && isDrawingMode)
                          _PersonalTouchInputLayer(
                            canvasSize: canvasSize,
                            backgroundImageSize: _backgroundImageSize,
                            currentStrokeId: _currentStrokeId,
                            currentPoints: _currentPoints,
                            transformationController: _transformationController,
                            onPanStart: _onPersonalPanStart,
                            onPanUpdate: _onPersonalPanUpdate,
                            onPanEnd: _onPersonalPanEnd,
                          ),
                      ],
                    ),
                  ),
                ),

                // ====================================
                // 레이어 5: 소켓 연결 상태 표시
                // ====================================
                Positioned(
                  top: 8,
                  right: 8,
                  child: _SocketStatusIndicator(),
                ),

                // ====================================
                // 레이어 6: 줌 레벨 표시
                // ====================================
                Positioned(
                  top: 8,
                  left: 8,
                  child: _ZoomIndicator(scale: _currentScale),
                ),

                // ====================================
                // 레이어 7: 디버그 정보 (개발용)
                // ====================================
                if (_backgroundImageSize != null)
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Canvas: ${canvasSize.width.toInt()}x${canvasSize.height.toInt()}\n'
                            'Image: ${_backgroundImageSize!.width.toInt()}x${_backgroundImageSize!.height.toInt()}\n'
                            'Zoom: ${_currentScale.toStringAsFixed(2)}x',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),

                // ====================================
                // 레이어 8: 모드 안내 (그리기 모드일 때)
                // ====================================
                if (isDrawingMode)
                  Positioned(
                    bottom: 60,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '✏️ 그리기 모드 (줌/이동 비활성화)',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _onPanStart(DragStartDetails details, CoordinateScaler scaler, DrawingProvider provider) {
    // InteractiveViewer의 변환을 고려한 실제 로컬 좌표 계산
    final localPosition = _getTransformedPosition(details.localPosition);

    // 터치가 콘텐츠 영역 안인지 확인
    if (!scaler.isInContentArea(localPosition)) {
      return;
    }

    _currentPoints.clear();

    final point = scaler.pixelToNormalized(localPosition);
    _currentPoints.add(point);

    _currentStrokeId = provider.sendDrawStart(point);
  }

  void _onPanUpdate(DragUpdateDetails details, CoordinateScaler scaler, DrawingProvider provider) {
    if (_currentStrokeId == null) return;

    // InteractiveViewer의 변환을 고려한 실제 로컬 좌표 계산
    final localPosition = _getTransformedPosition(details.localPosition);

    // 터치가 콘텐츠 영역 안인지 확인
    if (!scaler.isInContentArea(localPosition)) {
      return;
    }

    final point = scaler.pixelToNormalized(localPosition);
    _currentPoints.add(point);

    provider.sendDrawMove(_currentStrokeId!, point);
  }

  void _onPanEnd(CoordinateScaler scaler, DrawingProvider provider) {
    if (_currentStrokeId == null) return;

    provider.sendDrawEnd(_currentStrokeId!, _currentPoints);

    _currentStrokeId = null;
    _currentPoints.clear();
  }

  /// InteractiveViewer의 변환을 역으로 적용하여 실제 좌표 계산
  Offset _getTransformedPosition(Offset screenPosition) {
    final matrix = _transformationController.value.clone()..invert();
    final transformed = MatrixUtils.transformPoint(matrix, screenPosition);
    return transformed;
  }

  /// ===============================
  /// 개인 필기 터치 이벤트 (학생용)
  /// ===============================
  void _onPersonalPanStart(DragStartDetails details, CoordinateScaler scaler, PersonalDrawingProvider provider, Color color, double width) {
    final localPosition = _getTransformedPosition(details.localPosition);

    if (!scaler.isInContentArea(localPosition)) {
      return;
    }

    _currentPoints.clear();
    final point = scaler.pixelToNormalized(localPosition);
    _currentPoints.add(point);

    _currentStrokeId = DateTime.now().millisecondsSinceEpoch;
    provider.startDrawing(_currentStrokeId!, point, color, width);
  }

  void _onPersonalPanUpdate(DragUpdateDetails details, CoordinateScaler scaler, PersonalDrawingProvider provider) {
    if (_currentStrokeId == null) return;

    final localPosition = _getTransformedPosition(details.localPosition);

    if (!scaler.isInContentArea(localPosition)) {
      return;
    }

    final point = scaler.pixelToNormalized(localPosition);
    _currentPoints.add(point);

    provider.updateDrawing(_currentStrokeId!, point);
  }

  void _onPersonalPanEnd(CoordinateScaler scaler, PersonalDrawingProvider provider) {
    if (_currentStrokeId == null) return;

    provider.endDrawing(_currentStrokeId!, _currentPoints);

    _currentStrokeId = null;
    _currentPoints.clear();
  }
}

/// ===============================
/// 배경 레이어
/// ===============================
class _BackgroundLayer extends StatelessWidget {
  final Size canvasSize;
  final Function(Size) onImageLoaded;

  const _BackgroundLayer({
    required this.canvasSize,
    required this.onImageLoaded,
  });

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
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (frame != null) {
                  // 이미지 로드 완료 - 크기 측정
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _getImageSize(backgroundUrl).then((size) {
                      if (size != null) {
                        onImageLoaded(size);
                      }
                    });
                  });
                }
                return child;
              },
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

  Future<Size?> _getImageSize(String url) async {
    try {
      final imageProvider = NetworkImage(url);
      final imageStream = imageProvider.resolve(const ImageConfiguration());
      final completer = Completer<Size?>();

      late ImageStreamListener listener;
      listener = ImageStreamListener((ImageInfo info, bool synchronousCall) {
        final image = info.image;
        completer.complete(Size(
          image.width.toDouble(),
          image.height.toDouble(),
        ));
        imageStream.removeListener(listener);
      }, onError: (dynamic error, StackTrace? stackTrace) {
        debugPrint('Failed to get image size: $error');
        completer.complete(null);
        imageStream.removeListener(listener);
      });

      imageStream.addListener(listener);
      return await completer.future;
    } catch (e) {
      debugPrint('Failed to get image size: $e');
      return null;
    }
  }
}

/// ===============================
/// 다른 사람들의 판서 레이어 (파란색)
/// ===============================
class _OthersDrawingLayer extends StatelessWidget {
  final Size canvasSize;
  final Size? backgroundImageSize;
  final double scale;

  const _OthersDrawingLayer({
    required this.canvasSize,
    required this.backgroundImageSize,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<DrawingProvider, List<Stroke>>(
      selector: (context, provider) => provider.othersAllStrokes,
      shouldRebuild: (previous, next) {
        return previous.length != next.length ||
            !_strokesEqual(previous, next);
      },
      builder: (context, strokes, child) {
        final scaler = CoordinateScaler(
          canvasSize: canvasSize,
          contentSize: backgroundImageSize,
          fit: BoxFit.contain,
        );

        return Positioned.fill(
          child: CustomPaint(
            painter: DrawingPainter(
              strokes: strokes,
              scaler: scaler,
              scale: scale, // 줌 레벨 전달
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
  final Size? backgroundImageSize;
  final double scale;

  const _MyDrawingLayer({
    required this.canvasSize,
    required this.backgroundImageSize,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<DrawingProvider, List<Stroke>>(
      selector: (context, provider) => provider.myAllStrokes,
      shouldRebuild: (previous, next) {
        return previous.length != next.length ||
            !_strokesEqual(previous, next);
      },
      builder: (context, strokes, child) {
        final scaler = CoordinateScaler(
          canvasSize: canvasSize,
          contentSize: backgroundImageSize,
          fit: BoxFit.contain,
        );

        return Positioned.fill(
          child: CustomPaint(
            painter: DrawingPainter(
              strokes: strokes,
              scaler: scaler,
              scale: scale, // 줌 레벨 전달
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
  final Size? backgroundImageSize;
  final int? currentStrokeId;
  final List<DrawPoint> currentPoints;
  final TransformationController transformationController;
  final Function(DragStartDetails, CoordinateScaler, DrawingProvider) onPanStart;
  final Function(DragUpdateDetails, CoordinateScaler, DrawingProvider) onPanUpdate;
  final Function(CoordinateScaler, DrawingProvider) onPanEnd;

  const _TouchInputLayer({
    required this.canvasSize,
    required this.backgroundImageSize,
    required this.currentStrokeId,
    required this.currentPoints,
    required this.transformationController,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  @override
  Widget build(BuildContext context) {
    final scaler = CoordinateScaler(
      canvasSize: canvasSize,
      contentSize: backgroundImageSize,
      fit: BoxFit.contain,
    );

    return Positioned.fill(
      child: GestureDetector(
        onPanStart: (details) {
          final provider = context.read<DrawingProvider>();
          onPanStart(details, scaler, provider);
        },
        onPanUpdate: (details) {
          final provider = context.read<DrawingProvider>();
          onPanUpdate(details, scaler, provider);
        },
        onPanEnd: (details) {
          final provider = context.read<DrawingProvider>();
          onPanEnd(scaler, provider);
        },
        child: Container(color: Colors.transparent),
      ),
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
                decoration: const BoxDecoration(
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

/// ===============================
/// 줌 레벨 표시
/// ===============================
class _ZoomIndicator extends StatelessWidget {
  final double scale;

  const _ZoomIndicator({required this.scale});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.zoom_in,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            '${(scale * 100).toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================
/// 개인 필기 레이어 (학생용)
/// ===============================
class _PersonalDrawingLayer extends StatelessWidget {
  final Size canvasSize;
  final Size? backgroundImageSize;
  final double scale;

  const _PersonalDrawingLayer({
    required this.canvasSize,
    required this.backgroundImageSize,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<PersonalDrawingProvider, ({bool show, List<Stroke> strokes})>(
      selector: (context, provider) => (
      show: provider.showPersonalLayer,
      strokes: provider.allPersonalStrokes,
      ),
      shouldRebuild: (previous, next) {
        return previous.show != next.show ||
            previous.strokes.length != next.strokes.length ||
            !_strokesEqual(previous.strokes, next.strokes);
      },
      builder: (context, data, child) {
        if (!data.show) {
          return const SizedBox.shrink();
        }

        final scaler = CoordinateScaler(
          canvasSize: canvasSize,
          contentSize: backgroundImageSize,
          fit: BoxFit.contain,
        );

        return Positioned.fill(
          child: CustomPaint(
            painter: DrawingPainter(
              strokes: data.strokes,
              scaler: scaler,
              scale: scale,
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
/// 개인 필기 터치 입력 레이어 (학생용)
/// ===============================
class _PersonalTouchInputLayer extends StatelessWidget {
  final Size canvasSize;
  final Size? backgroundImageSize;
  final int? currentStrokeId;
  final List<DrawPoint> currentPoints;
  final TransformationController transformationController;
  final Function(DragStartDetails, CoordinateScaler, PersonalDrawingProvider, Color, double) onPanStart;
  final Function(DragUpdateDetails, CoordinateScaler, PersonalDrawingProvider) onPanUpdate;
  final Function(CoordinateScaler, PersonalDrawingProvider) onPanEnd;

  const _PersonalTouchInputLayer({
    required this.canvasSize,
    required this.backgroundImageSize,
    required this.currentStrokeId,
    required this.currentPoints,
    required this.transformationController,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  @override
  Widget build(BuildContext context) {
    final scaler = CoordinateScaler(
      canvasSize: canvasSize,
      contentSize: backgroundImageSize,
      fit: BoxFit.contain,
    );

    return Positioned.fill(
      child: Consumer<PersonalDrawingProvider>(
        builder: (context, personalProvider, child) {
          final drawingProvider = context.read<DrawingProvider>();

          return GestureDetector(
            onPanStart: (details) {
              onPanStart(
                details,
                scaler,
                personalProvider,
                drawingProvider.currentColor,
                drawingProvider.currentWidth,
              );
            },
            onPanUpdate: (details) {
              onPanUpdate(details, scaler, personalProvider);
            },
            onPanEnd: (details) {
              onPanEnd(scaler, personalProvider);
            },
            child: Container(color: Colors.transparent),
          );
        },
      ),
    );
  }
}