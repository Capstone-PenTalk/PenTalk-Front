
import 'package:flutter/foundation.dart';
import '../models/student_session_model.dart';
import '../services/session_storage.dart';

class StudentSessionProvider extends ChangeNotifier {
  static const String _fallbackClassId = String.fromEnvironment(
    'PENTALK_DEMO_CLASS_ID',
    defaultValue: 'seed-class-01',
  );

  List<StudentSessionModel> _sessions = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<StudentSessionModel> get sessions => _sessions;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // 과목별로 세션 그룹화
  Map<String, List<StudentSessionModel>> get sessionsBySubject {
    final Map<String, List<StudentSessionModel>> grouped = {};
    for (var session in _sessions) {
      if (!grouped.containsKey(session.subject)) {
        grouped[session.subject] = [];
      }
      grouped[session.subject]!.add(session);
    }
    return grouped;
  }

  // 참여한 과목 리스트
  List<String> get subjects {
    return _sessions.map((s) => s.subject).toSet().toList()..sort();
  }

  // 내가 참여한 세션 목록 불러오기
  Future<void> loadMySessions() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final lastSession = await SessionStorage.getLastSession();

      if (lastSession != null) {
        _sessions = [
          StudentSessionModel(
            id: lastSession.roomId,
            title: '실시간 수업',
            classId: _fallbackClassId,
            teacherName: 'teacher1',
            subject: '공유 세션',
            joinedAt: lastSession.joinedAt ?? DateTime.now(),
          ),
        ];
      } else {
        _sessions = [];
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = '세션을 불러오는 중 오류가 발생했습니다: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  // 특정 세션 찾기
  StudentSessionModel? getSessionById(String sessionId) {
    try {
      return _sessions.firstWhere((session) => session.id == sessionId);
    } catch (e) {
      return null;
    }
  }

  // 특정 과목의 세션들 가져오기
  List<StudentSessionModel> getSessionsBySubject(String subject) {
    return _sessions.where((s) => s.subject == subject).toList();
  }

  // 에러 메시지 초기화
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
