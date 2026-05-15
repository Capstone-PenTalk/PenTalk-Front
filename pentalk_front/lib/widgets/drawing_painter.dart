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

      // 꺾임 각도에 따라 tension 조절 (adaptive tension)
      final tension = _calcTension(p0, p1, p2);

      final cp1 = Offset(
        p0.dx + (p1.dx - p0.dx) * 0.5,
        p0.dy + (p1.dy - p0.dy) * 0.5,
      );
      final cp2 = Offset(
        p1.dx - (p2.dx - p0.dx) * tension,
        p1.dy - (p2.dy - p0.dy) * tension,
      );

      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p1.dx, p1.dy);
    }

    // 마지막 점 연결 (기존 누락 버그 수정)
    if (points.length >= 2) {
      final last = scaler.normalizedToPixel(points.last);
      path.lineTo(last.dx, last.dy);
    }

    return path;
  }

  // 꺾임 각도 기반 tension 계산
  double _calcTension(Offset p0, Offset p1, Offset p2) {
    final v1 = p1 - p0;
    final v2 = p2 - p1;
    final len1 = v1.distance;
    final len2 = v2.distance;
    if (len1 < 0.001 || len2 < 0.001) return 0.15;

    // cosAngle: 1=직선, 0=직각, -1=U턴
    final cosAngle = (v1.dx * v2.dx + v1.dy * v2.dy) / (len1 * len2);

    // 약 81° 이상 꺾임이면 tension 제거 → 날카로운 모서리 유지
    if (cosAngle < 0.15) return 0.0;
    return 0.15;
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