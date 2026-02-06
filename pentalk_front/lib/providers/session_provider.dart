
import 'package:flutter/foundation.dart';
import '../models/session_model.dart';

class SessionProvider extends ChangeNotifier {
  List<SessionModel> _sessions = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<SessionModel> get sessions => _sessions;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // 세션 목록 불러오기 (서버 연동 시 수정 필요)
  Future<void> loadSessions() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // TODO: 실제 API 호출로 대체
      await Future.delayed(const Duration(seconds: 1));

      // 임시 더미 데이터
      _sessions = [
        SessionModel(
          id: '1',
          title: '1-2',
          maxParticipants: 30,
          password: '1234',
          createdAt: DateTime.now().subtract(const Duration(days: 2)),
          files: [
            FileModel(
              id: 'f1',
              name: '2024-03-05_방정식.pdf',
              url: 'https://example.com/file1.pdf',
              sizeInBytes: 1024 * 500,
              uploadedAt: DateTime.now().subtract(const Duration(days: 2)),
              type: SessionFileType.pdf,
            ),
          ],
        ),
        SessionModel(
          id: '2',
          title: '1-3',
          maxParticipants: 28,
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ];

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = '세션을 불러오는 중 오류가 발생했습니다: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  // 세션 생성
  Future<void> createSession({
    required String title,
    required int maxParticipants,
    String? password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // TODO: 실제 API 호출로 대체
      await Future.delayed(const Duration(seconds: 1));

      final newSession = SessionModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        maxParticipants: maxParticipants,
        password: password,
        createdAt: DateTime.now(),
      );

      _sessions.add(newSession);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = '세션 생성 중 오류가 발생했습니다: $e';
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  // 세션 삭제
  Future<void> deleteSession(String sessionId) async {
    try {
      // TODO: 실제 API 호출로 대체
      await Future.delayed(const Duration(milliseconds: 500));

      _sessions.removeWhere((session) => session.id == sessionId);
      notifyListeners();
    } catch (e) {
      _errorMessage = '세션 삭제 중 오류가 발생했습니다: $e';
      notifyListeners();
      rethrow;
    }
  }

  // 특정 세션 찾기
  SessionModel? getSessionById(String sessionId) {
    try {
      return _sessions.firstWhere((session) => session.id == sessionId);
    } catch (e) {
      return null;
    }
  }

  // 세션에 파일 추가
  Future<void> addFileToSession(String sessionId, FileModel file) async {
    try {
      // TODO: 실제 API 호출로 대체
      await Future.delayed(const Duration(milliseconds: 500));

      final sessionIndex = _sessions.indexWhere((s) => s.id == sessionId);
      if (sessionIndex != -1) {
        final updatedFiles = List<FileModel>.from(_sessions[sessionIndex].files)..add(file);
        _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(files: updatedFiles);
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = '파일 추가 중 오류가 발생했습니다: $e';
      notifyListeners();
      rethrow;
    }
  }

  // 세션에서 파일 삭제
  Future<void> deleteFileFromSession(String sessionId, String fileId) async {
    try {
      // TODO: 실제 API 호출로 대체
      await Future.delayed(const Duration(milliseconds: 500));

      final sessionIndex = _sessions.indexWhere((s) => s.id == sessionId);
      if (sessionIndex != -1) {
        final updatedFiles = _sessions[sessionIndex].files.where((f) => f.id != fileId).toList();
        _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(files: updatedFiles);
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = '파일 삭제 중 오류가 발생했습니다: $e';
      notifyListeners();
      rethrow;
    }
  }

  // 에러 메시지 초기화
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}