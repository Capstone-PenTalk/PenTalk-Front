import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../models/document_source.dart';

class PdfDocumentService {
  static const MethodChannel _channel = MethodChannel('pentalk/pdf');

  static Future<DocumentSource> openDocument({
    required String materialId,
    required String pdfUrl,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('PDF native rendering is not supported on web.');
    }

    final localPdfPath = await _ensureLocalPdf(
      materialId: materialId,
      pdfUrl: pdfUrl,
    );

    final result = await _channel.invokeMapMethod<String, dynamic>(
      'inspectDocument',
      {
        'materialId': materialId,
        'pdfUrl': pdfUrl,
        'localPdfPath': localPdfPath,
      },
    );

    if (result == null) {
      throw Exception('PDF 문서 정보를 불러오지 못했습니다.');
    }

    return DocumentSource.fromJson(Map<String, dynamic>.from(result));
  }

  static Future<DocumentPageSource> renderPage({
    required DocumentSource document,
    required int pageNumber,
    int targetWidth = 1440,
    bool generateThumbnail = false,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('PDF native rendering is not supported on web.');
    }

    final result = await _channel.invokeMapMethod<String, dynamic>(
      'renderPage',
      {
        'materialId': document.materialId,
        'localPdfPath': document.localPdfPath,
        'pageNumber': pageNumber,
        'targetWidth': targetWidth,
        'generateThumbnail': generateThumbnail,
      },
    );

    if (result == null) {
      throw Exception('PDF 페이지를 렌더링하지 못했습니다.');
    }

    return DocumentPageSource.fromJson(Map<String, dynamic>.from(result));
  }

  static Future<String> _ensureLocalPdf({
    required String materialId,
    required String pdfUrl,
  }) async {
    final resolvedPdfUrl = _resolvePdfUrl(pdfUrl);

    if (_isRemoteUrl(resolvedPdfUrl)) {
      final directory = await _cacheDirectory();
      final filePath = p.join(directory.path, '$materialId.pdf');
      final file = File(filePath);
      if (await file.exists()) {
        return file.path;
      }

      final response = await http.get(Uri.parse(resolvedPdfUrl));
      if (response.statusCode != 200) {
        throw Exception('PDF 다운로드 실패 [${response.statusCode}]');
      }
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file.path;
    }

    final file = File(resolvedPdfUrl);
    if (await file.exists()) {
      return file.path;
    }
    throw Exception('PDF 파일을 찾을 수 없습니다: $resolvedPdfUrl');
  }

  static bool _isRemoteUrl(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  static String _resolvePdfUrl(String pdfUrl) {
    final trimmed = pdfUrl.trim();
    if (trimmed.isEmpty) return trimmed;
    if (_isRemoteUrl(trimmed) || trimmed.startsWith('file://')) {
      return trimmed;
    }
    if (p.isAbsolute(trimmed)) {
      return trimmed;
    }
    return Uri.parse('${AppConfig.apiBaseUrl}/').resolve(trimmed).toString();
  }

  static Future<Directory> _cacheDirectory() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(baseDir.path, 'pdf_cache'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }
}
