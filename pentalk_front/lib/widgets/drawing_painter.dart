// lib/widgets/drawing_painter.dart

import 'package:flutter/material.dart';
import '../models/drawing_models.dart';

/// ===============================
/// 판서를 실제로 그리는 CustomPainter
/// 최적화: shouldRepaint를 통해 필요할 때만 다시 그리기
/// ===============================
class DrawingPainter extends CustomPainter {
  final List<Stroke> strokes;
  final Size canvasSize;

  DrawingPainter({
    required this.strokes,
    required this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 모든 선 그리기
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }
  }

  /// 개별 선 그리기
  void _drawStroke(Canvas canvas, Stroke stroke) {
    final points = stroke.displayPoints;

    if (points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true; // 안티앨리어싱 활성화 (부드러운 선)

    // 점이 1개만 있으면 점으로 표시
    if (points.length == 1) {
      final offset = points[0].toPixelOffset(canvasSize);
      canvas.drawCircle(offset, stroke.width / 2, paint);
      return;
    }

    // 2개 이상의 점이면 Path로 연결
    final path = _createSmoothPath(points);
    canvas.drawPath(path, paint);
  }

  /// 부드러운 곡선 Path 생성 (Quadratic Bezier 사용)
  Path _createSmoothPath(List<DrawPoint> points) {
    final path = Path();

    if (points.isEmpty) return path;

    // 첫 점으로 이동
    final firstPoint = points[0].toPixelOffset(canvasSize);
    path.moveTo(firstPoint.dx, firstPoint.dy);

    if (points.length == 2) {
      // 두 점이면 직선
      final secondPoint = points[1].toPixelOffset(canvasSize);
      path.lineTo(secondPoint.dx, secondPoint.dy);
      return path;
    }

    // 세 점 이상: Quadratic Bezier로 부드러운 곡선 생성
    for (int i = 0; i < points.length - 1; i++) {
      final current = points[i].toPixelOffset(canvasSize);
      final next = points[i + 1].toPixelOffset(canvasSize);

      // 중점 계산 (제어점으로 사용)
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

    // 마지막 점까지 연결
    final lastPoint = points.last.toPixelOffset(canvasSize);
    path.lineTo(lastPoint.dx, lastPoint.dy);

    return path;
  }

  @override
  bool shouldRepaint(covariant DrawingPainter oldDelegate) {
    // 선의 개수나 내용이 변경된 경우에만 다시 그리기
    // 최적화: 리스트 참조 비교로 빠르게 체크
    return oldDelegate.strokes != strokes ||
        oldDelegate.canvasSize != canvasSize;
  }

  @override
  bool shouldRebuildSemantics(covariant DrawingPainter oldDelegate) => false;
}