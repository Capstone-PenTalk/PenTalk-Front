
import 'package:flutter/foundation.dart';
import '../models/student_session_model.dart';

class StudentSessionProvider extends ChangeNotifier {
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
      // TODO: 실제 API 호출로 대체
      await Future.delayed(const Duration(seconds: 1));

      // 임시 더미 데이터
      _sessions = [
        // 통합과학
        StudentSessionModel(
          id: 's1',
          title: '1-1',
          teacherName: '김선생님',
          subject: '통합과학',
          joinedAt: DateTime.now().subtract(const Duration(days: 30)),
          materials: [
            MaterialModel(
              id: 'm1',
              title: '1단원: 물질의 규칙성',
              fileName: '2024-03-05_물질의규칙성.pdf',
              url: 'https://example.com/file1.pdf',
              sizeInBytes: 1024 * 1024 * 2,
              uploadedAt: DateTime.now().subtract(const Duration(days: 5)),
              description: '원소와 주기율표에 대한 내용입니다.',
              type: FileMaterialType.pdf,
            ),
            MaterialModel(
              id: 'm2',
              title: '실험 보고서 양식',
              fileName: '실험보고서.docx',
              url: 'https://example.com/file2.docx',
              sizeInBytes: 1024 * 500,
              uploadedAt: DateTime.now().subtract(const Duration(days: 3)),
              type: FileMaterialType.document,
            ),
          ],
        ),
        StudentSessionModel(
          id: 's2',
          title: '1-2',
          teacherName: '김선생님',
          subject: '통합과학',
          joinedAt: DateTime.now().subtract(const Duration(days: 25)),
          materials: [
            MaterialModel(
              id: 'm3',
              title: '2단원: 자연의 구성 물질',
              fileName: '2024-03-12_자연의구성물질.pdf',
              url: 'https://example.com/file3.pdf',
              sizeInBytes: 1024 * 1024 * 3,
              uploadedAt: DateTime.now().subtract(const Duration(days: 2)),
              type: FileMaterialType.pdf,
            ),
          ],
        ),
        StudentSessionModel(
          id: 's3',
          title: '1-3',
          teacherName: '김선생님',
          subject: '통합과학',
          joinedAt: DateTime.now().subtract(const Duration(days: 20)),
        ),
        // 확률과 통계
        StudentSessionModel(
          id: 's4',
          title: '2-1',
          teacherName: '이선생님',
          subject: '확률과 통계',
          joinedAt: DateTime.now().subtract(const Duration(days: 28)),
          materials: [
            MaterialModel(
              id: 'm4',
              title: '경우의 수',
              fileName: '2024-03-10_경우의수.pdf',
              url: 'https://example.com/file4.pdf',
              sizeInBytes: 1024 * 1024,
              uploadedAt: DateTime.now().subtract(const Duration(days: 7)),
              description: '순열과 조합의 기초',
              type: FileMaterialType.pdf,
            ),
            MaterialModel(
              id: 'm5',
              title: '확률 연습문제',
              fileName: '확률_연습문제.pdf',
              url: 'https://example.com/file5.pdf',
              sizeInBytes: 1024 * 800,
              uploadedAt: DateTime.now().subtract(const Duration(days: 1)),
              type: FileMaterialType.pdf,
            ),
          ],
        ),
        StudentSessionModel(
          id: 's5',
          title: '2-2',
          teacherName: '이선생님',
          subject: '확률과 통계',
          joinedAt: DateTime.now().subtract(const Duration(days: 21)),
        ),
        StudentSessionModel(
          id: 's6',
          title: '2-3',
          teacherName: '이선생님',
          subject: '확률과 통계',
          joinedAt: DateTime.now().subtract(const Duration(days: 14)),
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