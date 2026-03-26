import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/student_session_model.dart';
import '../providers/personal_drawing_provider.dart';
import '../services/api_service.dart';

/// ===============================
/// PDF export 결과 모델
/// ===============================
class PdfExportResult {
  final File file;
  final String filePath;
  final int strokeCount;
  final int pageCount;
  final int fileSizeBytes;

  PdfExportResult({
    required this.file,
    required this.filePath,
    required this.strokeCount,
    required this.pageCount,
    required this.fileSizeBytes,
  });

  String get formattedFileSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// ===============================
/// PDF export 예외
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
///   4. POST /export/pdf 호출
///   5. 응답 바이너리를 로컬 파일로 저장
/// ===============================
class PdfExportService {
  // 서버 제한 (400 에러 방지)
  static const int _maxStrokes = 3000;
  static const int _maxPoints = 50000;

  /// PDF 내보내기 메인 메서드
  ///
  /// [sessionId]: 현재 세션 ID
  /// [materials]: 세션의 자료 목록 (페이지 순서 기준)
  /// [personalProvider]: 개인 필기 provider
  static Future<PdfExportResult> export({
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

    // 3. 유효성 검사 (서버 제한 초과 시 에러)
    _validate(strokes);

    // 4. API 호출
    final pdfBytes = await ApiService.exportPdf(
      sessionId: sessionId,
      strokes: strokes,
    );

    // 5. 로컬 파일 저장
    final file = await _saveToFile(pdfBytes, sessionId);

    // 총 포인트 수 계산 (로깅용)
    final totalPoints = strokes.fold<int>(
      0,
          (sum, s) => sum + ((s['points'] as List?)?.length ?? 0),
    );

    debugPrint('✅ PDF export complete');
    debugPrint('   strokes: ${strokes.length}');
    debugPrint('   total points: $totalPoints');
    debugPrint('   file size: ${pdfBytes.length} bytes');
    debugPrint('   path: ${file.path}');

    return PdfExportResult(
      file: file,
      filePath: file.path,
      strokeCount: strokes.length,
      pageCount: materials.length,
      fileSizeBytes: pdfBytes.length,
    );
  }

  /// ===============================
  /// 유효성 검사
  /// ===============================
  static void _validate(List<Map<String, dynamic>> strokes) {
    // stroke 수 제한
    if (strokes.length > _maxStrokes) {
      throw PdfExportException(
        '필기 데이터가 너무 많습니다 (${strokes.length}개 / 최대 $_maxStrokes개).\n'
            '일부 필기를 삭제한 후 다시 시도해주세요.',
        code: 'STROKE_LIMIT_EXCEEDED',
      );
    }

    // 총 포인트 수 제한
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

  /// ===============================
  /// PDF 바이너리 → 로컬 파일 저장
  /// ===============================
  static Future<File> _saveToFile(Uint8List bytes, String sessionId) async {
    final dir = await getApplicationDocumentsDirectory();

    // 파일명: pentalk_{sessionId}_{timestamp}.pdf
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'pentalk_${sessionId}_$timestamp.pdf';
    final filePath = '${dir.path}/$fileName';

    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);

    debugPrint('💾 PDF saved: $filePath');
    return file;
  }
}