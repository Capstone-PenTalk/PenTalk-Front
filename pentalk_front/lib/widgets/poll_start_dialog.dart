import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ===============================
/// 교사용 이해도 체크 시작 다이얼로그
/// ===============================
class PollStartDialog extends StatefulWidget {
  final Function({
  required String question,
  required List<Map<String, dynamic>> options,
  int? duration,
  }) onStart;

  const PollStartDialog({Key? key, required this.onStart}) : super(key: key);

  static Future<void> show(
      BuildContext context, {
        required Function({
        required String question,
        required List<Map<String, dynamic>> options,
        int? duration,
        }) onStart,
      }) {
    return showDialog(
      context: context,
      builder: (context) => PollStartDialog(onStart: onStart),
    );
  }

  @override
  State<PollStartDialog> createState() => _PollStartDialogState();
}

class _PollStartDialogState extends State<PollStartDialog> {
  final _questionController = TextEditingController();
  final _durationController = TextEditingController();

  // 선택지: 최소 2개, 최대 4개
  final List<TextEditingController> _optionControllers = [
    TextEditingController(text: '이해했어요'),
    TextEditingController(text: '잘 모르겠어요'),
  ];

  bool _hasDuration = false;

  @override
  void dispose() {
    _questionController.dispose();
    _durationController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= 4) return;
    setState(() {
      _optionControllers.add(TextEditingController());
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    setState(() {
      _optionControllers[index].dispose();
      _optionControllers.removeAt(index);
    });
  }

  void _handleStart() {
    final question = _questionController.text.trim();
    if (question.isEmpty) {
      _showError('질문을 입력해주세요');
      return;
    }

    final options = <Map<String, dynamic>>[];
    for (int i = 0; i < _optionControllers.length; i++) {
      final text = _optionControllers[i].text.trim();
      if (text.isEmpty) {
        _showError('선택지 ${i + 1}을 입력해주세요');
        return;
      }
      options.add({'id': i + 1, 'text': text});
    }

    int? duration;
    if (_hasDuration) {
      final d = int.tryParse(_durationController.text.trim());
      if (d == null || d <= 0) {
        _showError('올바른 시간을 입력해주세요');
        return;
      }
      duration = d;
    }

    Navigator.pop(context);

    widget.onStart(
      question: question,
      options: options,
      duration: duration,
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.poll_outlined, color: Colors.blue),
          SizedBox(width: 8),
          Text('이해도 체크 시작'),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 질문 입력
            TextField(
              controller: _questionController,
              decoration: InputDecoration(
                labelText: '질문',
                hintText: '예: 이 내용 이해됐나요?',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // 선택지
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '선택지 (${_optionControllers.length}/4)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_optionControllers.length < 4)
                  TextButton.icon(
                    onPressed: _addOption,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('추가'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            ...List.generate(_optionControllers.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _optionControllers[i],
                        decoration: InputDecoration(
                          labelText: '선택지 ${i + 1}',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    if (_optionControllers.length > 2)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Colors.red),
                        onPressed: () => _removeOption(i),
                      ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 8),

            // 타이머 설정
            Row(
              children: [
                Switch(
                  value: _hasDuration,
                  onChanged: (v) => setState(() => _hasDuration = v),
                ),
                const Text('타이머 설정'),
              ],
            ),
            if (_hasDuration) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _durationController,
                decoration: InputDecoration(
                  labelText: '시간 (초)',
                  hintText: '예: 30',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixText: '초',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton.icon(
          onPressed: _handleStart,
          icon: const Icon(Icons.send, size: 16),
          label: const Text('시작'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}