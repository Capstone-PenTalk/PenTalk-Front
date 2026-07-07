import 'package:flutter/material.dart';
import '../models/poll_model.dart';
import '../theme/app_colors.dart';

/// ===============================
/// 학생용 이해도 체크 오버레이
/// 캔버스 중앙에 모달 카드로 표시
/// ===============================
class PollOverlay extends StatelessWidget {
  final PollState pollState;
  final int remainingSeconds;
  final Function(dynamic optionId) onAnswer;
  final VoidCallback? onDismiss;

  const PollOverlay({
    Key? key,
    required this.pollState,
    required this.remainingSeconds,
    required this.onAnswer,
    this.onDismiss,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 24,
              spreadRadius: 2,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '이해도 check!',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (pollState.hasDuration && pollState.isActive) ...[
                    const SizedBox(width: 8),
                    _TimerBadge(seconds: remainingSeconds),
                  ],
                  if (pollState.isAnswered && onDismiss != null) ...[
                    const Spacer(),
                    GestureDetector(
                      onTap: onDismiss,
                      child: const Icon(
                        Icons.close,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                pollState.pollData!.question,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: pollState.pollData!.options.map((option) {
                  final isSelected = pollState.selectedOptionId == option.id;
                  final isAnswered = pollState.isAnswered;

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _OptionButton(
                        option: option,
                        isSelected: isSelected,
                        isDisabled: isAnswered,
                        onTap: isAnswered ? null : () => onAnswer(option.id),
                      ),
                    ),
                  );
                }).toList(),
              ),

              // 응답 완료 메시지
              if (pollState.isAnswered)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: AppColors.success,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '응답이 전송됐습니다',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.success,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final PollOption option;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback? onTap;

  const _OptionButton({
    required this.option,
    required this.isSelected,
    required this.isDisabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primaryLight
            : isDisabled
            ? Colors.grey[100]
            : AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.border,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Text(
            option.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isSelected
                  ? AppColors.primary
                  : isDisabled
                  ? Colors.grey[400]
                  : AppColors.textPrimary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimerBadge extends StatelessWidget {
  final int seconds;

  const _TimerBadge({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final isUrgent = seconds <= 5;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isUrgent ? AppColors.danger : AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer,
            color: isUrgent ? Colors.white : AppColors.primary,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            '${seconds}s',
            style: TextStyle(
              color: isUrgent ? Colors.white : AppColors.primary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}