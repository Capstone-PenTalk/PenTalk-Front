import 'package:flutter/material.dart';
import '../models/poll_model.dart';

/// ===============================
/// 교사용 실시간 집계 결과 시트
/// 화면 우측에 고정 표시
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

  @override
  Widget build(BuildContext context) {
    final result = pollState.resultData;
    final options = pollState.pollData?.options ?? [];
    final total = result?.total ?? 0;

    return Positioned(
      right: 16,
      top: 16,
      child: Container(
        width: 280,
        constraints: const BoxConstraints(maxHeight: 480),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 16,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: BoxDecoration(
                color: Colors.blue[600],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bar_chart, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '이해도 집계',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // 타이머
                  if (pollState.hasDuration && pollState.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: remainingSeconds <= 5
                            ? Colors.red
                            : Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${remainingSeconds}s',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  // 종료 표시
                  if (pollState.isEnded)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '종료',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  // 닫기 버튼 (종료 시만)
                  if (pollState.isEnded)
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 18),
                      onPressed: onClose,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                ],
              ),
            ),

            // 질문
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                pollState.pollData?.question ?? '',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 응답자 수
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.people_outline,
                      size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    '응답 $total명',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 선택지별 막대 그래프
            if (options.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: options.map((option) {
                    final count = result?.countFor(option.id) ?? 0;
                    final ratio = result?.ratioFor(option.id) ?? 0.0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ResultBar(
                        text: option.text,
                        count: count,
                        ratio: ratio,
                        total: total,
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResultBar extends StatelessWidget {
  final String text;
  final int count;
  final double ratio;
  final int total;

  const _ResultBar({
    required this.text,
    required this.count,
    required this.ratio,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (ratio * 100).toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count명 ($percent%)',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 10,
            backgroundColor: Colors.grey[100],
            valueColor: AlwaysStoppedAnimation<Color>(
              _barColor(ratio),
            ),
          ),
        ),
      ],
    );
  }

  Color _barColor(double ratio) {
    if (ratio >= 0.7) return Colors.green;
    if (ratio >= 0.4) return Colors.blue;
    return Colors.orange;
  }
}