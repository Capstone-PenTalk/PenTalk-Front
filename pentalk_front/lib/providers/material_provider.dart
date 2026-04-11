import 'package:flutter/foundation.dart';
import '../models/student_session_model.dart';

/// ===============================
/// 자료 목록 Provider
/// 교사 업로드 + 학생 실시간 수신 공용
/// ===============================
class MaterialProvider extends ChangeNotifier {
  List<MaterialModel> _materials = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<MaterialModel> get materials => List.unmodifiable(_materials);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// ===============================
  /// 자료 목록 설정 (API 로드 후)
  /// ===============================
  void setMaterials(List<MaterialModel> materials) {
    _materials = materials;
    notifyListeners();
  }

  /// ===============================
  /// 자료 추가 (업로드 완료 or material:uploaded 수신)
  /// ===============================
  void addMaterial(MaterialModel material) {
    // 중복 방지
    final exists = _materials.any((m) => m.id == material.id);
    if (!exists) {
      _materials = [..._materials, material];
      notifyListeners();
      debugPrint('📎 Material added: ${material.title}');
    }
  }

  /// ===============================
  /// 자료 제거
  /// ===============================
  void removeMaterial(String materialId) {
    final before = _materials.length;
    _materials = _materials.where((m) => m.id != materialId).toList();
    if (_materials.length < before) notifyListeners();
  }

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setError(String? message) {
    _errorMessage = message;
    notifyListeners();
  }

  void clear() {
    _materials = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }
}