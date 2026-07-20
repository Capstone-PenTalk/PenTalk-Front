import 'package:flutter/foundation.dart';
import '../models/question_model.dart';

/// ===============================
/// 질문하기(Q&A) Provider — 교사 전용 수신함
/// ===============================
class QuestionProvider extends ChangeNotifier {
  final List<QuestionModel> _questions = [];

  List<QuestionModel> get questions => List.unmodifiable(_questions);
  int get unreadCount => _questions.length;

  void addQuestion(QuestionModel question) {
    if (_questions.any((q) => q.id == question.id)) return;
    _questions.insert(0, question);
    notifyListeners();
  }

  void setQuestions(List<QuestionModel> questions) {
    _questions
      ..clear()
      ..addAll(questions);
    notifyListeners();
  }

  void dismiss(String id) {
    _questions.removeWhere((q) => q.id == id);
    notifyListeners();
  }

  void clear() {
    _questions.clear();
    notifyListeners();
  }
}
