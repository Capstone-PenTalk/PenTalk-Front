import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/student_session_model.dart';
import '../providers/personal_drawing_provider.dart';
import '../services/api_service.dart';
import '../services/pdf_file_service.dart';

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
///   5. PdfFileService.save() 로 로컬 파일 저장
///   6. PdfSaveResult 반환 → UI에서 완료 다이얼로그 표시
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
  /// 반환: PdfSaveResult (UI에서 완료 다이얼로그에 전달)
  static Future<PdfSaveResult> export({
    required String sessionId,
    required List<MaterialModel> materials,
    required PersonalDrawingProvider personalProvider,
  }) async {
    debugPrint('🚀 PdfExportService.export() started');
    debugPrint('   sessionId: $sessionId');
    debugPrint('   materials: ${materials.length}개');

    // 1. 페이지 순서 목록 (materialTitle 기준)
    final pageIdOrder = materials.map((m) => m.title).toList();

    // 2. 개인 필기 전체 취합
    final strokes = await personalProvider.getAllPersonalStrokesForExport(
      pageIdOrder: pageIdOrder,
    );

    debugPrint('📦 Total personal strokes for export: ${strokes.length}');

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

    debugPrint('✅ PDF binary received');
    debugPrint('   strokes: ${strokes.length}, total points: $totalPoints');
    debugPrint('   size: ${pdfBytes.length} bytes');

    // 5. 로컬 파일 저장
    final saveResult = await PdfFileService.save(
      bytes: pdfBytes,
      sessionId: sessionId,
    );

    debugPrint('✅ PdfExportService.export() complete: ${saveResult.filePath}');

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
}