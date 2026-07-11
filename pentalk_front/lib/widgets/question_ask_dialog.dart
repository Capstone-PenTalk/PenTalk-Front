import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// ===============================
/// 학생용 질문하기 작성 다이얼로그
/// 항상 익명으로 전송됨 (교사는 발신자를 알 수 없음)
/// ===============================
class QuestionAskDialog extends StatefulWidget {
  final void Function(String content) onSend;

  const QuestionAskDialog({Key? key, required this.onSend}) : super(key: key);

  static Future<void> show(
    BuildContext context, {
    required void Function(String content) onSend,
  }) {
    return showDialog(
      context: context,
      builder: (context) => QuestionAskDialog(onSend: onSend),
    );
  }

  @override
  State<QuestionAskDialog> createState() => _QuestionAskDialogState();
}

class _QuestionAskDialogState extends State<QuestionAskDialog> {
  static const int _maxLength = 500; // 서버 제한(content 최대 500자)에 맞춤
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSend() {
    final content = _controller.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('질문 내용을 입력해주세요')));
      return;
    }
    Navigator.pop(context);
    widget.onSend(content);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.chat_bubble_outline, color: AppColors.primary),
          SizedBox(width: 8),
          Text('질문하기'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '익명으로 전송돼요. 선생님은 누가 보냈는지 알 수 없어요.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 5,
            minLines: 2,
            maxLength: _maxLength,
            decoration: InputDecoration(
              hintText: '예: 방금 설명하신 부분 다시 알려주실 수 있나요?',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: _handleSend,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('전송'),
        ),
      ],
    );
  }
}
