import 'package:flutter/material.dart';
import '../models/poll_model.dart';

/// ===============================
/// 학생용 이해도 체크 오버레이
/// 화면 하단에 표시
/// ===============================
class PollOverlay extends StatelessWidget {
  final PollState pollState;
  final int remainingSeconds;
  final Function(dynamic optionId) onAnswer;

  const PollOverlay({
    Key? key,
    required this.pollState,
    required this.remainingSeconds,
    required this.onAnswer,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 80, // FAB 위에 표시
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          constraints: const BoxConstraints(maxWidth: 520),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 헤더
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue[600],
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.poll, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '이해도 체크',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // 타이머 (duration 있을 때만)
                    if (pollState.hasDuration && pollState.isActive)
                      _TimerBadge(seconds: remainingSeconds),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 질문
                    Text(
                      pollState.pollData!.question,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 선택지 버튼들
                    ...pollState.pollData!.options.map((option) {
                      final isSelected =
                          pollState.selectedOptionId == option.id;
                      final isAnswered = pollState.isAnswered;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _OptionButton(
                          option: option,
                          isSelected: isSelected,
                          isDisabled: isAnswered,
                          onTap: isAnswered ? null : () => onAnswer(option.id),
                        ),
                      );
                    }),

                    // 응답 완료 메시지
                    if (pollState.isAnswered)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle,
                                color: Colors.green[600], size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '응답이 전송됐습니다',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.green[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
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
            ? Colors.blue[50]
            : isDisabled
            ? Colors.grey[50]
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? Colors.blue : Colors.grey[300]!,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option.text,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDisabled && !isSelected
                        ? Colors.grey[400]
                        : Colors.black87,
                    fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: Colors.blue[600], size: 20),
            ],
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
        color: isUrgent ? Colors.red : Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer,
            color: Colors.white,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            '${seconds}s',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}