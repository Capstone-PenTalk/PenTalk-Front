import 'package:flutter/material.dart';
import '../models/drawing_models.dart';
import '../utils/coordinate_scaler.dart';

/// ===============================
/// 판서를 실제로 그리는 CustomPainter
/// 최적화: shouldRepaint를 통해 필요할 때만 다시 그리기
/// CoordinateScaler 사용으로 정확한 좌표 변환
/// scale: 줌 레벨 (펜 굵기 보정용)
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
    // 모든 선 그리기
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }
  }

  /// 개별 선 그리기
  void _drawStroke(Canvas canvas, Stroke stroke) {
    final points = stroke.displayPoints;

    if (points.isEmpty) return;

    // 줌 레벨에 따라 펜 굵기 보정
    // scale이 2.0이면 펜 굵기를 0.5배로 줄여서 실제로는 같은 굵기로 보이게
    final adjustedWidth = stroke.width / scale;

    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = adjustedWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    // 점이 1개만 있으면 점으로 표시
    if (points.length == 1) {
      final offset = scaler.normalizedToPixel(points[0]);
      canvas.drawCircle(offset, adjustedWidth / 2, paint);
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
    final firstPoint = scaler.normalizedToPixel(points[0]);
    path.moveTo(firstPoint.dx, firstPoint.dy);

    if (points.length == 2) {
      // 두 점이면 직선
      final secondPoint = scaler.normalizedToPixel(points[1]);
      path.lineTo(secondPoint.dx, secondPoint.dy);
      return path;
    }

    // 세 점 이상: Quadratic Bezier로 부드러운 곡선 생성
    for (int i = 0; i < points.length - 1; i++) {
      final current = scaler.normalizedToPixel(points[i]);
      final next = scaler.normalizedToPixel(points[i + 1]);

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
    final lastPoint = scaler.normalizedToPixel(points.last);
    path.lineTo(lastPoint.dx, lastPoint.dy);

    return path;
  }

  @override
  bool shouldRepaint(covariant DrawingPainter oldDelegate) {
    // 선의 개수나 내용이 변경된 경우에만 다시 그리기
    // 또는 scaler가 변경된 경우 (화면 회전 등)
    // 또는 줌 레벨이 변경된 경우
    return oldDelegate.strokes != strokes ||
        oldDelegate.scaler.canvasSize != scaler.canvasSize ||
        oldDelegate.scaler.contentSize != scaler.contentSize ||
        (oldDelegate.scale - scale).abs() > 0.01;
  }

  @override
  bool shouldRebuildSemantics(covariant DrawingPainter oldDelegate) => false;
}