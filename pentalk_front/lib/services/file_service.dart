
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../models/session_model.dart';

class FileService {
  // 파일 선택 (교사가 강의 자료 업로드)
  Future<File?> pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx', 'ppt', 'pptx'],
      );

      if (result != null && result.files.single.path != null) {
        return File(result.files.single.path!);
      }
      return null;
    } catch (e) {
      throw Exception('파일 선택 실패: $e');
    }
  }

  // 여러 파일 선택
  Future<List<File>?> pickMultipleFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx', 'ppt', 'pptx'],
        allowMultiple: true,
      );

      if (result != null) {
        return result.paths
            .where((path) => path != null)
            .map((path) => File(path!))
            .toList();
      }
      return null;
    } catch (e) {
      throw Exception('파일 선택 실패: $e');
    }
  }

  // 파일 업로드 (서버로 전송)
  Future<FileModel> uploadFile(File file, String sessionId) async {
    try {
      // TODO: 실제 서버 업로드 로직으로 대체
      // 예시: AWS S3, Firebase Storage 등에 업로드
      await Future.delayed(const Duration(seconds: 2)); // 업로드 시뮬레이션

      final fileName = file.path.split('/').last;
      final fileSize = await file.length();
      final fileExtension = fileName.split('.').last.toLowerCase();

      // 임시 URL (실제로는 서버에서 받은 URL 사용)
      final fileUrl = 'https://example.com/files/$sessionId/$fileName';

      return FileModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: fileName,
        url: fileUrl,
        sizeInBytes: fileSize,
        uploadedAt: DateTime.now(),
        type: SessionFileType.fromString(fileExtension),
      );
    } catch (e) {
      throw Exception('파일 업로드 실패: $e');
    }
  }

  // 파일 다운로드
  Future<void> downloadFile(FileModel file) async {
    try {
      // TODO: 실제 다운로드 로직으로 대체
      // 예시: http 패키지로 파일 다운로드 후 저장
      await Future.delayed(const Duration(seconds: 1)); // 다운로드 시뮬레이션

      // 실제 구현 시:
      // 1. HTTP GET 요청으로 파일 데이터 받기
      // 2. 로컬 저장소에 저장 (Downloads 폴더 등)
      // 3. 사용자에게 알림

      print('파일 다운로드 완료: ${file.name}');
    } catch (e) {
      throw Exception('파일 다운로드 실패: $e');
    }
  }

  // 파일 삭제 (서버에서)
  Future<void> deleteFile(String fileId, String sessionId) async {
    try {
      // TODO: 실제 서버 삭제 API 호출
      await Future.delayed(const Duration(milliseconds: 500));

      print('파일 삭제 완료: $fileId');
    } catch (e) {
      throw Exception('파일 삭제 실패: $e');
    }
  }

  // 파일 타입 검증
  bool isValidFileType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    const validExtensions = ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx', 'ppt', 'pptx'];
    return validExtensions.contains(extension);
  }

  // 파일 크기 검증 (예: 최대 50MB)
  bool isValidFileSize(int sizeInBytes, {int maxSizeInMB = 50}) {
    final maxSizeInBytes = maxSizeInMB * 1024 * 1024;
    return sizeInBytes <= maxSizeInBytes;
  }
}