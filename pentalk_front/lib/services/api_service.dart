import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../models/drawing_models.dart';
import 'auth_service.dart';
import '../models/quiz_model.dart';

/// ===============================
/// REST API 클라이언트 서비스
/// ===============================
class ApiService {
  static String get baseUrl => AppConfig.apiBaseUrl;

  /// ===============================
  /// 판서 데이터 저장 (POST /strokes)
  /// ===============================
  static Future<ApiResponse> saveStrokes({
    required String sessionId,
    required List<Stroke> strokes,
  }) async {
    try {
      final token = await AuthService.getToken();

      final strokesJson = strokes
          .map((stroke) => {
        'sId': stroke.strokeId,
        'pts': stroke.points
            .map((p) => {
          'x': p.x,
          'y': p.y,
        })
            .toList(),
        'c':
        '#${stroke.color.value.toRadixString(16).padLeft(8, '0').substring(2)}',
        'w': stroke.width,
      })
          .toList();

      final body = {
        'sessionId': sessionId,
        'strokes': strokesJson,
      };

      debugPrint('POST /strokes: ${strokes.length} strokes');

      final response = await http
          .post(
        Uri.parse('$baseUrl/strokes'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Request timeout'),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Saved ${data['count']} strokes');
        return ApiResponse(success: true, data: data);
      } else {
        final error = jsonDecode(response.body);
        debugPrint('❌ Save failed: ${error['message']}');
        return ApiResponse(
          success: false,
          error: error['error'] ?? 'UNKNOWN_ERROR',
          message: error['message'] ?? 'Failed to save strokes',
        );
      }
    } catch (e) {
      debugPrint('❌ API error: $e');
      return ApiResponse(
        success: false,
        error: 'NETWORK_ERROR',
        message: e.toString(),
      );
    }

  }

  /// ===============================
  /// 판서 데이터 불러오기 (GET /strokes)
  /// ===============================
  static Future<ApiResponse<List<Stroke>>> loadStrokes({
    required String sessionId,
  }) async {
    try {
      final token = await AuthService.getToken();

      debugPrint('📥 GET /strokes?sessionId=$sessionId');

      final response = await http
          .get(
        Uri.parse('$baseUrl/strokes?sessionId=$sessionId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Request timeout'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final strokesJson = (data['strokes'] as List?) ?? const [];

        final strokes = strokesJson.map((json) {
          final item = Map<String, dynamic>.from(json as Map);
          final points = ((item['pts'] as List?) ?? const [])
              .whereType<Map>()
              .map((p) {
            final pointMap = Map<String, dynamic>.from(p);
            return DrawPoint(
              x: (pointMap['x'] as num?)?.toDouble() ?? 0.0,
              y: (pointMap['y'] as num?)?.toDouble() ?? 0.0,
            );
          }).toList();

          final colorString = (item['c'] as String?) ?? '#000000';
          final colorInt = int.tryParse(
                colorString.replaceFirst('#', ''),
                radix: 16,
              ) ??
              0;
          final color = Color(0xFF000000 | colorInt);

          final rawStrokeId = item['sId'];
          final strokeId = rawStrokeId is num
              ? rawStrokeId.toInt()
              : int.tryParse(rawStrokeId?.toString() ?? '') ?? 0;
          final rawWidth = item['w'];
          final width = rawWidth is num
              ? rawWidth.toDouble()
              : double.tryParse(rawWidth?.toString() ?? '') ?? 2.5;

          return Stroke(
            strokeId: strokeId,
            points: points,
            color: color,
            width: width,
          );
        }).toList();

        debugPrint('✅ Loaded ${strokes.length} strokes');
        return ApiResponse<List<Stroke>>(success: true, data: strokes);
      } else {
        final error = jsonDecode(response.body);
        debugPrint('❌ Load failed: ${error['message']}');
        return ApiResponse<List<Stroke>>(
          success: false,
          error: error['error'] ?? 'UNKNOWN_ERROR',
          message: error['message'] ?? 'Failed to load strokes',
        );
      }
    } catch (e) {
      debugPrint('❌ API error: $e');
      return ApiResponse<List<Stroke>>(
        success: false,
        error: 'NETWORK_ERROR',
        message: e.toString(),
      );
    }
  }

  /// ===============================
  /// PDF 내보내기 (POST /export/pdf)
  ///
  /// [sessionId]: 세션 ID
  /// [strokes]: 학생 개인 필기 stroke 배열
  ///   각 stroke 형식:
  ///   { pageNumber, c("#AARRGGBB"), w, points:[{x,y,p?}] }
  ///
  /// 반환: PDF 바이너리 + 서버 파일명
  /// ===============================
  static Future<PdfExportBinaryResponse> exportPdf({
    required String sessionId,
    List<Map<String, dynamic>>? strokes,
  }) async {
    final token = await AuthService.getToken();
    final normalizedStrokes =
        (strokes ?? const <Map<String, dynamic>>[])
            .map(_normalizeExportStroke)
            .toList();

    final body = <String, dynamic>{
      'sessionId': sessionId,
      'strokes': normalizedStrokes,
    };

    debugPrint('POST /export/pdf');
    debugPrint('   baseUrl: $baseUrl');
    debugPrint('   sessionId: $sessionId');
    debugPrint('   auth token present: ${token != null && token.isNotEmpty}');
    debugPrint('   body: ${jsonEncode(body)}');
    debugPrint('   client strokes prepared: ${normalizedStrokes.length}개');

    final response = await http
        .post(
      Uri.parse('$baseUrl/export/pdf'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/pdf',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    )
        .timeout(
      // PDF 생성은 시간이 걸릴 수 있으므로 타임아웃 넉넉하게
      const Duration(seconds: 60),
      onTimeout: () => throw TimeoutException('PDF export timeout'),
    );

    if (response.statusCode == 200) {
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (!contentType.contains('application/pdf')) {
        debugPrint('❌ Export failed: unexpected content-type=$contentType');
        throw const PdfExportApiException(
          '서버가 PDF 파일을 반환하지 않았습니다.',
          statusCode: 200,
          code: 'INVALID_CONTENT_TYPE',
        );
      }

      final serverFileName = _extractAttachmentFileName(
        response.headers['content-disposition'],
      );

      debugPrint('✅ PDF received: ${response.bodyBytes.length} bytes');
      debugPrint('   server fileName: ${serverFileName ?? '(none)'}');
      return PdfExportBinaryResponse(
        bytes: response.bodyBytes,
        fileName: serverFileName,
      );
    }

    // 에러 응답 파싱
    String errorMessage = 'PDF 생성에 실패했습니다';
    String errorCode = 'EXPORT_FAILED';

    try {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      errorMessage = error['message'] as String? ?? errorMessage;
      errorCode = error['code'] as String? ?? errorCode;
    } catch (_) {
      // 응답이 JSON이 아닌 경우 무시
    }

    debugPrint('❌ Export failed [${response.statusCode}]: $errorMessage');

    if (response.statusCode == 400) {
      throw PdfExportApiException(
        errorMessage,
        statusCode: 400,
        code: errorCode,
      );
    } else if (response.statusCode == 401) {
      throw PdfExportApiException(
        '인증이 만료되었습니다. 다시 로그인해주세요.',
        statusCode: 401,
        code: 'UNAUTHORIZED',
      );
    } else if (response.statusCode == 404) {
      throw PdfExportApiException(
        '세션을 찾을 수 없습니다.',
        statusCode: 404,
        code: 'SESSION_NOT_FOUND',
      );
    } else {
      throw PdfExportApiException(
        errorMessage,
        statusCode: response.statusCode,
        code: errorCode,
      );
    }
  }

  /// ===============================
  /// 세션 생성 (POST /session/create)
  /// ===============================
  static Future<ApiResponse<SessionCreateResponse>> createSession({
    required String classId,
    String? materialId,
  }) async {
    try {
      final token = await AuthService.getToken();

      final body = {
        'classId': classId,
        if (materialId != null && materialId.isNotEmpty) 'materialId': materialId,
      };

      debugPrint('POST /session/create');
      debugPrint('   classId: $classId');
      if (materialId != null && materialId.isNotEmpty) {
        debugPrint('   materialId: $materialId');
      }

      final response = await http
          .post(
        Uri.parse('$baseUrl/session/create'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Request timeout'),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResponse<SessionCreateResponse>(
          success: true,
          data: SessionCreateResponse.fromJson(data),
        );
      }

      String message = '세션 생성에 실패했습니다';
      String code = 'CREATE_SESSION_FAILED';
      try {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        message = error['message'] as String? ?? message;
        code = error['code'] as String? ?? code;
      } catch (_) {}

      return ApiResponse<SessionCreateResponse>(
        success: false,
        error: code,
        message: message,
      );
    } catch (e) {
      return ApiResponse<SessionCreateResponse>(
        success: false,
        error: 'NETWORK_ERROR',
        message: e.toString(),
      );
    }
  }

  /// ===============================
  /// 로그인 (POST /auth/dev-login)
  /// ===============================
  static Future<ApiResponse<LoginResponse>> login({
    required String userId,
    required String role,
  }) async {
    try {
      debugPrint('POST /auth/dev-login: userId=$userId, role=$role');

      final body = {'userId': userId, 'role': role};

      final response = await http
          .post(
        Uri.parse('$baseUrl/auth/dev-login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Login timeout'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final user = (data['user'] is Map)
            ? Map<String, dynamic>.from(data['user'] as Map)
            : <String, dynamic>{};
        final token = data['token']?.toString() ?? '';
        final parsedUserId =
            user['userId']?.toString() ?? data['userId']?.toString() ?? '';
        final parsedRole =
            user['role']?.toString() ?? data['role']?.toString() ?? role;

        debugPrint('✅ Login success: $parsedUserId');

        return ApiResponse<LoginResponse>(
          success: true,
          data: LoginResponse(
            token: token,
            userId: parsedUserId,
            role: parsedRole,
          ),
        );
      } else {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        final message = error['message']?.toString() ?? 'Login failed';
        final code = error['code']?.toString() ?? 'LOGIN_FAILED';
        debugPrint('❌ Login failed: $message');
        return ApiResponse<LoginResponse>(
          success: false,
          error: code,
          message: message,
        );
      }
    } catch (e) {
      debugPrint('❌ Login error: $e');
      return ApiResponse<LoginResponse>(
        success: false,
        error: 'NETWORK_ERROR',
        message: e.toString(),
      );
    }
  }

  /// ===============================
  /// 세션 종료 (POST /sessions/{sessionId}/end)
  /// ===============================
  static Future<ApiResponse<EndSessionResponse>> endSession({
    required String sessionId,
  }) async {
    try {
      final token = await AuthService.getToken();

      debugPrint('POST /sessions/$sessionId/end');

      final response = await http
          .post(
        Uri.parse('$baseUrl/sessions/$sessionId/end'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Request timeout'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Session ended: ${data['sessionId']}');

        return ApiResponse<EndSessionResponse>(
          success: data['ok'] ?? false,
          data: EndSessionResponse(
            sessionId: data['sessionId'],
            status: data['status'],
            strokeCount: data['strokeCount'],
            drawingPath: data['drawingPath'],
            closedAt: data['closedAt'],
          ),
        );
      } else {
        final error = jsonDecode(response.body);
        debugPrint('❌ End session failed: ${error['message']}');
        return ApiResponse<EndSessionResponse>(
          success: false,
          error: error['code'] ?? 'END_SESSION_FAILED',
          message: error['message'] ?? 'Failed to end session',
        );
      }
    } catch (e) {
      debugPrint('❌ End session error: $e');
      return ApiResponse<EndSessionResponse>(
        success: false,
        error: 'NETWORK_ERROR',
        message: e.toString(),
      );
    }
  }

  /// ===============================
  /// 판서 데이터 조회 (GET /sessions/{sessionId}/whiteboard)
  /// ===============================
  static Future<ApiResponse<WhiteboardData>> getWhiteboard({
    required String sessionId,
  }) async {
    try {
      final token = await AuthService.getToken();

      debugPrint('GET /sessions/$sessionId/whiteboard');

      final response = await http
          .get(
        Uri.parse('$baseUrl/sessions/$sessionId/whiteboard'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Request timeout'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint(
            '✅ Whiteboard loaded: ${data['strokes']?.length ?? 0} strokes');

        return ApiResponse<WhiteboardData>(
          success: true,
          data: WhiteboardData(
            sessionId: data['sessionId'],
            readOnly: data['readOnly'] ?? true,
            strokes: (data['strokes'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
                [],
          ),
        );
      } else {
        final error = jsonDecode(response.body);
        debugPrint('❌ Get whiteboard failed: ${error['message']}');
        return ApiResponse<WhiteboardData>(
          success: false,
          error: error['code'] ?? 'GET_WHITEBOARD_FAILED',
          message: error['message'] ?? 'Failed to get whiteboard',
        );
      }
    } catch (e) {
      debugPrint('❌ Get whiteboard error: $e');
      return ApiResponse<WhiteboardData>(
        success: false,
        error: 'NETWORK_ERROR',
        message: e.toString(),
      );
    }
  }

  /// ===============================
  /// 세션 상태 확인 (GET /sessions/{sessionId}/status)
  /// ===============================
  static Future<ApiResponse<SessionStatus>> getSessionStatus({
    required String sessionId,
  }) async {
    try {
      final token = await AuthService.getToken();

      debugPrint('GET /sessions/$sessionId/status');

      final response = await http
          .get(
        Uri.parse('$baseUrl/sessions/$sessionId/status'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      )
          .timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Request timeout'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Session status: ${data['status']}');

        return ApiResponse<SessionStatus>(
          success: true,
          data: SessionStatus(
            sessionId: data['sessionId'] ?? sessionId,
            status: data['status'] ?? 'UNKNOWN',
          ),
        );
      } else if (response.statusCode == 404) {
        debugPrint('❌ Session not found: $sessionId');
        return ApiResponse<SessionStatus>(
          success: false,
          error: 'SESSION_NOT_FOUND',
          message: 'Session not found',
        );
      } else {
        final error = jsonDecode(response.body);
        debugPrint('❌ Get session status failed: ${error['message']}');
        return ApiResponse<SessionStatus>(
          success: false,
          error: error['code'] ?? 'GET_STATUS_FAILED',
          message: error['message'] ?? 'Failed to get session status',
        );
      }
    } catch (e) {
      debugPrint('❌ Get session status error: $e');
      return ApiResponse<SessionStatus>(
        success: false,
        error: 'NETWORK_ERROR',
        message: e.toString(),
      );
    }
  }


  /// ===============================
  /// 자료 업로드 (POST /materials/pdf)
  /// 교사 전용, multipart/form-data
  /// ===============================
  static Future<MaterialUploadResponse> uploadMaterial({
    required String classId,
    required String filePath,
    required String fileName,
  }) async {
    final token = await AuthService.getToken();

    debugPrint('POST /materials/pdf: $fileName (classId: $classId)');

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/materials/pdf'),
    );

    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.fields['classId'] = classId;
    request.files.add(await http.MultipartFile.fromPath(
      'file',
      filePath,
      filename: fileName,
      contentType: MediaType('application', 'pdf'),
    ));

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw TimeoutException('Upload timeout'),
    );

    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint('✅ Material uploaded: ${data['id']}');
      return MaterialUploadResponse.fromJson(data);
    }

    // 에러 처리
    String errorMessage = '자료 업로드에 실패했습니다';
    try {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      errorMessage = error['message'] as String? ?? errorMessage;
    } catch (_) {}

    debugPrint('❌ Upload failed [${response.statusCode}]: $errorMessage');

    if (response.statusCode == 413) {
      throw MaterialUploadException('파일 크기가 너무 큽니다 (최대 50MB)', code: 'FILE_TOO_LARGE');
    }
    if (response.statusCode == 400) {
      throw MaterialUploadException(errorMessage, code: 'INVALID_REQUEST');
    }
    if (response.statusCode == 403) {
      throw MaterialUploadException('이 수업에 자료를 업로드할 권한이 없습니다', code: 'FORBIDDEN');
    }
    throw MaterialUploadException(errorMessage, code: 'UPLOAD_FAILED');
  }

  /// ===============================
  /// 자료 목록 조회 (GET /materials?classId=)
  /// ===============================
  static Future<List<MaterialUploadResponse>> getMaterials({
    required String classId,
  }) async {
    final token = await AuthService.getToken();

    debugPrint('📥 GET /materials?classId=$classId');

    final response = await http.get(
      Uri.parse('$baseUrl/materials?classId=$classId'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Request timeout'),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];
      debugPrint('✅ Materials loaded: ${items.length}개');
      return items
          .whereType<Map>()
          .map((e) => MaterialUploadResponse.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    String errorMessage = '자료 목록을 불러오지 못했습니다';
    try {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      errorMessage = error['message'] as String? ?? errorMessage;
    } catch (_) {}

    debugPrint('❌ Get materials failed [${response.statusCode}]: $errorMessage');
    throw MaterialUploadException(errorMessage, code: 'GET_MATERIALS_FAILED');
  }

  /// ===============================
  /// 자료 다운로드 URL 조회 (GET /materials/:materialId/download-url)
  /// presigned URL 반환
  /// ===============================
  static Future<String> getMaterialDownloadUrl({
    required String materialId,
  }) async {
    final token = await AuthService.getToken();

    debugPrint('📥 GET /materials/$materialId/download-url');

    final response = await http.get(
      Uri.parse('$baseUrl/materials/$materialId/download-url'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Request timeout'),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final url = data['url']?.toString().trim() ?? '';
      if (url.isEmpty) {
        throw const MaterialUploadException(
          '다운로드 URL이 비어 있습니다',
          code: 'EMPTY_DOWNLOAD_URL',
        );
      }
      debugPrint('✅ Material download URL loaded: $materialId');
      return url;
    }

    String errorMessage = '자료 다운로드 URL을 불러오지 못했습니다';
    try {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      errorMessage = error['message'] as String? ?? errorMessage;
    } catch (_) {}

    debugPrint(
      '❌ Get material download URL failed [${response.statusCode}]: '
      '$errorMessage',
    );
    throw MaterialUploadException(
      errorMessage,
      code: 'GET_DOWNLOAD_URL_FAILED',
    );
  }

  static String? _extractAttachmentFileName(String? contentDisposition) {
    if (contentDisposition == null || contentDisposition.trim().isEmpty) {
      return null;
    }

    final utf8Match = RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false)
        .firstMatch(contentDisposition);
    if (utf8Match != null) {
      return Uri.decodeComponent(utf8Match.group(1)!.trim());
    }

    final asciiMatch = RegExp(r'filename="?([^";]+)"?', caseSensitive: false)
        .firstMatch(contentDisposition);
    if (asciiMatch != null) {
      return asciiMatch.group(1)?.trim();
    }

    return null;
  }

  static Map<String, dynamic> _normalizeExportStroke(
    Map<String, dynamic> stroke,
  ) {
    final normalized = Map<String, dynamic>.from(stroke);
    final rawColor = normalized.remove('color');
    final rawCompactColor = normalized['c'];

    final compactColor = _normalizeArgbHex(rawCompactColor ?? rawColor);
    if (compactColor != null) {
      normalized['c'] = compactColor;
    }

    return normalized;
  }

  static String? _normalizeArgbHex(Object? value) {
    if (value == null) return null;

    if (value is Color) {
      return '#${value.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
    }

    if (value is num) {
      return '#${value.toInt().toRadixString(16).padLeft(8, '0').toUpperCase()}';
    }

    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    final hex = raw.startsWith('#') ? raw.substring(1) : raw;
    if (!RegExp(r'^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(hex)) {
      return raw.startsWith('#') ? raw : '#$raw';
    }

    final argb = hex.length == 6 ? 'FF$hex' : hex;
    return '#${argb.toUpperCase()}';
  }
  // ── 퀴즈 문항 조회 (학생 + 교사 공용) ─────────────────────
//
// GET /sessions/:sessionId/quiz
// 응답: { ok: true, questions: [...] }
//
// 반환: List<QuizQuestion>
// 교사 응답에는 answer 포함, 학생 응답에는 answer null
//
  static Future<List<QuizQuestion>> getQuizQuestions({
    required String sessionId,
  }) async {
    final token = await AuthService.getToken();
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/sessions/$sessionId/quiz');

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final rawQuestions = body['questions'] as List<dynamic>? ?? [];
      return rawQuestions
          .whereType<Map>()
          .map((q) => QuizQuestion.fromJson(Map<String, dynamic>.from(q)))
          .toList();
    }

    throw Exception('퀴즈 조회 실패 [${response.statusCode}]');
  }

// ── 퀴즈 답안 제출 (학생) ─────────────────────────────────
//
// POST /sessions/:sessionId/quiz/submit
// Body: { questionId, answer }
// 응답: { ok, questionId, isCorrect, submittedAnswer, correctAnswer }
// 429: QUIZ_DAILY_LIMIT_EXCEEDED
//
  static Future<QuizSubmitResult> submitQuizAnswer({
    required String sessionId,
    required String questionId,
    required String answer,
  }) async {
    final token = await AuthService.getToken();
    final uri = Uri.parse(
        '${AppConfig.apiBaseUrl}/sessions/$sessionId/quiz/submit');

    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'questionId': questionId, 'answer': answer}),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return QuizSubmitResult.fromJson(body);
    }

    if (response.statusCode == 429) {
      // 하루 2회 초과
      throw const QuizDailyLimitException();
    }

    throw Exception('퀴즈 제출 실패 [${response.statusCode}]');
  }

// ── 퀴즈 문항 추가 (교사) ─────────────────────────────────
//
// POST /sessions/:sessionId/quiz
// Body: { question, answer, order }
// 응답: { ok: true, question: { id, question, answer, order, createdAt } }
//
  static Future<QuizQuestion> addQuizQuestion({
    required String sessionId,
    required String question,
    required String answer,
    required int order,
  }) async {
    final token = await AuthService.getToken();
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/sessions/$sessionId/quiz');

    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'question': question,
        'answer': answer,
        'order': order,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final rawQuestion = body['question'] as Map<String, dynamic>;
      return QuizQuestion.fromJson(rawQuestion);
    }

    throw Exception('문항 추가 실패 [${response.statusCode}]');
  }

// ── 퀴즈 문항 수정 (교사) ─────────────────────────────────
//
// PUT /sessions/:sessionId/quiz/:questionId
// Body: { question?, answer? }
//
  static Future<QuizQuestion> updateQuizQuestion({
    required String sessionId,
    required String questionId,
    String? question,
    String? answer,
  }) async {
    assert(question != null || answer != null,
    'question 또는 answer 중 하나는 필수입니다');

    final token = await AuthService.getToken();
    final uri = Uri.parse(
        '${AppConfig.apiBaseUrl}/sessions/$sessionId/quiz/$questionId');

    final body = <String, dynamic>{};
    if (question != null) body['question'] = question;
    if (answer != null) body['answer'] = answer;

    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
      final rawQuestion = responseBody['question'] as Map<String, dynamic>;
      return QuizQuestion.fromJson(rawQuestion);
    }

    throw Exception('문항 수정 실패 [${response.statusCode}]');
  }

// ── 퀴즈 문항 삭제 (교사) ─────────────────────────────────
//
// DELETE /sessions/:sessionId/quiz/:questionId
//
  static Future<void> deleteQuizQuestion({
    required String sessionId,
    required String questionId,
  }) async {
    final token = await AuthService.getToken();
    final uri = Uri.parse(
        '${AppConfig.apiBaseUrl}/sessions/$sessionId/quiz/$questionId');

    final response = await http.delete(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('문항 삭제 실패 [${response.statusCode}]');
    }
  }
}

/// ===============================
/// 모델 클래스들
/// ===============================

class EndSessionResponse {
  final String sessionId;
  final String status;
  final int strokeCount;
  final String drawingPath;
  final String closedAt;

  EndSessionResponse({
    required this.sessionId,
    required this.status,
    required this.strokeCount,
    required this.drawingPath,
    required this.closedAt,
  });
}

class LoginResponse {
  final String token;
  final String userId;
  final String role;

  LoginResponse({
    required this.token,
    required this.userId,
    required this.role,
  });
}

class WhiteboardData {
  final String sessionId;
  final bool readOnly;
  final List<Map<String, dynamic>> strokes;

  WhiteboardData({
    required this.sessionId,
    required this.readOnly,
    required this.strokes,
  });
}

class SessionStatus {
  final String sessionId;
  final String status;

  SessionStatus({required this.sessionId, required this.status});

  bool get isActive => status == 'ACTIVE';
  bool get isArchived => status == 'ARCHIVED';
}

class SessionCreateResponse {
  final String sessionId;
  final String? materialId;
  final String? joinUrlTeacher;
  final String? joinUrlStudent;
  final int? ttlSeconds;

  SessionCreateResponse({
    required this.sessionId,
    this.materialId,
    this.joinUrlTeacher,
    this.joinUrlStudent,
    this.ttlSeconds,
  });

  factory SessionCreateResponse.fromJson(Map<String, dynamic> json) {
    final ttlRaw = json['ttlSeconds'];
    return SessionCreateResponse(
      sessionId: json['sessionId']?.toString() ?? '',
      materialId: json['materialId']?.toString(),
      joinUrlTeacher: json['joinUrlTeacher']?.toString(),
      joinUrlStudent: json['joinUrlStudent']?.toString(),
      ttlSeconds: ttlRaw is num ? ttlRaw.toInt() : int.tryParse(ttlRaw?.toString() ?? ''),
    );
  }
}

class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? error;
  final String? message;

  ApiResponse({
    required this.success,
    this.data,
    this.error,
    this.message,
  });
}

/// ===============================
/// 자료 업로드 응답 모델
/// ===============================
class MaterialUploadResponse {
  final String id;
  final String type;
  final String url;
  final String name;
  final String classId;
  final String createdAt;

  MaterialUploadResponse({
    required this.id,
    required this.type,
    required this.url,
    required this.name,
    required this.classId,
    required this.createdAt,
  });

  factory MaterialUploadResponse.fromJson(Map<String, dynamic> json) {
    String toStringValue(dynamic value, {required String fallback}) {
      if (value == null) return fallback;
      final result = value.toString().trim();
      return result.isEmpty ? fallback : result;
    }

    final resolvedName = [
      json['name'],
      json['title'],
      json['fileName'],
      json['filename'],
    ]
        .map((value) => value?.toString().trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => 'untitled');

    final resolvedUrl = [
      json['url'],
      json['downloadUrl'],
      json['fileUrl'],
      json['s3Key'],
      json['key'],
    ]
        .map((value) => value?.toString().trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    final resolvedCreatedAt = [
      json['createdAt'],
      json['uploadedAt'],
      json['updatedAt'],
    ]
        .map((value) => value?.toString().trim() ?? '')
        .firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => DateTime.now().toIso8601String(),
        );

    return MaterialUploadResponse(
      id: toStringValue(json['id'], fallback: ''),
      type: toStringValue(json['type'], fallback: 'pdf'),
      url: resolvedUrl,
      name: resolvedName,
      classId: toStringValue(json['classId'], fallback: ''),
      createdAt: resolvedCreatedAt,
    );
  }
}

/// ===============================
/// 자료 업로드 예외
/// ===============================
class MaterialUploadException implements Exception {
  final String message;
  final String code;

  const MaterialUploadException(this.message, {required this.code});

  @override
  String toString() => message;
}

/// PDF export API 전용 예외
class PdfExportApiException implements Exception {
  final String message;
  final int statusCode;
  final String code;

  const PdfExportApiException(
      this.message, {
        required this.statusCode,
        required this.code,
      });

  @override
  String toString() => message;
}

class PdfExportBinaryResponse {
  final Uint8List bytes;
  final String? fileName;

  const PdfExportBinaryResponse({
    required this.bytes,
    this.fileName,
  });
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}
