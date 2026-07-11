/// ===============================
/// 질문하기(Q&A) 모델
/// 학생 → 교사 단방향 질문. 교사는 답장 불가, 발신자 식별 불가(익명)
/// ===============================
class QuestionModel {
  final String id;
  final String content;
  final DateTime createdAt;

  const QuestionModel({
    required this.id,
    required this.content,
    required this.createdAt,
  });

  /// 서버 실제 페이로드: { questionId, content, askedBy, status, askedAt(epoch ms) }
  /// 발신자 식별 정보(askedBy)는 서버가 익명일 때 항상 null로 치환해 내려주므로
  /// 여기서도 의도적으로 파싱하지 않는다 (항상 익명).
  factory QuestionModel.fromJson(Map<String, dynamic> json) {
    final rawId = json['questionId'] ?? json['id'];
    final rawContent = json['content'] ?? json['question'] ?? json['text'];
    final rawAskedAt = json['askedAt'] ?? json['createdAt'] ?? json['timestamp'];

    DateTime parsedDate;
    if (rawAskedAt is int) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(rawAskedAt);
    } else if (rawAskedAt is String) {
      // epoch ms가 문자열로 오는 경우도 방어
      final asInt = int.tryParse(rawAskedAt);
      parsedDate = asInt != null
          ? DateTime.fromMillisecondsSinceEpoch(asInt)
          : (DateTime.tryParse(rawAskedAt) ?? DateTime.now());
    } else {
      parsedDate = DateTime.now();
    }

    return QuestionModel(
      id:
          rawId?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      content: rawContent?.toString() ?? '',
      createdAt: parsedDate,
    );
  }
}
