import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// ===============================
/// PDF 파일 처리 서비스
/// 저장 / 열기 / 공유
/// ===============================
class PdfFileService {
  /// ===============================
  /// PDF 바이너리 → 로컬 파일 저장
  ///
  /// 저장 위치: 앱 문서 디렉토리
  ///   iOS:     /Documents/
  ///   Android: /files/
  ///
  /// 파일명: pentalk_{sessionId}_{yyyyMMdd_HHmmss}.pdf
  /// ===============================
  static Future<PdfSaveResult> save({
    required Uint8List bytes,
    required String sessionId,
  }) async {
    debugPrint('💾 PdfFileService.save() started');

    final dir = await getApplicationDocumentsDirectory();

    // 파일명: pentalk_sessionId_날짜시간.pdf
    final now = DateTime.now();
    final timestamp =
        '${now.year}${_pad(now.month)}${_pad(now.day)}_'
        '${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
    final fileName = 'pentalk_${sessionId}_$timestamp.pdf';
    final filePath = '${dir.path}/$fileName';

    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);

    debugPrint('✅ PDF saved: $filePath (${bytes.length} bytes)');

    return PdfSaveResult(
      file: file,
      fileName: fileName,
      filePath: filePath,
      // 사용자에게 보여줄 경로 (문서 폴더 기준 상대 경로)
      displayPath: '문서 폴더 / $fileName',
      fileSizeBytes: bytes.length,
      savedAt: now,
    );
  }

  /// ===============================
  /// PDF 파일 열기
  /// 기기의 기본 PDF 앱으로 열기
  /// ===============================
  static Future<OpenResult> open(String filePath) async {
    debugPrint('📂 Opening PDF: $filePath');

    final result = await OpenFile.open(filePath, type: 'application/pdf');

    switch (result.type) {
      case ResultType.done:
        debugPrint('✅ PDF opened successfully');
        break;
      case ResultType.noAppToOpen:
        debugPrint('⚠️ No PDF app found on device');
        break;
      case ResultType.fileNotFound:
        debugPrint('❌ PDF file not found: $filePath');
        break;
      case ResultType.permissionDenied:
        debugPrint('❌ Permission denied to open PDF');
        break;
      case ResultType.error:
        debugPrint('❌ Error opening PDF: ${result.message}');
        break;
    }

    return result;
  }

  /// ===============================
  /// PDF 파일 공유
  /// share_plus 시트 띄우기
  /// ===============================
  static Future<void> share({
    required String filePath,
    required String fileName,
    // 태블릿에서 공유 시트 위치 지정용 (선택)
    Rect? sharePositionOrigin,
  }) async {
    debugPrint('📤 Sharing PDF: $filePath');

    final xFile = XFile(
      filePath,
      mimeType: 'application/pdf',
      name: fileName,
    );

    await Share.shareXFiles(
      [xFile],
      subject: fileName,
      sharePositionOrigin: sharePositionOrigin,
    );

    debugPrint('✅ Share sheet presented');
  }

  /// ===============================
  /// 파일 삭제 (필요 시)
  /// ===============================
  static Future<void> delete(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('🗑️ PDF deleted: $filePath');
      }
    } catch (e) {
      debugPrint('❌ Failed to delete PDF: $e');
    }
  }

  /// ===============================
  /// 저장된 PDF 목록 조회
  /// ===============================
  static Future<List<File>> getSavedPdfs() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.pdf') && f.path.contains('pentalk_'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path)); // 최신순

      return files;
    } catch (e) {
      debugPrint('❌ Failed to list PDFs: $e');
      return [];
    }
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}

/// ===============================
/// PDF 저장 결과 모델
/// ===============================
class PdfSaveResult {
  final File file;
  final String fileName;
  final String filePath;
  final String displayPath; // 사용자에게 보여줄 경로
  final int fileSizeBytes;
  final DateTime savedAt;

  PdfSaveResult({
    required this.file,
    required this.fileName,
    required this.filePath,
    required this.displayPath,
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