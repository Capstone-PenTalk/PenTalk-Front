import 'package:flutter/material.dart';

/// ===============================
/// 펜 스타일 상수
/// ===============================
class PenStyleConstants {
  // 기본값 (서버와 동일)
  static const Color defaultColor = Color(0xFF000000);  // #000000
  static const double defaultWidth = 4.0;  // 보통 굵기
  static const double maxWidth = 50.0;

  // 색상 팔레트 (8가지)
  static const List<Color> colorPalette = [
    Color(0xFF000000),  // 검정
    Color(0xFFFF0000),  // 빨강
    Color(0xFF0000FF),  // 파랑
    Color(0xFF00FF00),  // 초록
    Color(0xFFFFA500),  // 주황
    Color(0xFF800080),  // 보라
    Color(0xFF8B4513),  // 갈색
    Color(0xFFFF1493),  // 핑크
  ];

  // 색상 이름 (디버깅/접근성용)
  static const List<String> colorNames = [
    '검정',
    '빨강',
    '파랑',
    '초록',
    '주황',
    '보라',
    '갈색',
    '핑크',
  ];

  // 굵기 프리셋 (4가지) - 명확한 차이
  static const List<double> widthPresets = [
    2.0,    // 가는
    4.0,    // 보통
    8.0,    // 두꺼운
    16.0,   // 매우 두꺼운
  ];

  // 굵기 이름
  static const List<String> widthNames = [
    '가는',
    '보통',
    '두꺼운',
    '매우 두꺼운',
  ];

  /// Color → Hex String (#RRGGBB)
  static String colorToHex(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
  }

  /// Hex String → Color
  static Color hexToColor(String hex) {
    final hexCode = hex.replaceAll('#', '');

    // #RGB → #RRGGBB 변환
    if (hexCode.length == 3) {
      final r = hexCode[0] * 2;
      final g = hexCode[1] * 2;
      final b = hexCode[2] * 2;
      return Color(int.parse('FF$r$g$b', radix: 16));
    }

    // #RRGGBB
    return Color(int.parse('FF$hexCode', radix: 16));
  }

  /// 굵기 검증 (0 < width ≤ 50)
  static double validateWidth(double width) {
    return width.clamp(0.1, maxWidth);
  }
}