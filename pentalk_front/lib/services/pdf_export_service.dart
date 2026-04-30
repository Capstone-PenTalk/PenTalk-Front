import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import '../models/document_source.dart';
import '../models/student_session_model.dart';
import '../providers/personal_drawing_provider.dart';
import '../services/api_service.dart';

/// ===============================
/// PDF export 예외 (클라이언트 사이드)
/// ===============================
class PdfExportException implements Exception {
  final String message;
  final String code;

  const PdfExportException(this.message, {this.code = 'EXPORT_FAILED'});

  @override
  String toString() => message;
}

/// ===============================
/// PDF 내보내기 서비스
///
/// 흐름:
///   1. pageId → pageNumber 매핑 생성
///   2. 개인 필기 DB에서 전체 stroke 취합
///   3. stroke 수 / point 수 유효성 검사
///   4. POST /export/pdf 호출 → PDF 바이너리 수신
///   5. 저장용 결과 반환 (UI에서 save dialog 처리)
/// ===============================
class PdfExportService {
  // 서버 제한 (400 에러 방지용 사전 차단)
  static const int _maxStrokes = 3000;
  static const int _maxPoints = 50000;

  /// PDF 내보내기 메인 메서드
  ///
  /// [sessionId]: 현재 세션 ID
  /// [materials]: 세션의 자료 목록 (페이지 순서 기준)
  /// [personalProvider]: 개인 필기 provider
  ///
  /// 반환: export 결과 (UI에서 저장 다이얼로그에 전달)
  static Future<PdfSaveResult> export({
    required String sessionId,
    required List<MaterialModel> materials,
    required PersonalDrawingProvider personalProvider,
    DocumentSource? documentSource,
  }) async {
    debugPrint('PdfExportService.export() started');
    debugPrint('   sessionId: $sessionId');
    debugPrint('   materials: ${materials.length}개');

    final pageMapping = documentSource != null
        ? documentSource.createPageNumberMap()
        : <String, int>{
            for (int i = 0; i < materials.length; i++) materials[i].title: i + 1,
          };

    // 2. 개인 필기 전체 취합
    final strokes = await personalProvider.getAllPersonalStrokesForExport(
      pageMapping: pageMapping,
    );

    debugPrint('Total personal strokes for export: ${strokes.length}');
    for (final stroke in strokes) {
      debugPrint(
        '   export stroke sId=${stroke['sId']} '
        'page=${stroke['page']} '
        'points=${(stroke['points'] as List?)?.length ?? 0}',
      );
    }

    // 3. 서버 제한 사전 검사
    _validate(strokes);

    // 4. POST /export/pdf 호출
    final Uint8List pdfBytes = await ApiService.exportPdf(
      sessionId: sessionId,
      strokes: strokes,
    );

    final totalPoints = strokes.fold<int>(
      0,
          (sum, s) => sum + ((s['points'] as List?)?.length ?? 0),
    );

    debugPrint('PDF binary received');
    debugPrint('   strokes: ${strokes.length}, total points: $totalPoints');
    debugPrint('   size: ${pdfBytes.length} bytes');

    final saveResult = PdfSaveResult(
      fileName: _buildExportFileName(sessionId),
      bytes: pdfBytes,
      fileSizeBytes: pdfBytes.length,
      savedAt: DateTime.now(),
    );

    debugPrint('PdfExportService.export() complete');

    return saveResult;
  }

  /// ===============================
  /// 유효성 검사 (서버 호출 전 사전 차단)
  /// ===============================
  static void _validate(List<Map<String, dynamic>> strokes) {
    if (strokes.length > _maxStrokes) {
      throw PdfExportException(
        '필기 데이터가 너무 많습니다 (${strokes.length}개 / 최대 $_maxStrokes개).\n'
            '일부 필기를 삭제한 후 다시 시도해주세요.',
        code: 'STROKE_LIMIT_EXCEEDED',
      );
    }

    final totalPoints = strokes.fold<int>(
      0,
          (sum, s) => sum + ((s['points'] as List?)?.length ?? 0),
    );

    if (totalPoints > _maxPoints) {
      throw PdfExportException(
        '필기 데이터의 좌표 수가 너무 많습니다 ($totalPoints개 / 최대 $_maxPoints개).',
        code: 'POINT_LIMIT_EXCEEDED',
      );
    }
  }

  static String _buildExportFileName(String sessionId) {
    final now = DateTime.now();
    final timestamp =
        '${now.year}${_pad(now.month)}${_pad(now.day)}_'
        '${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
    return 'pentalk_${sessionId}_$timestamp.pdf';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}

class PdfSaveResult {
  final String fileName;
  final Uint8List bytes;
  final int fileSizeBytes;
  final DateTime savedAt;

  PdfSaveResult({
    required this.fileName,
    required this.bytes,
    required this.fileSizeBytes,
    required this.savedAt,
  });

  String get formattedSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
