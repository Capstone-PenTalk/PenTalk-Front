import 'package:flutter/material.dart';

class SessionLinkProvider extends ChangeNotifier {
  String? _sessionUrl;
  bool _isLoading = false;
  String? _error;

  String? get sessionUrl => _sessionUrl;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadSessionLink() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // TODO: 나중에 서버 API 연결
      await Future.delayed(const Duration(seconds: 1));

      _sessionUrl = "https://pentalk.app/session/abc123";
    } catch (e) {
      _error = "링크를 불러오지 못했습니다.";
    }

    _isLoading = false;
    notifyListeners();
  }
}
