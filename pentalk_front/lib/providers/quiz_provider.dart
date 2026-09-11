import 'package:flutter/foundation.dart';
import '../models/quiz_model.dart';
import '../services/api_service.dart';

/// ===============================
/// 복습 퀴즈 Provider
/// 학생 수행 + 교사 등록/관리 공용
/// ===============================
class QuizProvider extends ChangeNotifier {
  static const int requiredQuestionCount = 3;

  // ── 공통 상태 ────────────────────────────────────────────
  List<QuizQuestion> _questions = [];
  QuizStatus _status = QuizStatus.idle;
  String? _errorMessage;

  // ── 학생 전용 상태 ────────────────────────────────────────
  /// questionId → 'O' | 'X'
  final Map<String, String> _studentAnswers = {};

  /// questionId → 제출 결과
  final Map<String, QuizSubmitResult> _results = {};

  /// 다음 submitAll()이 재응시 시작인지 여부 (resetForRetry()에서 true로 설정)
  bool _isRetryAttempt = false;

  // ── Getters ───────────────────────────────────────────────
  List<QuizQuestion> get questions =>
      List.unmodifiable(_questions..sort((a, b) => a.order.compareTo(b.order)));

  QuizStatus get status => _status;
  String? get errorMessage => _errorMessage;

  Map<String, String> get studentAnswers => Map.unmodifiable(_studentAnswers);

  Map<String, QuizSubmitResult> get results => Map.unmodifiable(_results);

  /// 모든 문항에 답변 완료 여부
  bool get allAnswered =>
      _questions.isNotEmpty &&
      _questions.every((q) => _studentAnswers.containsKey(q.id));

  /// 정답 수
  int get correctCount => _results.values.where((r) => r.isCorrect).length;

  /// 전체 문항 수
  int get totalCount => _questions.length;

  /// 통과 여부 (60% 이상)
  bool get passed =>
      _questions.isNotEmpty && correctCount / _questions.length >= 0.6;

  /// 교사가 추가 가능한지 (정확히 3문항 필수)
  bool get canAddQuestion => _questions.length < requiredQuestionCount;
  bool get hasRequiredQuestionCount =>
      _questions.length == requiredQuestionCount;

  // ── 학생: 문항 로드 ──────────────────────────────────────
  Future<void> loadQuestionsForStudent(String sessionId) async {
    debugPrint('🎯 Quiz load: sessionId=$sessionId');
    _setStatus(QuizStatus.loading);

    try {
      final questions = await ApiService.getQuizQuestions(sessionId: sessionId);

      debugPrint('✅ Quiz loaded: ${questions.length}문제');

      if (questions.isEmpty) {
        _questions = [];
        _setStatus(QuizStatus.noQuestions);
        return;
      }

      _questions = questions;
      _setStatus(QuizStatus.ready);
    } catch (e) {
      debugPrint('❌ Quiz load error: $e');
      _errorMessage = '퀴즈를 불러오지 못했습니다\n$e';
      _setStatus(QuizStatus.error);
    }
  }

  // ── 학생: 답변 선택 ──────────────────────────────────────
  void setAnswer(String questionId, String answer) {
    assert(answer == 'O' || answer == 'X', 'OX 퀴즈 답변은 O 또는 X여야 합니다');
    _studentAnswers[questionId] = answer;
    notifyListeners();
  }

  // ── 학생: 전체 제출 ──────────────────────────────────────
  Future<void> submitAll(String sessionId) async {
    if (!allAnswered) return;

    _setStatus(QuizStatus.submitting);

    // 재응시 시작 여부는 이번 제출의 첫 문항에서만 표시하고 즉시 소비한다
    final isRetryAttempt = _isRetryAttempt;
    _isRetryAttempt = false;

    try {
      // 문항 순서대로 순차 제출
      for (int i = 0; i < _questions.length; i++) {
        final question = _questions[i];
        final answer = _studentAnswers[question.id]!;
        debugPrint(
          '📝 Submitting quiz answer: questionId=${question.id}, '
          'myAnswer=$answer, teacherAnswer(local)=${question.answer}, '
          'isRetryStart=${i == 0 && isRetryAttempt}',
        );
        final result = await ApiService.submitQuizAnswer(
          sessionId: sessionId,
          questionId: question.id,
          answer: answer,
          isRetryStart: i == 0 && isRetryAttempt,
        );
        debugPrint(
          '📩 Quiz submit result: questionId=${result.questionId}, '
          'isCorrect=${result.isCorrect}, submittedAnswer=${result.submittedAnswer}, '
          'correctAnswer=${result.correctAnswer}',
        );
        _results[question.id] = result;
      }

      _setStatus(passed ? QuizStatus.passed : QuizStatus.failed);
    } on QuizDailyLimitException {
      _errorMessage = '오늘 응시 횟수를 모두 사용했습니다.\n내일 다시 도전해주세요.';
      _setStatus(QuizStatus.dailyLimitExceeded);
    } catch (e) {
      _errorMessage = '제출 중 오류가 발생했습니다. 다시 시도해주세요.';
      _setStatus(QuizStatus.failed);
      debugPrint('QuizProvider.submitAll error: $e');
    }
  }

  // ── 학생: 재시도 준비 ────────────────────────────────────
  void resetForRetry() {
    _studentAnswers.clear();
    _results.clear();
    _errorMessage = null;
    _isRetryAttempt = true;
    _setStatus(QuizStatus.ready);
  }

  // ── 교사: 문항 로드 ──────────────────────────────────────
  Future<void> loadQuestionsForTeacher(String sessionId) async {
    _setStatus(QuizStatus.loading);

    try {
      final questions = await ApiService.getQuizQuestions(sessionId: sessionId);
      _questions = questions;
      _setStatus(QuizStatus.ready);
    } catch (e) {
      _errorMessage = '퀴즈를 불러오지 못했습니다';
      _setStatus(QuizStatus.idle);
      debugPrint('QuizProvider.loadQuestionsForTeacher error: $e');
    }
  }

  // ── 교사: 문항 추가 ──────────────────────────────────────
  Future<void> addQuestion(
    String sessionId, {
    required String question,
    required String answer,
  }) async {
    if (!canAddQuestion) throw Exception('복습퀴즈는 정확히 3문항만 등록할 수 있습니다');

    final nextOrder = _questions.isEmpty
        ? 1
        : (_questions.map((q) => q.order).reduce((a, b) => a > b ? a : b) + 1)
              .clamp(1, requiredQuestionCount);

    final newQuestion = await ApiService.addQuizQuestion(
      sessionId: sessionId,
      question: question,
      answer: answer,
      order: nextOrder,
    );

    _questions = [..._questions, newQuestion];
    notifyListeners();
  }

  // ── 교사: 문항 수정 ──────────────────────────────────────
  Future<void> updateQuestion(
    String sessionId,
    String questionId, {
    String? question,
    String? answer,
  }) async {
    final updated = await ApiService.updateQuizQuestion(
      sessionId: sessionId,
      questionId: questionId,
      question: question,
      answer: answer,
    );

    final index = _questions.indexWhere((q) => q.id == questionId);
    if (index != -1) {
      final list = List<QuizQuestion>.from(_questions);
      list[index] = updated;
      _questions = list;
      notifyListeners();
    }
  }

  // ── 교사: 문항 삭제 ──────────────────────────────────────
  Future<void> deleteQuestion(String sessionId, String questionId) async {
    await ApiService.deleteQuizQuestion(
      sessionId: sessionId,
      questionId: questionId,
    );

    _questions = _questions.where((q) => q.id != questionId).toList();
    notifyListeners();
  }

  // ── 초기화 ────────────────────────────────────────────────
  void clear() {
    _questions = [];
    _studentAnswers.clear();
    _results.clear();
    _status = QuizStatus.idle;
    _errorMessage = null;
    notifyListeners();
  }

  // ── 내부 헬퍼 ─────────────────────────────────────────────
  void _setStatus(QuizStatus status) {
    _status = status;
    notifyListeners();
  }
}
