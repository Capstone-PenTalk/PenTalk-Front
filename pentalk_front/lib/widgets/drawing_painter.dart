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

    // 👇 날아갔던 '진짜 선 그리기' 로직 복구!
    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = adjustedWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = _createSmoothPath(points);
    canvas.drawPath(path, paint);
  }

  Path _createSmoothPath(List<DrawPoint> points) {
    final path = Path();
    if (points.isEmpty) return path;

    final first = scaler.normalizedToPixel(points[0]);
    path.moveTo(first.dx, first.dy);

    for (int i = 0; i < points.length - 2; i++) {
      final p0 = scaler.normalizedToPixel(points[i]);
      final p1 = scaler.normalizedToPixel(points[i + 1]);
      final p2 = scaler.normalizedToPixel(points[i + 2]);

      final cp1 = Offset(
        p0.dx + (p1.dx - p0.dx) * 0.5,
        p0.dy + (p1.dy - p0.dy) * 0.5,
      );
      final cp2 = Offset(
        p1.dx - (p2.dx - p0.dx) * 0.15,
        p1.dy - (p2.dy - p0.dy) * 0.15,
      );

      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p1.dx, p1.dy);
    }

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

  // 👇 추가할 함수 시작
  void _drawStrokeWithPressure(Canvas canvas, Stroke stroke, List<DrawPoint> points) {
    if (points.isEmpty) return;

    // 기본 굵기 계산
    final baseWidth = (stroke.width / scale).clamp(1.0, 50.0);

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
// 👆 추가할 함수 끝
}