import 'package:flutter/material.dart';

/// ===============================
/// PenTalk 앱 컬러 팔레트
/// 인디고 포인트 + 아이보리 배경
/// ===============================
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF4F46E5); // 인디고
  static const Color primaryLight = Color(0xFFEEF2FF);
  static const Color accent = Color(0xFFF97316); // 오렌지
  static const Color accentLight = Color(0xFFFCEFE0);

  static const Color background = Color(0xFFFBF8EF); // 화면 배경 (아이보리)
  static const Color surface = Color(0xFFFFFDF6); // 카드/입력창 배경
  static const Color paper = Color(0xFFF3EEDD); // 판서 캔버스 종이

  static const Color border = Color(0xFFEFE8D6);

  static const Color textPrimary = Color(0xFF2B2A28);
  static const Color textSecondary = Color(0xFFA39C8C);

  static const Color success = Color(0xFF12A150);
  static const Color danger = Color(0xFFEF4444);
}
