import 'package:flutter/material.dart';
import 'dart:async';
import '../models/participant_model.dart';

/// ===============================
/// 참여자 목록 상태 관리 Provider
/// ===============================
class ParticipantsProvider extends ChangeNotifier {
  final _participantsController =
      StreamController<List<Participant>>.broadcast();
  Stream<List<Participant>> get participantsStream =>
      _participantsController.stream;

  List<Participant> _participants = [];
  List<Participant> get participants => List.unmodifiable(_participants);

  int get totalCount => _participants.length;
  int get teacherCount => _participants.where((p) => p.isTeacher).length;
  int get studentCount => _participants.where((p) => p.isStudent).length;

  /// 전체 참여자 목록 설정 (PRESENCE_STATE)
  void setParticipants(List<Participant> participants) {
    _participants = participants
        .map((participant) => _mergeExistingParticipant(participant))
        .toList();
    _participantsController.add(_participants);
    notifyListeners();
    debugPrint('👥 Participants updated: ${_participants.length} total');
  }

  /// 참여자 추가 (PRESENCE_JOIN)
  void addParticipant(Participant participant) {
    final existingIndex = _participants.indexWhere(
      (p) => p.userId == participant.userId && p.role == participant.role,
    );

    if (existingIndex == -1) {
      _participants.add(participant);
      _participantsController.add(_participants);
      notifyListeners();
      debugPrint(
        '✅ Participant joined: ${participant.displayName} (${participant.role})',
      );
    } else {
      final updated = _participants[existingIndex].mergeWith(participant);
      if (updated != _participants[existingIndex]) {
        _participants[existingIndex] = updated;
        _participantsController.add(_participants);
        notifyListeners();
        debugPrint(
          '✅ Participant updated: ${updated.displayName} (${updated.role})',
        );
      }
    }
  }

  /// 참여자 제거 (PRESENCE_LEAVE)
  void removeParticipant(String userId, String role) {
    final initialLength = _participants.length;

    _participants.removeWhere((p) => p.userId == userId && p.role == role);

    if (_participants.length < initialLength) {
      _participantsController.add(_participants);
      notifyListeners();
      debugPrint('❌ Participant left: $userId ($role)');
    }
  }

  /// 초기화
  void clear() {
    _participants.clear();
    _participantsController.add(_participants);
    notifyListeners();
  }

  Participant _mergeExistingParticipant(Participant participant) {
    final existingIndex = _participants.indexWhere(
      (p) => p.userId == participant.userId && p.role == participant.role,
    );
    if (existingIndex == -1) return participant;
    return _participants[existingIndex].mergeWith(participant);
  }

  @override
  void dispose() {
    _participantsController.close();
    super.dispose();
  }
}
