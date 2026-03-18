/// ===============================
/// Participant 모델
/// ===============================
class Participant {
  final String userId;
  final String role;

  Participant({
    required this.userId,
    required this.role,
  });

  bool get isTeacher => role == 'teacher';
  bool get isStudent => role == 'student';

  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      userId: json['userId'] as String,
      role: json['role'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'role': role,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Participant &&
        other.userId == userId &&
        other.role == role;
  }

  @override
  int get hashCode => userId.hashCode ^ role.hashCode;
}