import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/quiz_model.dart';
import '../providers/quiz_provider.dart';

/// ===============================
/// 학생용 복습 퀴즈 화면
/// session:ended 이후 표시
/// 60% 이상 통과 시 PDF 다운로드 활성화
/// ===============================
class QuizScreen extends StatefulWidget {
  final String sessionId;

  /// 통과 시 호출 → PDF 다운로드 트리거
  final VoidCallback onPassed;

  /// 퀴즈 없이 닫을 때 (noQuestions 등)
  final VoidCallback onClose;

  const QuizScreen({
    Key? key,
    required this.sessionId,
    required this.onPassed,
    required this.onClose,
  }) : super(key: key);

  /// 전체 화면 모달로 표시
  static Future<void> show(
      BuildContext context, {
        required String sessionId,
        required VoidCallback onPassed,
        required VoidCallback onClose,
      }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ChangeNotifierProvider(
          create: (_) => QuizProvider(),
          child: QuizScreen(
            sessionId: sessionId,
            onPassed: onPassed,
            onClose: onClose,
          ),
        ),
      ),
    );
  }

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<QuizProvider>().loadQuestionsForStudent(widget.sessionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // 뒤로가기 비활성화 (퀴즈 중간 이탈 방지)
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: SafeArea(
          child: Consumer<QuizProvider>(
            builder: (context, provider, _) {
              return switch (provider.status) {
                QuizStatus.idle || QuizStatus.loading => const _LoadingView(),
                QuizStatus.error => _ErrorView(
                  message: provider.errorMessage ?? '퀴즈를 불러오지 못했습니다',
                  onRetry: () => provider.loadQuestionsForStudent(widget.sessionId),
                  onClose: widget.onClose,
                ),
                QuizStatus.noQuestions => _NoQuestionsView(onClose: widget.onClose),
                QuizStatus.ready => _QuizFormView(
                  provider: provider,
                  onSubmit: () => provider.submitAll(widget.sessionId),
                ),
                QuizStatus.submitting => const _LoadingView(
                  message: '채점 중...',
                ),
                QuizStatus.passed => _ResultView(
                  provider: provider,
                  passed: true,
                  onPdfDownload: () {
                    Navigator.pop(context);
                    widget.onPassed();
                  },
                  onClose: () {
                    Navigator.pop(context);
                    widget.onClose();
                  },
                ),
                QuizStatus.failed => _ResultView(
                  provider: provider,
                  passed: false,
                  onRetry: () => provider.resetForRetry(),
                  onClose: () {
                    Navigator.pop(context);
                    widget.onClose();
                  },
                ),
                QuizStatus.dailyLimitExceeded => _DailyLimitView(
                  message: provider.errorMessage ?? '오늘 응시 횟수를 모두 사용했습니다.',
                  onClose: () {
                    Navigator.pop(context);
                    widget.onClose();
                  },
                ),
              };
            },
          ),
        ),
      ),
    );
  }
}

// ── 로딩 뷰 ─────────────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  final String message;

  const _LoadingView({this.message = '퀴즈를 불러오는 중...'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(message, style: const TextStyle(fontSize: 16, color: Colors.grey)),
        ],
      ),
    );
  }
}

// ── 문항 없음 뷰 ──────────────────────────────────────────────
class _NoQuestionsView extends StatelessWidget {
  final VoidCallback onClose;

  const _NoQuestionsView({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.quiz_outlined, size: 72, color: Colors.grey[400]),
            const SizedBox(height: 20),
            Text(
              '등록된 퀴즈가 없습니다',
              style: TextStyle(fontSize: 20, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              '교사가 퀴즈를 등록하지 않았습니다.\nPDF를 바로 다운로드할 수 있습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: onClose,
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 퀴즈 폼 뷰 ───────────────────────────────────────────────
class _QuizFormView extends StatelessWidget {
  final QuizProvider provider;
  final VoidCallback onSubmit;

  const _QuizFormView({required this.provider, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final questions = provider.questions;

    return Column(
      children: [
        // 헤더
        _QuizHeader(totalCount: questions.length),

        // 문항 목록
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                for (int i = 0; i < questions.length; i++) ...[
                  _QuestionCard(
                    index: i,
                    question: questions[i],
                    selectedAnswer: provider.studentAnswers[questions[i].id],
                    onAnswerSelected: (answer) =>
                        provider.setAnswer(questions[i].id, answer),
                  ),
                  if (i < questions.length - 1) const SizedBox(height: 16),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),

        // 제출 버튼
        _SubmitBar(
          answeredCount: provider.studentAnswers.length,
          totalCount: questions.length,
          canSubmit: provider.allAnswered,
          onSubmit: onSubmit,
        ),
      ],
    );
  }
}

// ── 퀴즈 헤더 ────────────────────────────────────────────────
class _QuizHeader extends StatelessWidget {
  final int totalCount;

  const _QuizHeader({required this.totalCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '복습 퀴즈',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'PDF를 받으려면 퀴즈를 통과하세요',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '$totalCount문제 중 ${(totalCount * 0.6).ceil()}문제 이상 맞히면 통과!',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

// ── 문항 카드 ─────────────────────────────────────────────────
class _QuestionCard extends StatelessWidget {
  final int index;
  final QuizQuestion question;
  final String? selectedAnswer;
  final ValueChanged<String> onAnswerSelected;

  const _QuestionCard({
    required this.index,
    required this.question,
    required this.selectedAnswer,
    required this.onAnswerSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 문항 번호 + 텍스트
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.blue[600],
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    question.question,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // O / X 버튼
            Row(
              children: [
                Expanded(
                  child: _OxButton(
                    label: 'O',
                    isSelected: selectedAnswer == 'O',
                    color: Colors.green,
                    onTap: () => onAnswerSelected('O'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _OxButton(
                    label: 'X',
                    isSelected: selectedAnswer == 'X',
                    color: Colors.red,
                    onTap: () => onAnswerSelected('X'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── OX 버튼 ──────────────────────────────────────────────────
class _OxButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _OxButton({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 56,
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
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: isSelected ? color : Colors.grey[400],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 제출 바 ──────────────────────────────────────────────────
class _SubmitBar extends StatelessWidget {
  final int answeredCount;
  final int totalCount;
  final bool canSubmit;
  final VoidCallback onSubmit;

  const _SubmitBar({
    required this.answeredCount,
    required this.totalCount,
    required this.canSubmit,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!canSubmit)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '$answeredCount / $totalCount 문제 답변 완료',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ),
            ElevatedButton(
              onPressed: canSubmit ? onSubmit : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[200],
              ),
              child: Text(
                canSubmit ? '제출하기' : '모든 문제에 답해주세요',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 결과 뷰 (통과/미통과) ────────────────────────────────────
class _ResultView extends StatelessWidget {
  final QuizProvider provider;
  final bool passed;
  final VoidCallback? onPdfDownload; // 통과 시
  final VoidCallback? onRetry; // 미통과 시
  final VoidCallback onClose;

  const _ResultView({
    required this.provider,
    required this.passed,
    this.onPdfDownload,
    this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final questions = provider.questions;
    final results = provider.results;

    return Column(
      children: [
        // 결과 배너
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: passed ? Colors.green[600] : Colors.orange[600],
          ),
          child: Column(
            children: [
              Icon(
                passed ? Icons.celebration : Icons.refresh,
                color: Colors.white,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                passed ? '통과!' : '아쉽지만 미통과',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${provider.correctCount} / ${provider.totalCount} 정답',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
              if (!passed)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '통과 기준: ${(provider.totalCount * 0.6).ceil()}문제 이상',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // 문항별 결과 목록
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                for (int i = 0; i < questions.length; i++) ...[
                  _ResultCard(
                    index: i,
                    question: questions[i],
                    result: results[questions[i].id],
                  ),
                  if (i < questions.length - 1) const SizedBox(height: 12),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),

        // 하단 버튼
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (passed)
                  ElevatedButton.icon(
                    onPressed: onPdfDownload,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text(
                      'PDF 다운로드',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                else ...[
                  ElevatedButton(
                    onPressed: onRetry,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '다시 도전',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onClose,
                    child: Text(
                      '나중에 하기',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── 문항별 결과 카드 ─────────────────────────────────────────
class _ResultCard extends StatelessWidget {
  final int index;
  final QuizQuestion question;
  final QuizSubmitResult? result;

  const _ResultCard({
    required this.index,
    required this.question,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final isCorrect = result?.isCorrect ?? false;
    final color = isCorrect ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 정오 아이콘
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCorrect ? Icons.check : Icons.close,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Q${index + 1}. ${question.question}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                if (result != null)
                  Row(
                    children: [
                      _AnswerChip(
                        label: '내 답변',
                        value: result!.submittedAnswer,
                        isCorrect: isCorrect,
                      ),
                      const SizedBox(width: 8),
                      if (!isCorrect)
                        _AnswerChip(
                          label: '정답',
                          value: result!.correctAnswer,
                          isCorrect: true,
                          isAnswer: true,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerChip extends StatelessWidget {
  final String label;
  final String value;
  final bool isCorrect;
  final bool isAnswer;

  const _AnswerChip({
    required this.label,
    required this.value,
    required this.isCorrect,
    this.isAnswer = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isCorrect ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 12,
          color: color[700],
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── 에러 뷰 ─────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 20),
            const Text(
              '퀴즈를 불러오지 못했습니다',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onClose,
              child: Text('닫기', style: TextStyle(color: Colors.grey[600])),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 일일 제한 초과 뷰 ────────────────────────────────────────
class _DailyLimitView extends StatelessWidget {
  final String message;
  final VoidCallback onClose;

  const _DailyLimitView({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.orange[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.hourglass_empty,
                size: 40,
                color: Colors.orange[600],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '오늘 응시 횟수 초과',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey[600], height: 1.5),
            ),
            const SizedBox(height: 8),
            Text(
              '내일 자정 이후 다시 도전할 수 있습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: onClose,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
  }
}