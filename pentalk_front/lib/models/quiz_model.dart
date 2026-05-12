/// ===============================
/// 복습 퀴즈 모델
/// OX 형식 / 세션당 최대 3문제
/// ===============================

/// 퀴즈 문항 (교사 등록 + 학생 수행 공용)
class QuizQuestion {
  final String id;
  final String question;

  /// 교사 응답에만 포함됨 ('O' 또는 'X')
  /// 학생용 GET 응답에는 null
  final String? answer;

  final int order; // 1·2·3

  final DateTime? createdAt;

  const QuizQuestion({
    required this.id,
    required this.question,
    this.answer,
    required this.order,
    this.createdAt,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    return QuizQuestion(
      id: json['id'] as String,
      question: json['question'] as String,
      answer: json['answer'] as String?,
      order: (json['order'] as num).toInt(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'question': question,
      if (answer != null) 'answer': answer,
      'order': order,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    };
  }

  QuizQuestion copyWith({
    String? id,
    String? question,
    String? answer,
    int? order,
    DateTime? createdAt,
  }) {
    return QuizQuestion(
      id: id ?? this.id,
      question: question ?? this.question,
      answer: answer ?? this.answer,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// 답안 제출 결과 (POST /quiz/submit 응답)
class QuizSubmitResult {
  final String questionId;
  final bool isCorrect;
  final String submittedAnswer;
  final String correctAnswer;

  const QuizSubmitResult({
    required this.questionId,
    required this.isCorrect,
    required this.submittedAnswer,
    required this.correctAnswer,
  });

  factory QuizSubmitResult.fromJson(Map<String, dynamic> json) {
    return QuizSubmitResult(
      questionId: json['questionId'] as String,
      isCorrect: json['isCorrect'] as bool,
      submittedAnswer: json['submittedAnswer'] as String,
      correctAnswer: json['correctAnswer'] as String,
    );
  }
}

/// 퀴즈 전체 상태
enum QuizStatus {
  idle,              // 초기 상태
  loading,           // 문항 불러오는 중
  ready,             // 문항 로드 완료, 답변 대기
  submitting,        // 제출 중
  passed,            // 통과 (60% 이상)
  failed,            // 미통과 (60% 미만)
  dailyLimitExceeded,// 하루 2회 초과 (429)
  noQuestions,       // 등록된 문항 없음
}

/// 하루 2회 초과 예외
class QuizDailyLimitException implements Exception {
  const QuizDailyLimitException();

  @override
  String toString() => '하루 최대 2회까지 응시할 수 있습니다';
}