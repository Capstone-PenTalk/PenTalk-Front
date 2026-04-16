import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/drawing_models.dart';
import '../services/api_service.dart';
import '../services/upload_queue_service.dart';

/// ===============================
/// 배치 업로드 Provider
/// 판서 데이터를 모아서 서버로 전송
/// ===============================
class BatchUploadProvider extends ChangeNotifier {
  // 배치 조건
  static const int batchSize = 50; // 50개 모이면 전송
  static const Duration batchInterval = Duration(seconds: 30); // 30초마다 전송
  static const int maxRetries = 3; // 최대 재시도 횟수

  // 현재 배치 (메모리)
  final List<Stroke> _pendingStrokes = [];
  Timer? _batchTimer;
  bool _isUploading = false;

  String? _sessionId;

  // 통계
  int _totalUploaded = 0;
  int _totalFailed = 0;

  int get pendingCount => _pendingStrokes.length;
  int get totalUploaded => _totalUploaded;
  int get totalFailed => _totalFailed;
  bool get isUploading => _isUploading;

  /// ===============================
  /// 세션 시작 (타이머 시작)
  /// ===============================
  void startSession(String sessionId) {
    _sessionId = sessionId;
    _startBatchTimer();
    _retryFailedBatches(); // 이전 실패한 것들 재시도
    debugPrint('🚀 Batch upload session started: $sessionId');
  }

  /// ===============================
  /// 세션 종료 (남은 거 전부 전송)
  /// ===============================
  Future<void> endSession() async {
    _stopBatchTimer();

    if (_pendingStrokes.isNotEmpty) {
      debugPrint('📤 Sending remaining ${_pendingStrokes.length} strokes...');
      await _sendBatch();
    }

    _sessionId = null;
    debugPrint('🛑 Batch upload session ended');
  }

  /// ===============================
  /// 선 추가 (교사 판서만!)
  /// ===============================
  void addStroke(Stroke stroke) {
    _pendingStrokes.add(stroke);
    debugPrint('➕ Added stroke (${_pendingStrokes.length}/$batchSize)');

    // 50개 모이면 즉시 전송
    if (_pendingStrokes.length >= batchSize) {
      debugPrint('📦 Batch size reached, sending...');
      _sendBatch();
    }

    notifyListeners();
  }

  /// ===============================
  /// 배치 타이머 시작
  /// ===============================
  void _startBatchTimer() {
    _batchTimer?.cancel();
    _batchTimer = Timer.periodic(batchInterval, (timer) {
      if (_pendingStrokes.isNotEmpty) {
        debugPrint('⏰ Timer triggered, sending ${_pendingStrokes.length} strokes...');
        _sendBatch();
      }
    });
  }

  /// ===============================
  /// 배치 타이머 중지
  /// ===============================
  void _stopBatchTimer() {
    _batchTimer?.cancel();
    _batchTimer = null;
  }

  /// ===============================
  /// 배치 전송
  /// ===============================
  Future<void> _sendBatch() async {
    if (_isUploading || _pendingStrokes.isEmpty || _sessionId == null) {
      return;
    }

    _isUploading = true;
    notifyListeners();

    // 전송할 데이터 복사
    final strokesToSend = List<Stroke>.from(_pendingStrokes);
    _pendingStrokes.clear();

    try {
      // API 호출
      final response = await ApiService.saveStrokes(
        sessionId: _sessionId!,
        strokes: strokesToSend,
      );

      if (response.success) {
        // 성공
        _totalUploaded += strokesToSend.length;
        debugPrint('✅ Uploaded ${strokesToSend.length} strokes');
      } else {
        // 실패 → Queue에 저장
        debugPrint('❌ Upload failed: ${response.message}');
        await _saveToQueue(strokesToSend);
        _totalFailed += strokesToSend.length;
      }
    } catch (e) {
      // 네트워크 에러 → Queue에 저장
      debugPrint('❌ Network error: $e');
      await _saveToQueue(strokesToSend);
      _totalFailed += strokesToSend.length;
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  /// ===============================
  /// Queue에 저장 (실패 시)
  /// ===============================
  Future<void> _saveToQueue(List<Stroke> strokes) async {
    if (_sessionId == null) return;

    await UploadQueueService.addToQueue(
      sessionId: _sessionId!,
      strokes: strokes,
    );

    debugPrint('💾 Saved to queue for retry');
  }

  /// ===============================
  /// Queue에서 재시도
  /// ===============================
  Future<void> _retryFailedBatches() async {
    try {
      final batches = await UploadQueueService.getPendingBatches();

      if (batches.isEmpty) {
        debugPrint('✅ No failed batches to retry');
        return;
      }

      debugPrint('🔄 Retrying ${batches.length} failed batches...');

      for (final batch in batches) {
        // 재시도 횟수 체크
        if (batch.retryCount >= maxRetries) {
          debugPrint('⚠️ Max retries exceeded for batch ${batch.id}, removing...');
          await UploadQueueService.removeFromQueue(batch.id);
          continue;
        }

        // 재시도
        try {
          final response = await ApiService.saveStrokes(
            sessionId: batch.sessionId,
            strokes: batch.strokes,
          );

          if (response.success) {
            // 성공 → Queue에서 삭제
            await UploadQueueService.removeFromQueue(batch.id);
            _totalUploaded += batch.strokes.length;
            debugPrint('✅ Retry successful for batch ${batch.id}');
          } else {
            // 실패 → 재시도 횟수 증가
            await UploadQueueService.incrementRetryCount(batch.id);
            debugPrint('❌ Retry failed for batch ${batch.id}: ${response.message}');
          }
        } catch (e) {
          // 네트워크 에러 → 재시도 횟수 증가
          await UploadQueueService.incrementRetryCount(batch.id);
          debugPrint('❌ Retry error for batch ${batch.id}: $e');
        }

        // 과부하 방지
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      debugPrint('❌ Failed to retry batches: $e');
    }
  }

  /// ===============================
  /// Queue 통계 가져오기
  /// ===============================
  Future<QueueStats> getQueueStats() async {
    return await UploadQueueService.getStats();
  }

  /// ===============================
  /// 수동 재시도
  /// ===============================
  Future<void> retryNow() async {
    debugPrint('🔄 Manual retry triggered');
    await _retryFailedBatches();
  }

  /// ===============================
  /// 통계 초기화
  /// ===============================
  void resetStats() {
    _totalUploaded = 0;
    _totalFailed = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopBatchTimer();
    super.dispose();
  }
}