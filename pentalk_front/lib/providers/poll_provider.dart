import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/poll_model.dart';

/// ===============================
/// 이해도 체크 Provider
/// 학생 / 교사 공용
/// ===============================
class PollProvider extends ChangeNotifier {
  PollState _state = const PollState.idle();
  PollState get state => _state;

  // duration 타이머
  Timer? _durationTimer;
  int _remainingSeconds = 0;
  int get remainingSeconds => _remainingSeconds;

  /// ===============================
  /// poll:start 수신 처리
  /// ===============================
  void onPollStart(PollStartData data) {
    debugPrint('📊 Poll started: ${data.pollId}');
    debugPrint('   question: ${data.question}');
    debugPrint('   options: ${data.options.length}개');
    debugPrint('   duration: ${data.duration ?? "없음"}');

    _cancelTimer();

    _state = PollState(
      status: PollStatus.active,
      pollData: data,
      startedAt: DateTime.now(),
    );

    // duration 있을 때만 타이머 시작
    if (data.duration != null) {
      _startTimer(data.duration!);
    }

    notifyListeners();
  }

  /// ===============================
  /// 학생: 선택지 선택 (한 번 고정)
  /// ===============================
  void selectOption(dynamic optionId) {
    if (_state.status != PollStatus.active) return;
    if (_state.selectedOptionId != null) return; // 이미 선택함

    debugPrint('✅ Poll option selected: $optionId');

    _state = PollState(
      status: PollStatus.answered,
      pollData: _state.pollData,
      selectedOptionId: optionId,
      resultData: _state.resultData,
      startedAt: _state.startedAt,
    );

    notifyListeners();
  }

  /// ===============================
  /// poll:result 수신 (교사 실시간 집계)
  /// ===============================
  void onPollResult(PollResultData data) {
    if (_state.pollData?.pollId != data.pollId) return;

    debugPrint('📊 Poll result updated: total=${data.total}');

    _state = PollState(
      status: _state.status,
      pollData: _state.pollData,
      selectedOptionId: _state.selectedOptionId,
      resultData: data,
      startedAt: _state.startedAt,
    );

    notifyListeners();
  }

  /// ===============================
  /// poll:end 수신 (종료 + 최종 집계)
  /// ===============================
  void onPollEnd(PollResultData data) {
    if (_state.pollData?.pollId != data.pollId) {
      debugPrint('⚠️ poll:end pollId 불일치, 무시');
      return;
    }

    debugPrint('🏁 Poll ended: ${data.pollId}, total=${data.total}');

    _cancelTimer();

    _state = PollState(
      status: PollStatus.ended,
      pollData: _state.pollData,
      selectedOptionId: _state.selectedOptionId,
      resultData: data,
      startedAt: _state.startedAt,
    );

    notifyListeners();
  }

  /// ===============================
  /// Poll 상태 초기화 (다음 poll 준비)
  /// ===============================
  void reset() {
    _cancelTimer();
    _state = const PollState.idle();
    _remainingSeconds = 0;
    notifyListeners();
    debugPrint('🔄 Poll state reset');
  }

  /// ===============================
  /// duration 타이머
  /// ===============================
  void _startTimer(int seconds) {
    _remainingSeconds = seconds;

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 0) {
        _cancelTimer();
        return;
      }
      _remainingSeconds--;
      notifyListeners();
    });

    debugPrint('⏱️ Poll timer started: ${seconds}s');
  }

  void _cancelTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }
}