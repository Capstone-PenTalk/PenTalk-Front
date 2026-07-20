import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/quiz_model.dart';
import '../providers/quiz_provider.dart';
import '../theme/app_colors.dart';

/// ===============================
/// 교사용 복습 퀴즈 관리 위젯
/// SessionDetailScreen 내에 삽입해서 사용
///
/// 사용 예:
///   QuizEditorWidget(sessionId: session.id)
/// ===============================
class QuizEditorWidget extends StatefulWidget {
  final String sessionId;

  const QuizEditorWidget({Key? key, required this.sessionId}) : super(key: key);

  @override
  State<QuizEditorWidget> createState() => _QuizEditorWidgetState();
}

class _QuizEditorWidgetState extends State<QuizEditorWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<QuizProvider>()
          .loadQuestionsForTeacher(widget.sessionId);
    });
  }

  void _showAddDialog() {
    _showQuestionDialog(
      title: '문항 추가',
      onSave: (question, answer) async {
        await context.read<QuizProvider>().addQuestion(
          widget.sessionId,
          question: question,
          answer: answer,
        );
      },
    );
  }

  void _showEditDialog(QuizQuestion existing) {
    _showQuestionDialog(
      title: '문항 수정',
      initialQuestion: existing.question,
      initialAnswer: existing.answer,
      onSave: (question, answer) async {
        await context.read<QuizProvider>().updateQuestion(
          widget.sessionId,
          existing.id,
          question: question,
          answer: answer,
        );
      },
    );
  }

  void _showQuestionDialog({
    required String title,
    String? initialQuestion,
    String? initialAnswer,
    required Future<void> Function(String question, String answer) onSave,
  }) {
    showDialog(
      context: context,
      builder: (_) => _QuestionEditDialog(
        title: title,
        initialQuestion: initialQuestion ?? '',
        initialAnswer: initialAnswer ?? 'O',
        onSave: (question, answer) async {
          try {
            await onSave(question, answer);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('저장됐습니다')),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('오류: $e'),
                  backgroundColor: AppColors.danger,
                ),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _confirmDelete(QuizQuestion q) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('문항 삭제'),
        content: Text('Q${q.order}. "${q.question}" 을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style:
            ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await context
            .read<QuizProvider>()
            .deleteQuestion(widget.sessionId, q.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('삭제됐습니다')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('삭제 실패: $e'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<QuizProvider>(
      builder: (context, provider, _) {
        final questions = provider.questions;
        final isLoading = provider.status == QuizStatus.loading;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 섹션 헤더
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.quiz_outlined,
                      size: 22, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Text(
                    '복습 퀴즈',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary),
                  ),
                  const Spacer(),
                  // 문항 수 뱃지
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: questions.length >= 3
                          ? Colors.grey[200]
                          : AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${questions.length} / 3',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: questions.length >= 3
                            ? Colors.grey[600]
                            : AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 추가 버튼
                  if (provider.canAddQuestion)
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      color: AppColors.primary,
                      tooltip: '문항 추가',
                      onPressed: _showAddDialog,
                    ),
                ],
              ),
            ),

            const Divider(height: 1),

            // 로딩
            if (isLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            // 문항 없음
            else if (questions.isEmpty)
              _EmptyQuizHint(onAdd: _showAddDialog)
            // 문항 목록
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: questions.length,
                separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (_, index) {
                  final q = questions[index];
                  return _QuestionTile(
                    question: q,
                    onEdit: () => _showEditDialog(q),
                    onDelete: () => _confirmDelete(q),
                  );
                },
              ),

            if (questions.isNotEmpty && provider.canAddQuestion)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: OutlinedButton.icon(
                  onPressed: _showAddDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('문항 추가'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── 빈 상태 힌트 ──────────────────────────────────────────────
class _EmptyQuizHint extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyQuizHint({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.quiz_outlined, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            '아직 등록된 문항이 없습니다',
            style: TextStyle(fontSize: 15, color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(
            '수업 종료 후 학생이 PDF를 받으려면\n퀴즈를 통과해야 합니다 (최대 3문항)',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('첫 문항 추가'),
          ),
        ],
      ),
    );
  }
}

// ── 문항 타일 ─────────────────────────────────────────────────
class _QuestionTile extends StatelessWidget {
  final QuizQuestion question;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _QuestionTile({
    required this.question,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final answer = question.answer ?? '?';
    final answerColor = answer == 'O' ? AppColors.success : AppColors.danger;

    return ListTile(
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: AppColors.primaryLight,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '${question.order}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
      title: Text(
        question.question,
        style: const TextStyle(fontSize: 15),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: answerColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: answerColor.withOpacity(0.4)),
              ),
              child: Text(
                '정답: $answer',
                style: TextStyle(
                  fontSize: 12,
                  color: answerColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: Colors.grey[600],
            onPressed: onEdit,
            tooltip: '수정',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: AppColors.danger,
            onPressed: onDelete,
            tooltip: '삭제',
          ),
        ],
      ),
    );
  }
}

// ── 문항 추가/수정 다이얼로그 ────────────────────────────────
class _QuestionEditDialog extends StatefulWidget {
  final String title;
  final String initialQuestion;
  final String initialAnswer;
  final Future<void> Function(String question, String answer) onSave;

  const _QuestionEditDialog({
    required this.title,
    required this.initialQuestion,
    required this.initialAnswer,
    required this.onSave,
  });

  @override
  State<_QuestionEditDialog> createState() => _QuestionEditDialogState();
}

class _QuestionEditDialogState extends State<_QuestionEditDialog> {
  late final TextEditingController _questionController;
  late String _selectedAnswer;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _questionController =
        TextEditingController(text: widget.initialQuestion);
    _selectedAnswer =
    (widget.initialAnswer == 'X') ? 'X' : 'O';
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('문항 내용을 입력해주세요')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await widget.onSave(question, _selectedAnswer);
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('저장 실패: $e'),
              backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        content: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 문항 입력
          TextField(
            controller: _questionController,
            decoration: InputDecoration(
              labelText: '문항 내용',
              hintText: '예: 광합성은 빛에너지를 이용해 포도당을 만든다.',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            maxLines: 3,
            minLines: 2,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 20),

          // 정답 선택
          const Text(
            '정답',
            style:
            TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _OxSelectButton(
                  label: 'O',
                  isSelected: _selectedAnswer == 'O',
                  color: AppColors.success,
                  onTap: () => setState(() => _selectedAnswer = 'O'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _OxSelectButton(
                  label: 'X',
                  isSelected: _selectedAnswer == 'X',
                  color: AppColors.danger,
                  onTap: () => setState(() => _selectedAnswer = 'X'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        )
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _handleSave,
          style: ElevatedButton.styleFrom(
            padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: _isSaving
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Text('저장'),
        ),
      ],
    );
  }
}

class _OxSelectButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _OxSelectButton({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 52,
      decoration: BoxDecoration(
        color: isSelected ? color.withOpacity(0.12) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? color : Colors.grey[300]!,
          width: isSelected ? 2.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isSelected ? color : Colors.grey[400],
            ),
          ),
        ),
      ),
    );
  }
}