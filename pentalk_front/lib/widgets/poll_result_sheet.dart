import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models/poll_model.dart';
import '../theme/app_colors.dart';

/// ===============================
/// 교사용 실시간 집계 결과 패널
/// 판서 화면 좌측 고정 패널로 표시
/// ===============================
class PollResultSheet extends StatelessWidget {
  final PollState pollState;
  final int remainingSeconds;
  final VoidCallback onClose;

  const PollResultSheet({
    Key? key,
    required this.pollState,
    required this.remainingSeconds,
    required this.onClose,
  }) : super(key: key);

  static const List<Color> _segmentColors = [
    AppColors.primary,
    AppColors.accent,
    Color(0xFF9CA3AF),
  ];

  @override
  Widget build(BuildContext context) {
    final result = pollState.resultData;
    final options = pollState.pollData?.options ?? [];
    final total = result?.total ?? 0;
    final ratios = options
        .map((option) => result?.ratioFor(option.id) ?? 0.0)
        .toList();

    return Container(
      color: AppColors.surface,
      child: SafeArea(
        left: false,
        right: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '현재 이해도 체크',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (pollState.hasDuration && pollState.isActive)
                    _TimerChip(seconds: remainingSeconds),
                  if (pollState.isEnded)
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: onClose,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                pollState.pollData?.question ?? '',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),

              Center(
                child: SizedBox(
                  width: 110,
                  height: 110,
                  child: CustomPaint(
                    painter: DonutChartPainter(
                      ratios: ratios,
                      colors: _segmentColors,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$total명',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const Text(
                            '응답',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              if (options.isNotEmpty)
                Column(
                  children: List.generate(options.length, (i) {
                    final option = options[i];
                    final count = result?.countFor(option.id) ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _LegendRow(
                        color: _segmentColors[i % _segmentColors.length],
                        text: option.text,
                        count: count,
                      ),
                    );
                  }),
                ),

              const SizedBox(height: 8),
              if (pollState.isActive)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onClose,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text(
                      '이해도체크 종료',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String text;
  final int count;

  const _LegendRow({
    required this.color,
    required this.text,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '$count명',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _TimerChip extends StatelessWidget {
  final int seconds;

  const _TimerChip({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final isUrgent = seconds <= 5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isUrgent ? AppColors.danger : AppColors.primaryLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${seconds}s',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isUrgent ? Colors.white : AppColors.primary,
        ),
      ),
    );
  }
}

/// ===============================
/// 도넛차트 페인터 (외부 패키지 없이 CustomPaint로 구현)
/// ===============================
class DonutChartPainter extends CustomPainter {
  final List<double> ratios;
  final List<Color> colors;
  final double strokeWidth;

  DonutChartPainter({
    required this.ratios,
    required this.colors,
    this.strokeWidth = 14,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = Colors.grey.shade200
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    double start = -math.pi / 2;
    for (var i = 0; i < ratios.length; i++) {
      final sweep = ratios[i] * 2 * math.pi;
      if (sweep <= 0) continue;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = colors[i % colors.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant DonutChartPainter oldDelegate) =>
      oldDelegate.ratios != ratios || oldDelegate.colors != colors;
}
