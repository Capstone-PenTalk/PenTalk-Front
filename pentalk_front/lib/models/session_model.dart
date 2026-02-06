
class SessionModel {
  final String id;
  final String title;
  final int maxParticipants;
  final String? password;
  final DateTime createdAt;
  final List<FileModel> files;

  SessionModel({
    required this.id,
    required this.title,
    required this.maxParticipants,
    this.password,
    required this.createdAt,
    this.files = const [],
  });

  factory SessionModel.fromJson(Map<String, dynamic> json) {
    return SessionModel(
      id: json['id'] as String,
      title: json['title'] as String,
      maxParticipants: json['maxParticipants'] as int,
      password: json['password'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      files: (json['files'] as List<dynamic>?)
          ?.map((file) => FileModel.fromJson(file as Map<String, dynamic>))
          .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'maxParticipants': maxParticipants,
      'password': password,
      'createdAt': createdAt.toIso8601String(),
      'files': files.map((file) => file.toJson()).toList(),
    };
  }

  SessionModel copyWith({
    String? id,
    String? title,
    int? maxParticipants,
    String? password,
    DateTime? createdAt,
    List<FileModel>? files,
  }) {
    return SessionModel(
      id: id ?? this.id,
      title: title ?? this.title,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      password: password ?? this.password,
      createdAt: createdAt ?? this.createdAt,
      files: files ?? this.files,
    );
  }
}

class FileModel {
  final String id;
  final String name;
  final String url;
  final int sizeInBytes;
  final DateTime uploadedAt;
  final SessionFileType type;

  FileModel({
    required this.id,
    required this.name,
    required this.url,
    required this.sizeInBytes,
    required this.uploadedAt,
    required this.type,
  });

  factory FileModel.fromJson(Map<String, dynamic> json) {
    return FileModel(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      sizeInBytes: json['sizeInBytes'] as int,
      uploadedAt: DateTime.parse(json['uploadedAt'] as String),
      type: SessionFileType.fromString(json['type'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'sizeInBytes': sizeInBytes,
      'uploadedAt': uploadedAt.toIso8601String(),
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

enum SessionFileType {
  pdf,
  image,
  video,
  document,
  other;

  static SessionFileType fromString(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return SessionFileType.pdf;
      case 'image':
      case 'jpg':
      case 'jpeg':
      case 'png':
        return SessionFileType.image;
      case 'video':
      case 'mp4':
        return SessionFileType.video;
      case 'doc':
      case 'docx':
      case 'document':
        return SessionFileType.document;
      default:
        return SessionFileType.other;
    }
  }

  String get extension {
    switch (this) {
      case SessionFileType.pdf:
        return 'pdf';
      case SessionFileType.image:
        return 'jpg';
      case SessionFileType.video:
        return 'mp4';
      case SessionFileType.document:
        return 'docx';
      case SessionFileType.other:
        return 'file';
    }
  }
}
