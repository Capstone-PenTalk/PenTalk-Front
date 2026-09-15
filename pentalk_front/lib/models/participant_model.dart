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

  Participant mergeWith(Participant other) {
    return Participant(
      userId: other.userId.isNotEmpty ? other.userId : userId,
      role: other.role.isNotEmpty ? other.role : role,
      name: _preferNonEmpty(other.name, name),
      studentNumber: _preferNonEmpty(other.studentNumber, studentNumber),
    );
  }

  static String? _preferNonEmpty(String? preferred, String? fallback) {
    final trimmedPreferred = preferred?.trim();
    if (trimmedPreferred != null && trimmedPreferred.isNotEmpty) {
      return trimmedPreferred;
    }
    final trimmedFallback = fallback?.trim();
    if (trimmedFallback != null && trimmedFallback.isNotEmpty) {
      return trimmedFallback;
    }
    return null;
  }

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
    final profile = json['profile'] is Map
        ? Map<String, dynamic>.from(json['profile'] as Map)
        : const <String, dynamic>{};
    final classMember = json['classMember'] is Map
        ? Map<String, dynamic>.from(json['classMember'] as Map)
        : const <String, dynamic>{};
    return Participant(
      userId:
          (json['userId'] ?? user['userId'] ?? user['id'])?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      name:
          (json['name'] ??
                  json['displayName'] ??
                  json['fullName'] ??
                  user['name'] ??
                  user['displayName'] ??
                  profile['name'] ??
                  profile['displayName'])
              ?.toString(),
      studentNumber:
          (json['studentNumber'] ??
                  json['studentNo'] ??
                  json['studentId'] ??
                  user['studentNumber'] ??
                  user['studentNo'] ??
                  profile['studentNumber'] ??
                  profile['studentNo'] ??
                  classMember['studentNumber'] ??
                  classMember['studentNo'])
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
