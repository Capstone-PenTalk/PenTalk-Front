
import 'package:flutter/material.dart';
import '../models/drawing_models.dart';

/// ===============================
/// 좌표 스케일러
/// PDF/배경 이미지 영역 기준 좌표 변환
/// ===============================
class CoordinateScaler {
  final Size canvasSize; // 전체 캔버스 크기
  final Size? contentSize; // PDF/이미지의 실제 크기 (선택)
  final BoxFit fit; // 이미지 fit 방식

  // 계산된 콘텐츠 렌더링 영역
  late final Rect _contentRect;

  CoordinateScaler({
    required this.canvasSize,
    this.contentSize,
    this.fit = BoxFit.contain,
  }) {
    _contentRect = _calculateContentRect();
  }

  /// ===============================
  /// PDF/이미지가 실제로 렌더링되는 영역 계산
  /// ===============================
  Rect _calculateContentRect() {
    // 배경 이미지가 없으면 전체 화면 사용
    if (contentSize == null) {
      return Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height);
    }

    final imageAspect = contentSize!.width / contentSize!.height;
    final canvasAspect = canvasSize.width / canvasSize.height;

    double renderWidth;
    double renderHeight;
    double offsetX = 0;
    double offsetY = 0;

    switch (fit) {
      case BoxFit.contain:
      // 이미지가 캔버스에 완전히 들어가도록 (여백 생김)
        if (imageAspect > canvasAspect) {
          // 이미지가 더 넓음 → 가로 꽉 채움
          renderWidth = canvasSize.width;
          renderHeight = canvasSize.width / imageAspect;
          offsetY = (canvasSize.height - renderHeight) / 2;
        } else {
          // 이미지가 더 높음 → 세로 꽉 채움
          renderHeight = canvasSize.height;
          renderWidth = canvasSize.height * imageAspect;
          offsetX = (canvasSize.width - renderWidth) / 2;
        }
        break;

      case BoxFit.cover:
      // 이미지가 캔버스를 완전히 덮도록 (잘림)
        if (imageAspect > canvasAspect) {
          renderHeight = canvasSize.height;
          renderWidth = canvasSize.height * imageAspect;
          offsetX = (canvasSize.width - renderWidth) / 2;
        } else {
          renderWidth = canvasSize.width;
          renderHeight = canvasSize.width / imageAspect;
          offsetY = (canvasSize.height - renderHeight) / 2;
        }
        break;

      case BoxFit.fill:
      // 이미지를 캔버스에 맞춰 늘림 (비율 무시)
        renderWidth = canvasSize.width;
        renderHeight = canvasSize.height;
        break;

      default:
      // 기본: contain
        renderWidth = canvasSize.width;
        renderHeight = canvasSize.height;
    }

    return Rect.fromLTWH(offsetX, offsetY, renderWidth, renderHeight);
  }

  /// ===============================
  /// 정규화 좌표 (0.0~1.0) → 픽셀 좌표
  /// ===============================
  Offset normalizedToPixel(DrawPoint point) {
    return Offset(
      _contentRect.left + (point.x * _contentRect.width),
      _contentRect.top + (point.y * _contentRect.height),
    );
  }

  /// ===============================
  /// 픽셀 좌표 → 정규화 좌표 (0.0~1.0)
  /// ===============================
  DrawPoint pixelToNormalized(Offset pixel) {
    // 콘텐츠 영역 밖이면 clamp
    final relativeX = (pixel.dx - _contentRect.left) / _contentRect.width;
    final relativeY = (pixel.dy - _contentRect.top) / _contentRect.height;

    return DrawPoint(
      x: relativeX.clamp(0.0, 1.0),
      y: relativeY.clamp(0.0, 1.0),
    );
  }

  /// ===============================
  /// 터치가 콘텐츠 영역 안인지 확인
  /// ===============================
  bool isInContentArea(Offset pixel) {
    return _contentRect.contains(pixel);
  }

  /// ===============================
  /// 콘텐츠 렌더링 영역 정보
  /// ===============================
  Rect get contentRect => _contentRect;
  Size get contentRenderSize => _contentRect.size;

  /// ===============================
  /// 디버그 정보
  /// ===============================
  @override
  String toString() {
    return 'CoordinateScaler(\n'
        '  canvasSize: $canvasSize\n'
        '  contentSize: $contentSize\n'
        '  contentRect: $_contentRect\n'
        '  fit: $fit\n'
        ')';
  }
}