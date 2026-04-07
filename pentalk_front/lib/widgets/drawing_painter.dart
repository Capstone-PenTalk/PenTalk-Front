import 'package:flutter/material.dart';
import '../models/drawing_models.dart';
import '../utils/coordinate_scaler.dart';

/// ===============================
/// 판서를 실제로 그리는 CustomPainter
/// ===============================
class DrawingPainter extends CustomPainter {
  final List<Stroke> strokes;
  final CoordinateScaler scaler;
  final double scale;

  DrawingPainter({
    required this.strokes,
    required this.scaler,
    this.scale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }
  }

  void _drawStroke(Canvas canvas, Stroke stroke) {
    final points = stroke.displayPoints;
    if (points.isEmpty) return;

    // 필압(pressure) 데이터가 있으면 필압 기반 렌더링
    final hasPressure = points.any((p) => p.pressure != null);
    if (hasPressure) {
      _drawStrokeWithPressure(canvas, stroke, points);
      return;
    }

    // 줌 레벨에 따른 굵기 보정
    final adjustedWidth = (stroke.width / scale).clamp(
      stroke.width * 0.25,
      stroke.width * 2.0,
    );

    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = adjustedWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    if (points.length == 1) {
      final offset = scaler.normalizedToPixel(points[0]);
      canvas.drawCircle(offset, adjustedWidth / 2, paint);
      return;
    }

    final path = _createSmoothPath(points);
    canvas.drawPath(path, paint);
  }

  /// 필압 기반 선 그리기
  void _drawStrokeWithPressure(
      Canvas canvas,
      Stroke stroke,
      List<DrawPoint> points,
      ) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      // scaler.normalizedToPixel() 사용 (coordinate_scaler와 일관성)
      final offset = scaler.normalizedToPixel(point);
      final pressure = point.pressure ?? 1.0;
      final width = (stroke.width * pressure) / scale;

      if (i == 0) {
        paint.strokeWidth = width;
        canvas.drawCircle(offset, width / 2, paint);
        continue;
      }

      final prev = scaler.normalizedToPixel(points[i - 1]);
      final prevPressure = points[i - 1].pressure ?? 1.0;
      paint.strokeWidth =
          (stroke.width * (pressure + prevPressure)) / 2 / scale;
      canvas.drawLine(prev, offset, paint);
    }
  }

  /// 부드러운 곡선 Path 생성 (Quadratic Bezier)
  Path _createSmoothPath(List<DrawPoint> points) {
    final path = Path();
    if (points.isEmpty) return path;

    final firstPoint = scaler.normalizedToPixel(points[0]);
    path.moveTo(firstPoint.dx, firstPoint.dy);

    if (points.length == 2) {
      final secondPoint = scaler.normalizedToPixel(points[1]);
      path.lineTo(secondPoint.dx, secondPoint.dy);
      return path;
    }

    for (int i = 0; i < points.length - 1; i++) {
      final current = scaler.normalizedToPixel(points[i]);
      final next = scaler.normalizedToPixel(points[i + 1]);

      final controlPoint = current;
      final endPoint = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );

      path.quadraticBezierTo(
        controlPoint.dx,
        controlPoint.dy,
        endPoint.dx,
        endPoint.dy,
      );
    }

    final lastPoint = scaler.normalizedToPixel(points.last);
    path.lineTo(lastPoint.dx, lastPoint.dy);

    return path;
  }

  @override
  bool shouldRepaint(covariant DrawingPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.scaler.canvasSize != scaler.canvasSize ||
        oldDelegate.scaler.contentSize != scaler.contentSize ||
        (oldDelegate.scale - scale).abs() > 0.01;
  }

  @override
  bool shouldRebuildSemantics(covariant DrawingPainter oldDelegate) => false;
}