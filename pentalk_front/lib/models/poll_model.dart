/// ===============================
/// 이해도 체크 (Poll) 모델
/// ===============================

/// 선택지
class PollOption {
  final dynamic id; // string | number (서버에서 둘 다 가능)
  final String text;

  const PollOption({required this.id, required this.text});

  factory PollOption.fromJson(Map<String, dynamic> json) {
    return PollOption(
      id: json['id'],
      text: json['text'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'text': text};
}

/// poll:start 수신 데이터
class PollStartData {
  final String pollId;
  final String question;
  final List<PollOption> options;
  final int? duration; // null이면 타이머 없음

  const PollStartData({
    required this.pollId,
    required this.question,
    required this.options,
    this.duration,
  });

  factory PollStartData.fromJson(Map<String, dynamic> json) {
    return PollStartData(
      pollId: json['pollId'] as String,
      question: json['question'] as String,
      options: (json['options'] as List<dynamic>)
          .map((o) => PollOption.fromJson(o as Map<String, dynamic>))
          .toList(),
      duration: json['duration'] as int?,
    );
  }
}

/// poll:result / poll:end 수신 데이터
class PollResultData {
  final String pollId;

  /// 서버에서 string 키로 내려옴 (JS/JSON 특성)
  /// ex) { "1": 15, "2": 3 }
  final Map<String, int> counts;
  final int total;

  const PollResultData({
    required this.pollId,
    required this.counts,
    required this.total,
  });

  factory PollResultData.fromJson(Map<String, dynamic> json) {
    final rawCounts = json['counts'] as Map<String, dynamic>;
    final counts = rawCounts.map(
          (key, value) => MapEntry(key, (value as num).toInt()),
    );

    return PollResultData(
      pollId: json['pollId'] as String,
      counts: counts,
      total: (json['total'] as num).toInt(),
    );
  }

  /// optionId 기준으로 카운트 반환
  /// optionId가 int든 string이든 string으로 변환해서 조회
  int countFor(dynamic optionId) {
    return counts[optionId.toString()] ?? 0;
  }

  /// 특정 optionId의 비율 (0.0 ~ 1.0)
  double ratioFor(dynamic optionId) {
    if (total == 0) return 0.0;
    return countFor(optionId) / total;
  }
}

/// Poll 전체 상태
enum PollStatus {
  idle,       // 진행 중인 poll 없음
  active,     // poll 진행 중
  answered,   // 학생이 응답 완료
  ended,      // poll 종료됨
}

class PollState {
  final PollStatus status;
  final PollStartData? pollData;
  final dynamic selectedOptionId;   // 학생이 선택한 optionId
  final PollResultData? resultData; // 실시간 집계 (교사용) / 최종 집계 (종료 시)
  final DateTime? startedAt;

  const PollState({
    required this.status,
    this.pollData,
    this.selectedOptionId,
    this.resultData,
    this.startedAt,
  });

  const PollState.idle()
      : status = PollStatus.idle,
        pollData = null,
        selectedOptionId = null,
        resultData = null,
        startedAt = null;

  bool get isActive => status == PollStatus.active;
  bool get isAnswered => status == PollStatus.answered;
  bool get isEnded => status == PollStatus.ended;
  bool get hasDuration => pollData?.duration != null;
}