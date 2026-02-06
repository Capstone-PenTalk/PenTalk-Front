
class StudentSessionModel {
  final String id;
  final String title;
  final String teacherName;
  final String subject;
  final DateTime joinedAt;
  final List<MaterialModel> materials;

  StudentSessionModel({
    required this.id,
    required this.title,
    required this.teacherName,
    required this.subject,
    required this.joinedAt,
    this.materials = const [],
  });

  factory StudentSessionModel.fromJson(Map<String, dynamic> json) {
    return StudentSessionModel(
      id: json['id'] as String,
      title: json['title'] as String,
      teacherName: json['teacherName'] as String,
      subject: json['subject'] as String,
      joinedAt: DateTime.parse(json['joinedAt'] as String),
      materials: (json['materials'] as List<dynamic>?)
          ?.map((material) => MaterialModel.fromJson(material as Map<String, dynamic>))
          .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'teacherName': teacherName,
      'subject': subject,
      'joinedAt': joinedAt.toIso8601String(),
      'materials': materials.map((material) => material.toJson()).toList(),
    };
  }

  StudentSessionModel copyWith({
    String? id,
    String? title,
    String? teacherName,
    String? subject,
    DateTime? joinedAt,
    List<MaterialModel>? materials,
  }) {
    return StudentSessionModel(
      id: id ?? this.id,
      title: title ?? this.title,
      teacherName: teacherName ?? this.teacherName,
      subject: subject ?? this.subject,
      joinedAt: joinedAt ?? this.joinedAt,
      materials: materials ?? this.materials,
    );
  }
}

class MaterialModel {
  final String id;
  final String title;
  final String fileName;
  final String url;
  final int sizeInBytes;
  final DateTime uploadedAt;
  final String? description;
  final FileMaterialType type;

  MaterialModel({
    required this.id,
    required this.title,
    required this.fileName,
    required this.url,
    required this.sizeInBytes,
    required this.uploadedAt,
    this.description,
    required this.type,
  });

  factory MaterialModel.fromJson(Map<String, dynamic> json) {
    return MaterialModel(
      id: json['id'] as String,
      title: json['title'] as String,
      fileName: json['fileName'] as String,
      url: json['url'] as String,
      sizeInBytes: json['sizeInBytes'] as int,
      uploadedAt: DateTime.parse(json['uploadedAt'] as String),
      description: json['description'] as String?,
      type: FileMaterialType.fromString(json['type'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'fileName': fileName,
      'url': url,
      'sizeInBytes': sizeInBytes,
      'uploadedAt': uploadedAt.toIso8601String(),
      'description': description,
      'type': type.toString(),
    };
  }

  String get formattedSize {
    if (sizeInBytes < 1024) {
      return '$sizeInBytes B';
    } else if (sizeInBytes < 1024 * 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}

enum FileMaterialType {
  pdf,
  image,
  video,
  document,
  other;

  static FileMaterialType fromString(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return FileMaterialType.pdf;
      case 'image':
      case 'jpg':
      case 'jpeg':
      case 'png':
        return FileMaterialType.image;
      case 'video':
      case 'mp4':
        return FileMaterialType.video;
      case 'doc':
      case 'docx':
      case 'document':
        return FileMaterialType.document;
      default:
        return FileMaterialType.other;
    }
  }

  String get extension {
    switch (this) {
      case FileMaterialType.pdf:
        return 'pdf';
      case FileMaterialType.image:
        return 'jpg';
      case FileMaterialType.video:
        return 'mp4';
      case FileMaterialType.document:
        return 'docx';
      case FileMaterialType.other:
        return 'file';
    }
  }
}

// 과목 enum
enum Subject {
  math('수학'),
  english('영어'),
  science('과학'),
  social('사회'),
  korean('국어'),
  other('기타');

  final String displayName;
  const Subject(this.displayName);

  static Subject fromString(String value) {
    return Subject.values.firstWhere(
          (subject) => subject.displayName == value || subject.name == value,
      orElse: () => Subject.other,
    );
  }
}