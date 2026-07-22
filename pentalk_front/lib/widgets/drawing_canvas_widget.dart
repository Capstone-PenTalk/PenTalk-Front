import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../native_drawing.dart';
import '../providers/drawing_provider.dart';
import '../providers/personal_drawing_provider.dart';
import '../models/drawing_models.dart';
import '../utils/coordinate_scaler.dart';
import 'drawing_painter.dart';

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
  static const double _minZoomScale = 0.8;
  static const double _maxZoomScale = 1.6;
  static const double _panEnabledScaleThreshold = 1.0;

  int? _currentStrokeId;
  final List<DrawPoint> _currentPoints = [];

  // 배경 이미지 크기 (로드되면 설정됨)
  Size? _decodedImageSize;

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

  void _centerViewportAtCurrentScale(Size canvasSize) {
    final clampedScale = _currentScale.clamp(_minZoomScale, _maxZoomScale);
    final dx = (canvasSize.width - (canvasSize.width * clampedScale)) / 2;
    final dy = (canvasSize.height - (canvasSize.height * clampedScale)) / 2;
    _transformationController.value = Matrix4.diagonal3Values(
      clampedScale,
      clampedScale,
      1.0,
    )..setTranslationRaw(dx, dy, 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onCanvasSize?.call(canvasSize);
        });

        final isDrawingMode = context.select<DrawingProvider, bool>(
          (provider) => provider.isDrawingMode,
        );
        final useNativeTeacherInput =
            AppConfig.enableNativeTeacherDrawing &&
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.iOS &&
            widget.isTeacher;
        final pdfPageSize = context.select<DrawingProvider, Size?>((provider) {
          final width = provider.pdfWidth;
          final height = provider.pdfHeight;
          if (width == null || height == null || width <= 0 || height <= 0) {
            return null;
          }
          return Size(width, height);
        });
        final contentSize = pdfPageSize ?? _decodedImageSize;
        final backgroundScaler = CoordinateScaler(
          canvasSize: canvasSize,
          contentSize: contentSize,
          fit: BoxFit.contain,
        );
        final contentRect = backgroundScaler.contentRect;

        return Stack(
          children: [
            // ====================================
            // InteractiveViewer로 전체 감싸기
            // ====================================
            InteractiveViewer(
              transformationController: _transformationController,
              panEnabled:
                  !isDrawingMode && _currentScale > _panEnabledScaleThreshold,
              scaleEnabled: !isDrawingMode, // 그리기 모드에서는 줌 비활성화
              minScale: _minZoomScale,
              maxScale: _maxZoomScale,
              boundaryMargin: EdgeInsets.zero,
              onInteractionEnd: (_) {
                _centerViewportAtCurrentScale(canvasSize);
              },
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
                        contentSize: contentSize,
                        onImageLoaded: (size) {
                          if (_decodedImageSize == size) {
                            return;
                          }
                          setState(() {
                            _decodedImageSize = size;
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
                        contentSize: contentSize,
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
                          contentSize: contentSize,
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
                          contentSize: contentSize,
                          scale: _currentScale,
                        ),
                      ),

                    // ====================================
                    // 레이어 4: 터치 입력
                    // ====================================
                    if (useNativeTeacherInput)
                      Positioned(
                        left: contentRect.left,
                        top: contentRect.top,
                        width: contentRect.width,
                        height: contentRect.height,
                        child: _NativeTeacherInputLayer(
                          isDrawingEnabled: isDrawingMode,
                          renderSize: contentRect.size,
                          contentSize: contentSize,
                        ),
                      ),

                    // 교사: 공용 판서용
                    if (widget.isTeacher &&
                        isDrawingMode &&
                        !useNativeTeacherInput)
                      _TouchInputLayer(
                        canvasSize: canvasSize,
                        contentSize: contentSize,
                        currentStrokeId: _currentStrokeId,
                        currentPoints: _currentPoints,
                        transformationController: _transformationController,
                        onPointerStart: _onPointerStart,
                        onPointerMove: _onPointerMove,
                        onPointerEnd: _onPointerEnd,
                      ),

                    // 학생: 개인 필기용
                    if (!widget.isTeacher && isDrawingMode)
                      _PersonalTouchInputLayer(
                        canvasSize: canvasSize,
                        contentSize: contentSize,
                        currentStrokeId: _currentStrokeId,
                        currentPoints: _currentPoints,
                        transformationController: _transformationController,
                        onPointerStart: _onPersonalPointerStart,
                        onPointerMove: _onPersonalPointerMove,
                        onPointerEnd: _onPersonalPointerEnd,
                      ),
                  ],
                ),
              ),
            ),

            // ====================================
            // 레이어 5: 소켓 연결 상태 표시
            // ====================================
            Positioned(top: 8, right: 8, child: _SocketStatusIndicator()),

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
            if (_decodedImageSize != null)
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
                    'Page: ${(contentSize ?? _decodedImageSize)!.width.toInt()}x${(contentSize ?? _decodedImageSize)!.height.toInt()}\n'
                    'Decoded: ${_decodedImageSize!.width.toInt()}x${_decodedImageSize!.height.toInt()}\n'
                    'Content: ${contentRect.width.toInt()}x${contentRect.height.toInt()}\n'
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
                      '그리기 모드 (줌/이동 비활성화)',
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
  }

  void _onPointerStart(
    Offset localPosition,
    CoordinateScaler scaler,
    DrawingProvider provider,
  ) {
    final transformedPosition = _getTransformedPosition(localPosition);

    // 터치가 콘텐츠 영역 안인지 확인
    if (!scaler.isInContentArea(transformedPosition)) {
      return;
    }

    _currentPoints.clear();

    final point = scaler.pixelToNormalized(transformedPosition);
    _currentPoints.add(point);

    if (widget.isTeacher) {
      _currentStrokeId = provider.sendDrawStart(point);
    } else {
      _currentStrokeId = provider.startStudentPrivateStroke(point);
    }
  }

  void _onPointerMove(
    Offset localPosition,
    CoordinateScaler scaler,
    DrawingProvider provider,
  ) {
    if (_currentStrokeId == null) return;

    final transformedPosition = _getTransformedPosition(localPosition);

    // 터치가 콘텐츠 영역 안인지 확인
    if (!scaler.isInContentArea(transformedPosition)) {
      return;
    }

    final point = scaler.pixelToNormalized(transformedPosition);
    _currentPoints.add(point);

    if (widget.isTeacher) {
      provider.sendDrawMove(_currentStrokeId!, point);
    } else {
      provider.appendStudentPrivatePoint(_currentStrokeId!, point);
    }
  }

  void _onPointerEnd(CoordinateScaler scaler, DrawingProvider provider) {
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

  /// InteractiveViewer의 변환을 역으로 적용하여 실제 좌표 계산
  Offset _getTransformedPosition(Offset localPosition) {
    // The touch layers are children of InteractiveViewer's transformed child.
    // Flutter already converts pointer positions into that child coordinate
    // space during hit testing, so applying the inverse matrix here would
    // double-correct the point and shift strokes while zoomed.
    return localPosition;
  }

  /// ===============================
  /// 개인 필기 터치 이벤트 (학생용)
  /// ===============================
  void _onPersonalPointerStart(
    Offset localPosition,
    CoordinateScaler scaler,
    PersonalDrawingProvider provider,
    Color color,
    double width,
  ) {
    final transformedPosition = _getTransformedPosition(localPosition);

    if (!scaler.isInContentArea(transformedPosition)) {
      return;
    }

    _currentPoints.clear();
    final point = scaler.pixelToNormalized(transformedPosition);
    _currentPoints.add(point);

    _currentStrokeId = DateTime.now().millisecondsSinceEpoch;
    provider.startDrawing(_currentStrokeId!, point, color, width);
  }

  void _onPersonalPointerMove(
    Offset localPosition,
    CoordinateScaler scaler,
    PersonalDrawingProvider provider,
  ) {
    if (_currentStrokeId == null) return;

    final transformedPosition = _getTransformedPosition(localPosition);

    if (!scaler.isInContentArea(transformedPosition)) {
      return;
    }

    final point = scaler.pixelToNormalized(transformedPosition);
    _currentPoints.add(point);

    provider.updateDrawing(_currentStrokeId!, point);
  }

  void _onPersonalPointerEnd(
    CoordinateScaler scaler,
    PersonalDrawingProvider provider,
  ) {
    if (_currentStrokeId == null) return;

    final points = List<DrawPoint>.from(_currentPoints);
    provider.endDrawing(_currentStrokeId!, points);

    _currentStrokeId = null;
    _currentPoints.clear();
  }
}

/// ===============================
/// 배경 레이어
/// ===============================
class _BackgroundLayer extends StatelessWidget {
  final Size canvasSize;
  final Size? contentSize;
  final Function(Size) onImageLoaded;

  const _BackgroundLayer({
    required this.canvasSize,
    required this.contentSize,
    required this.onImageLoaded,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<DrawingProvider, String?>(
      selector: (context, provider) => provider.backgroundUrl,
      builder: (context, backgroundUrl, child) {
        if (backgroundUrl != null && backgroundUrl.isNotEmpty) {
          final isRemote =
              backgroundUrl.startsWith('http://') ||
              backgroundUrl.startsWith('https://');
          final contentRect = CoordinateScaler(
            canvasSize: canvasSize,
            contentSize: contentSize,
            fit: BoxFit.contain,
          ).contentRect;
          return SizedBox.expand(
            child: ColoredBox(
              color: Colors.white,
              child: Stack(
                children: [
                  Positioned.fromRect(
                    rect: contentRect,
                    child: isRemote || kIsWeb
                        ? Image.network(
                            backgroundUrl,
                            fit: BoxFit.fill,
                            webHtmlElementStrategy:
                                WebHtmlElementStrategy.fallback,
                            frameBuilder:
                                (
                                  context,
                                  child,
                                  frame,
                                  wasSynchronouslyLoaded,
                                ) {
                                  if (frame != null) {
                                    // 이미지 로드 완료 - 크기 측정.
                                    // 좌표 기준은 서버 page size가 있으면 그 값을 우선 사용한다.
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          _getImageSize(backgroundUrl).then((
                                            size,
                                          ) {
                                            if (size != null) {
                                              onImageLoaded(size);
                                            }
                                          });
                                        });
                                  }
                                  return child;
                                },
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(
                                  Icons.error,
                                  color: Colors.red,
                                  size: 48,
                                ),
                              );
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            },
                          )
                        : Image.file(
                            File(backgroundUrl),
                            fit: BoxFit.fill,
                            frameBuilder:
                                (
                                  context,
                                  child,
                                  frame,
                                  wasSynchronouslyLoaded,
                                ) {
                                  if (frame != null) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          _getImageSize(backgroundUrl).then((
                                            size,
                                          ) {
                                            if (size != null) {
                                              onImageLoaded(size);
                                            }
                                          });
                                        });
                                  }
                                  return child;
                                },
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(
                                  Icons.error,
                                  color: Colors.red,
                                  size: 48,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        }

        return const SizedBox.expand(child: ColoredBox(color: Colors.white));
      },
    );
  }

  Future<Size?> _getImageSize(String url) async {
    try {
      final ImageProvider imageProvider;
      if (!kIsWeb &&
          !url.startsWith('http://') &&
          !url.startsWith('https://')) {
        imageProvider = FileImage(File(url));
      } else {
        imageProvider = NetworkImage(url);
      }
      final imageStream = imageProvider.resolve(const ImageConfiguration());
      final completer = Completer<Size?>();

      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          final image = info.image;
          completer.complete(
            Size(image.width.toDouble(), image.height.toDouble()),
          );
          imageStream.removeListener(listener);
        },
        onError: (dynamic error, StackTrace? stackTrace) {
          debugPrint('Failed to get image size: $error');
          completer.complete(null);
          imageStream.removeListener(listener);
        },
      );

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
  final Size? contentSize;
  final double scale;

  const _OthersDrawingLayer({
    required this.canvasSize,
    required this.contentSize,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<DrawingProvider, List<Stroke>>(
      selector: (context, provider) => provider.othersAllStrokes,
      shouldRebuild: (previous, next) {
        return previous.length != next.length || !_strokesEqual(previous, next);
      },
      builder: (context, strokes, child) {
        final scaler = CoordinateScaler(
          canvasSize: canvasSize,
          contentSize: contentSize,
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
      // color와 width 비교 추가
      if (a[i].color != b[i].color) return false;
      if (a[i].width != b[i].width) return false;
    }
    return true;
  }
}

/// ===============================
/// 내 판서 레이어 (검은색 또는 선택한 색)
/// ===============================
class _MyDrawingLayer extends StatelessWidget {
  final Size canvasSize;
  final Size? contentSize;
  final double scale;

  const _MyDrawingLayer({
    required this.canvasSize,
    required this.contentSize,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<DrawingProvider, List<Stroke>>(
      selector: (context, provider) => provider.myAllStrokes,
      shouldRebuild: (previous, next) {
        return previous.length != next.length || !_strokesEqual(previous, next);
      },
      builder: (context, strokes, child) {
        final scaler = CoordinateScaler(
          canvasSize: canvasSize,
          contentSize: contentSize,
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
      // color와 width 비교 추가
      if (a[i].color != b[i].color) return false;
      if (a[i].width != b[i].width) return false;
    }
    return true;
  }
}

/// ===============================
/// iOS 네이티브 입력 레이어 (교사용)
/// ===============================
class _NativeTeacherInputLayer extends StatefulWidget {
  final bool isDrawingEnabled;
  final Size renderSize;
  final Size? contentSize;

  const _NativeTeacherInputLayer({
    required this.isDrawingEnabled,
    required this.renderSize,
    required this.contentSize,
  });

  @override
  State<_NativeTeacherInputLayer> createState() =>
      _NativeTeacherInputLayerState();
}

class _NativeTeacherInputLayerState extends State<_NativeTeacherInputLayer> {
  int? _lastColorValue;
  double? _lastWidth;
  Size? _lastRenderSize;
  Size? _lastContentSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncNativeBrushAndMetrics();
    });
  }

  @override
  void didUpdateWidget(covariant _NativeTeacherInputLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.renderSize != widget.renderSize ||
        oldWidget.contentSize != widget.contentSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncNativeBrushAndMetrics();
      });
    }
  }

  Future<void> _syncNativeBrushAndMetrics({
    int? colorValue,
    double? width,
  }) async {
    final provider = context.read<DrawingProvider>();
    final contentSize = widget.contentSize ?? widget.renderSize;
    final resolvedColorValue = colorValue ?? provider.currentColor.toARGB32();
    final resolvedWidth = width ?? provider.currentWidth;
    final shouldUpdateBrush =
        _lastColorValue != resolvedColorValue || _lastWidth != resolvedWidth;
    final shouldUpdateMetrics =
        _lastRenderSize != widget.renderSize || _lastContentSize != contentSize;

    try {
      if (shouldUpdateBrush) {
        await NativeDrawingBridge.setBrush(
          BrushConfig(
            tool: 'pen',
            color: resolvedColorValue,
            size: resolvedWidth,
            eraserSize: 24,
          ),
        );
        _lastColorValue = resolvedColorValue;
        _lastWidth = resolvedWidth;
      }
      if (shouldUpdateMetrics) {
        await NativeDrawingBridge.setDrawingMetrics(
          renderWidth: widget.renderSize.width,
          renderHeight: widget.renderSize.height,
          pdfWidth: contentSize.width,
          pdfHeight: contentSize.height,
        );
        _lastRenderSize = widget.renderSize;
        _lastContentSize = contentSize;
      }
    } catch (e) {
      debugPrint('Failed to sync native drawing config: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final brush = context
        .select<DrawingProvider, ({int colorValue, double width})>(
          (provider) => (
            colorValue: provider.currentColor.toARGB32(),
            width: provider.currentWidth,
          ),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncNativeBrushAndMetrics(
        colorValue: brush.colorValue,
        width: brush.width,
      );
    });
    return IgnorePointer(
      ignoring: !widget.isDrawingEnabled,
      child: UiKitView(
        viewType: 'pentalk/drawing_view',
        creationParams: {
          'tool': 'pen',
          'color': brush.colorValue,
          'size': brush.width,
          'eraserSize': 24.0,
        },
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}

/// ===============================
/// 터치 입력 레이어
/// ===============================
class _TouchInputLayer extends StatefulWidget {
  final Size canvasSize;
  final Size? contentSize;
  final int? currentStrokeId;
  final List<DrawPoint> currentPoints;
  final TransformationController transformationController;
  final Function(Offset, CoordinateScaler, DrawingProvider) onPointerStart;
  final Function(Offset, CoordinateScaler, DrawingProvider) onPointerMove;
  final Function(CoordinateScaler, DrawingProvider) onPointerEnd;

  const _TouchInputLayer({
    required this.canvasSize,
    required this.contentSize,
    required this.currentStrokeId,
    required this.currentPoints,
    required this.transformationController,
    required this.onPointerStart,
    required this.onPointerMove,
    required this.onPointerEnd,
  });

  @override
  State<_TouchInputLayer> createState() => _TouchInputLayerState();
}

class _TouchInputLayerState extends State<_TouchInputLayer> {
  final Set<int> _activePointers = <int>{};
  bool _gestureBlocked = false;
  int? _drawingPointer;

  void _handlePointerDown(PointerDownEvent event, CoordinateScaler scaler) {
    _activePointers.add(event.pointer);
    if (_activePointers.length > 1) {
      _gestureBlocked = true;
      if (widget.currentStrokeId != null) {
        final provider = context.read<DrawingProvider>();
        widget.onPointerEnd(scaler, provider);
      }
      _drawingPointer = null;
      return;
    }

    if (_gestureBlocked || _drawingPointer != null) {
      return;
    }

    _drawingPointer = event.pointer;
    final provider = context.read<DrawingProvider>();
    widget.onPointerStart(event.localPosition, scaler, provider);
  }

  void _handlePointerUp(PointerEvent event) {
    if (_drawingPointer == event.pointer && widget.currentStrokeId != null) {
      final scaler = CoordinateScaler(
        canvasSize: widget.canvasSize,
        contentSize: widget.contentSize,
        fit: BoxFit.contain,
      );
      final provider = context.read<DrawingProvider>();
      widget.onPointerEnd(scaler, provider);
    }

    _activePointers.remove(event.pointer);
    if (_drawingPointer == event.pointer) {
      _drawingPointer = null;
    }
    if (_activePointers.length <= 1) {
      _gestureBlocked = false;
    }
  }

  void _handlePointerMove(PointerMoveEvent event, CoordinateScaler scaler) {
    if (_gestureBlocked || _drawingPointer != event.pointer) return;
    if (_activePointers.length != 1 || widget.currentStrokeId == null) return;
    final provider = context.read<DrawingProvider>();
    widget.onPointerMove(event.localPosition, scaler, provider);
  }

  @override
  Widget build(BuildContext context) {
    final scaler = CoordinateScaler(
      canvasSize: widget.canvasSize,
      contentSize: widget.contentSize,
      fit: BoxFit.contain,
    );

    return Positioned.fill(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) => _handlePointerDown(event, scaler),
        onPointerMove: (event) => _handlePointerMove(event, scaler),
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerUp,
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
          const Icon(Icons.zoom_in, color: Colors.white, size: 16),
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
  final Size? contentSize;
  final double scale;

  const _PersonalDrawingLayer({
    required this.canvasSize,
    required this.contentSize,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<
      PersonalDrawingProvider,
      ({bool show, List<Stroke> strokes})
    >(
      selector: (context, provider) => (
        show: provider.showPersonalLayer,
        strokes: provider.allPersonalStrokes,
      ),
      shouldRebuild: (previous, next) =>
          previous.show != next.show ||
          !listEquals(previous.strokes, next.strokes),
      builder: (context, data, child) {
        if (!data.show) {
          return const SizedBox.shrink();
        }

        final scaler = CoordinateScaler(
          canvasSize: canvasSize,
          contentSize: contentSize,
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
}

/// ===============================
/// 개인 필기 터치 입력 레이어 (학생용)
/// ===============================
class _PersonalTouchInputLayer extends StatefulWidget {
  final Size canvasSize;
  final Size? contentSize;
  final int? currentStrokeId;
  final List<DrawPoint> currentPoints;
  final TransformationController transformationController;
  final Function(
    Offset,
    CoordinateScaler,
    PersonalDrawingProvider,
    Color,
    double,
  )
  onPointerStart;
  final Function(Offset, CoordinateScaler, PersonalDrawingProvider)
  onPointerMove;
  final Function(CoordinateScaler, PersonalDrawingProvider) onPointerEnd;

  const _PersonalTouchInputLayer({
    required this.canvasSize,
    required this.contentSize,
    required this.currentStrokeId,
    required this.currentPoints,
    required this.transformationController,
    required this.onPointerStart,
    required this.onPointerMove,
    required this.onPointerEnd,
  });

  @override
  State<_PersonalTouchInputLayer> createState() =>
      _PersonalTouchInputLayerState();
}

class _PersonalTouchInputLayerState extends State<_PersonalTouchInputLayer> {
  final Set<int> _activePointers = <int>{};
  bool _gestureBlocked = false;
  int? _drawingPointer;

  void _handlePointerDown(PointerDownEvent event, CoordinateScaler scaler) {
    _activePointers.add(event.pointer);
    if (_activePointers.length > 1) {
      _gestureBlocked = true;
      if (widget.currentStrokeId != null) {
        final provider = context.read<PersonalDrawingProvider>();
        widget.onPointerEnd(scaler, provider);
      }
      _drawingPointer = null;
      return;
    }

    if (_gestureBlocked || _drawingPointer != null) {
      return;
    }

    _drawingPointer = event.pointer;
    final personalProvider = context.read<PersonalDrawingProvider>();
    final drawingProvider = context.read<DrawingProvider>();
    widget.onPointerStart(
      event.localPosition,
      scaler,
      personalProvider,
      drawingProvider.currentColor,
      drawingProvider.currentWidth,
    );
  }

  void _handlePointerUp(PointerEvent event) {
    if (_drawingPointer == event.pointer && widget.currentStrokeId != null) {
      final scaler = CoordinateScaler(
        canvasSize: widget.canvasSize,
        contentSize: widget.contentSize,
        fit: BoxFit.contain,
      );
      final provider = context.read<PersonalDrawingProvider>();
      widget.onPointerEnd(scaler, provider);
    }

    _activePointers.remove(event.pointer);
    if (_drawingPointer == event.pointer) {
      _drawingPointer = null;
    }
    if (_activePointers.length <= 1) {
      _gestureBlocked = false;
    }
  }

  void _handlePointerMove(PointerMoveEvent event, CoordinateScaler scaler) {
    if (_gestureBlocked || _drawingPointer != event.pointer) return;
    if (_activePointers.length != 1 || widget.currentStrokeId == null) return;
    final provider = context.read<PersonalDrawingProvider>();
    widget.onPointerMove(event.localPosition, scaler, provider);
  }

  @override
  Widget build(BuildContext context) {
    final scaler = CoordinateScaler(
      canvasSize: widget.canvasSize,
      contentSize: widget.contentSize,
      fit: BoxFit.contain,
    );

    return Positioned.fill(
      child: Consumer<PersonalDrawingProvider>(
        builder: (context, personalProvider, child) {
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) => _handlePointerDown(event, scaler),
            onPointerMove: (event) => _handlePointerMove(event, scaler),
            onPointerUp: _handlePointerUp,
            onPointerCancel: _handlePointerUp,
            child: Container(color: Colors.transparent),
          );
        },
      ),
    );
  }
}
