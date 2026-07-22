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
    final adjustedWidth = (stroke.width / scale).clamp(1.0, 50.0);

    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = adjustedWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (points.length == 1) {
      _drawStartDot(canvas, points.first, paint);
      return;
    }

    final path = _createSmoothPath(points);
    canvas.drawPath(path, paint);
  }

  Path _createSmoothPath(List<DrawPoint> points) {
    final path = Path();
    if (points.isEmpty) return path;

    final pixelPoints = points.map(scaler.normalizedToPixel).toList();
    final firstPoint = pixelPoints.first;
    path.moveTo(firstPoint.dx, firstPoint.dy);

    if (points.length == 2) {
      final secondPoint = pixelPoints[1];
      path.lineTo(secondPoint.dx, secondPoint.dy);
      return path;
    }

    for (int i = 0; i < pixelPoints.length - 1; i++) {
      final p0 = i == 0 ? pixelPoints[i] : pixelPoints[i - 1];
      final p1 = pixelPoints[i];
      final p2 = pixelPoints[i + 1];
      final p3 = i + 2 < pixelPoints.length ? pixelPoints[i + 2] : p2;

      final control1 = p1 + (p2 - p0) / 6;
      final control2 = p2 - (p3 - p1) / 6;

      path.cubicTo(
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        p2.dx,
        p2.dy,
      );
    }

    return path;
  }

  void _drawStartDot(Canvas canvas, DrawPoint point, Paint paint) {
    final center = scaler.normalizedToPixel(point);
    canvas.drawCircle(center, paint.strokeWidth / 2, paint);
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

  void _drawStrokeWithPressure(
    Canvas canvas,
    Stroke stroke,
    List<DrawPoint> points,
  ) {
    if (points.isEmpty) return;

    // 기본 굵기 계산
    final baseWidth = (stroke.width / scale).clamp(1.0, 50.0);

    if (points.length == 1) {
      final pressure = points.first.pressure ?? 0.5;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = baseWidth * (pressure * 2)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      _drawStartDot(canvas, points.first, paint);
      return;
    }

    for (int i = 0; i < points.length - 1; i++) {
      final p1 = scaler.normalizedToPixel(points[i]);
      final p2 = scaler.normalizedToPixel(points[i + 1]);

      // 필압이 없으면 기본값 0.5로 처리
      final pressure1 = points[i].pressure ?? 0.5;
      final pressure2 = points[i + 1].pressure ?? 0.5;

      // 두 점 사이의 평균 필압으로 선 굵기 조절
      final avgPressure = (pressure1 + pressure2) / 2;
      final currentWidth = baseWidth * (avgPressure * 2);

      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = currentWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      canvas.drawLine(p1, p2, paint);
    }
  }
}
