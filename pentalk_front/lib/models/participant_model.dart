/// ===============================
/// Participant 모델
/// ===============================
class Participant {
  final String userId;
  final String role;
  final String? name;
  final String? studentNumber;

  Participant({
    required this.userId,
    required this.role,
    this.name,
    this.studentNumber,
  });

  bool get isTeacher => role == 'teacher';
  bool get isStudent => role == 'student';

  String get displayName {
    final trimmedName = name?.trim() ?? '';
    final trimmedStudentNumber = studentNumber?.trim() ?? '';

    if (isStudent) {
      if (trimmedStudentNumber.isNotEmpty && trimmedName.isNotEmpty) {
        return '$trimmedStudentNumber $trimmedName';
      }
      if (trimmedStudentNumber.isNotEmpty) return trimmedStudentNumber;
      if (trimmedName.isNotEmpty) return trimmedName;
    }

    if (isTeacher) {
      return trimmedName.isNotEmpty ? trimmedName : '교사';
    }

    return trimmedName.isNotEmpty ? trimmedName : userId;
  }

  factory Participant.fromJson(Map<String, dynamic> json) {
    final user = json['user'] is Map
        ? Map<String, dynamic>.from(json['user'] as Map)
        : const <String, dynamic>{};
    return Participant(
      userId:
          (json['userId'] ?? user['userId'] ?? user['id'])?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      name: (json['name'] ?? json['displayName'] ?? user['name'])?.toString(),
      studentNumber:
          (json['studentNumber'] ?? json['studentNo'] ?? user['studentNumber'])
              ?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'role': role,
      if (name != null) 'name': name,
      if (studentNumber != null) 'studentNumber': studentNumber,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Participant &&
        other.userId == userId &&
        other.role == role &&
        other.name == name &&
        other.studentNumber == studentNumber;
  }

  @override
  int get hashCode =>
      userId.hashCode ^ role.hashCode ^ name.hashCode ^ studentNumber.hashCode;
}
