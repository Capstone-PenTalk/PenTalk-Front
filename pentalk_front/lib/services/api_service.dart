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
          .map(
            (stroke) => {
              'sId': stroke.strokeId,
              'pts': stroke.points.map((p) => {'x': p.x, 'y': p.y}).toList(),
              'c':
                  '#${stroke.color.value.toRadixString(16).padLeft(8, '0').substring(2)}',
              'w': stroke.width,
            },
          )
          .toList();

      final body = {'sessionId': sessionId, 'strokes': strokesJson};

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
              })
              .toList();

          final colorString = (item['c'] as String?) ?? '#000000';
          final colorInt =
              int.tryParse(colorString.replaceFirst('#', ''), radix: 16) ?? 0;
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
  ///   { page, c("#RRGGBB"), w, points:[{x,y,p?}] }
  ///
  /// 반환: PDF 바이너리 + 서버 파일명
  /// ===============================
  static Future<PdfExportBinaryResponse> exportPdf({
    required String sessionId,
    List<Map<String, dynamic>>? strokes,
  }) async {
    final token = await AuthService.getToken();
    final normalizedStrokes = (strokes ?? const <Map<String, dynamic>>[])
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
    String? title,
    int? maxParticipants,
    String? password,
  }) async {
    try {
      final token = await _ensureTeacherToken();

      final body = {
        'classId': classId,
        if (materialId != null && materialId.isNotEmpty)
          'materialId': materialId,
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        if (maxParticipants != null) 'capacity': maxParticipants,
        if (password != null && password.trim().isNotEmpty)
          'password': password.trim(),
      };

      debugPrint('POST /session/create');
      debugPrint('   classId: $classId');
      if (materialId != null && materialId.isNotEmpty) {
        debugPrint('   materialId: $materialId');
      }
      if (title != null && title.trim().isNotEmpty) {
        debugPrint('   title: ${title.trim()}');
      }
      if (maxParticipants != null) {
        debugPrint('   capacity: $maxParticipants');
      }
      if (password != null && password.trim().isNotEmpty) {
        debugPrint('   password: <set>');
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

  static Future<ApiResponse<ClassCreateResponse>> createClass({
    required String title,
  }) async {
    try {
      final token = await _ensureTeacherToken();
      final body = {'title': title.trim()};

      debugPrint('POST /classes');
      debugPrint('   title: ${title.trim()}');

      final response = await http
          .post(
            Uri.parse('$baseUrl/classes'),
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
        return ApiResponse<ClassCreateResponse>(
          success: true,
          data: ClassCreateResponse.fromJson(data),
        );
      }

      String message = '클래스 생성에 실패했습니다';
      String code = 'CREATE_CLASS_FAILED';
      try {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        message = error['message'] as String? ?? message;
        code = error['code'] as String? ?? code;
      } catch (_) {}

      return ApiResponse<ClassCreateResponse>(
        success: false,
        error: code,
        message: message,
      );
    } catch (e) {
      return ApiResponse<ClassCreateResponse>(
        success: false,
        error: 'NETWORK_ERROR',
        message: e.toString(),
      );
    }
  }

  static Future<String?> _ensureTeacherToken() async {
    final response = await login(userId: 'teacher1', role: 'teacher');
    if (!response.success || response.data == null) {
      throw Exception(response.message ?? '교사 인증 토큰 발급 실패');
    }

    final loginData = response.data!;
    await AuthService.saveUserInfo(
      userId: loginData.userId,
      role: loginData.role,
      token: loginData.token,
    );
    return loginData.token;
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
          '✅ Whiteboard loaded: ${data['strokes']?.length ?? 0} strokes',
        );

        return ApiResponse<WhiteboardData>(
          success: true,
          data: WhiteboardData(
            sessionId: data['sessionId'],
            readOnly: data['readOnly'] ?? true,
            strokes:
                (data['strokes'] as List?)
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
  /// 세션 참여 (POST /sessions/{sessionId}/join)
  /// ===============================
  static Future<ApiResponse<SessionJoinResponse>> joinSession({
    required String sessionId,
    required String password,
    String? materialId,
  }) async {
    try {
      final token = await AuthService.getToken();
      final trimmedMaterialId = materialId?.trim();
      final body = {
        'password': password,
        if (trimmedMaterialId != null && trimmedMaterialId.isNotEmpty)
          'materialId': trimmedMaterialId,
      };

      debugPrint('POST /sessions/$sessionId/join');
      if (trimmedMaterialId != null && trimmedMaterialId.isNotEmpty) {
        debugPrint('   materialId: $trimmedMaterialId');
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/sessions/$sessionId/join'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException('Request timeout'),
          );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('✅ Session joined: $sessionId');
        debugPrint('   response: ${response.body}');

        return ApiResponse<SessionJoinResponse>(
          success: true,
          data: SessionJoinResponse.fromJson(
            data,
            fallbackSessionId: sessionId,
          ),
        );
      } else if (response.statusCode == 404) {
        if (response.body.contains('Cannot POST')) {
          debugPrint('⚠️ Session join endpoint unavailable');
          return ApiResponse<SessionJoinResponse>(
            success: false,
            error: 'SESSION_JOIN_UNAVAILABLE',
            message: 'Session join endpoint unavailable',
          );
        }
        debugPrint('❌ Session not found: $sessionId');
        return ApiResponse<SessionJoinResponse>(
          success: false,
          error: 'SESSION_NOT_FOUND',
          message: 'Session not found',
        );
      } else {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('❌ Join session failed: ${error['message']}');
        return ApiResponse<SessionJoinResponse>(
          success: false,
          error: error['code']?.toString() ?? 'JOIN_SESSION_FAILED',
          message: error['message']?.toString() ?? 'Failed to join session',
        );
      }
    } catch (e) {
      debugPrint('❌ Join session error: $e');
      return ApiResponse<SessionJoinResponse>(
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
    String? sessionId,
    required String filePath,
    required String fileName,
  }) async {
    final token = await AuthService.getToken();
    final trimmedSessionId = sessionId?.trim();

    debugPrint(
      'POST /materials/pdf: $fileName (classId: $classId'
      '${trimmedSessionId != null && trimmedSessionId.isNotEmpty ? ', sessionId: $trimmedSessionId' : ''})',
    );

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/materials/pdf'),
    );

    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.fields['classId'] = classId;
    if (trimmedSessionId != null && trimmedSessionId.isNotEmpty) {
      request.fields['sessionId'] = trimmedSessionId;
    }
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        filePath,
        filename: fileName,
        contentType: MediaType('application', 'pdf'),
      ),
    );

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw TimeoutException('Upload timeout'),
    );

    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final uploaded = MaterialUploadResponse.fromJson(data);
      debugPrint('✅ Material uploaded: ${uploaded.id}');
      return uploaded;
    }

    // 에러 처리
    String errorMessage = '자료 업로드에 실패했습니다';
    try {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      errorMessage = error['message'] as String? ?? errorMessage;
    } catch (_) {}

    debugPrint('❌ Upload failed [${response.statusCode}]: $errorMessage');

    if (response.statusCode == 413) {
      throw MaterialUploadException(
        '파일 크기가 너무 큽니다 (최대 50MB)',
        code: 'FILE_TOO_LARGE',
      );
    }
    if (response.statusCode == 400) {
      throw MaterialUploadException(errorMessage, code: 'INVALID_REQUEST');
    }
    if (response.statusCode == 403) {
      throw MaterialUploadException(
        '이 수업에 자료를 업로드할 권한이 없습니다',
        code: 'FORBIDDEN',
      );
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

    final response = await http
        .get(
          Uri.parse('$baseUrl/materials?classId=$classId'),
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
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];
      debugPrint('✅ Materials loaded: ${items.length}개');
      return items
          .whereType<Map>()
          .map(
            (e) =>
                MaterialUploadResponse.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList();
    }

    String errorMessage = '자료 목록을 불러오지 못했습니다';
    try {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      errorMessage = error['message'] as String? ?? errorMessage;
    } catch (_) {}

    debugPrint(
      '❌ Get materials failed [${response.statusCode}]: $errorMessage',
    );
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

    final response = await http
        .get(
          Uri.parse('$baseUrl/materials/$materialId/download-url'),
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

    final utf8Match = RegExp(
      r"filename\*=UTF-8''([^;]+)",
      caseSensitive: false,
    ).firstMatch(contentDisposition);
    if (utf8Match != null) {
      return Uri.decodeComponent(utf8Match.group(1)!.trim());
    }

    final asciiMatch = RegExp(
      r'filename="?([^";]+)"?',
      caseSensitive: false,
    ).firstMatch(contentDisposition);
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

    final compactColor = _normalizeRgbHex(rawCompactColor ?? rawColor);
    if (compactColor != null) {
      normalized['c'] = compactColor;
    }

    return normalized;
  }

  static String? _normalizeRgbHex(Object? value) {
    if (value == null) return null;

    if (value is Color) {
      return '#${(value.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    }

    if (value is num) {
      return '#${(value.toInt() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    }

    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    final hex = raw.startsWith('#') ? raw.substring(1) : raw;
    if (!RegExp(r'^([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(hex)) {
      return raw.startsWith('#') ? raw : '#$raw';
    }

    final rgb = hex.length == 8 ? hex.substring(2) : hex;
    return '#${rgb.toUpperCase()}';
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

    // 404 = 아직 등록된 문항 없음 → 빈 리스트 반환
    if (response.statusCode == 404) {
      return [];
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
    bool isRetryStart = false,
  }) async {
    final token = await AuthService.getToken();
    final uri = Uri.parse(
      '${AppConfig.apiBaseUrl}/sessions/$sessionId/quiz/submit',
    );

    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'questionId': questionId,
        'answer': answer,
        'isRetryStart': isRetryStart,
      }),
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
    assert(
      question != null || answer != null,
      'question 또는 answer 중 하나는 필수입니다',
    );

    final token = await AuthService.getToken();
    final uri = Uri.parse(
      '${AppConfig.apiBaseUrl}/sessions/$sessionId/quiz/$questionId',
    );

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
      '${AppConfig.apiBaseUrl}/sessions/$sessionId/quiz/$questionId',
    );

    final response = await http.delete(
      uri,
      headers: {'Authorization': 'Bearer $token'},
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

  bool get isActive => status.toUpperCase() == 'ACTIVE';
  bool get isArchived => status.toUpperCase() == 'ARCHIVED';
}

class SessionJoinResponse {
  final String sessionId;
  final String? classId;
  final String? materialId;
  final SessionJoinMaterial? material;
  final String? status;

  SessionJoinResponse({
    required this.sessionId,
    this.classId,
    this.materialId,
    this.material,
    this.status,
  });

  factory SessionJoinResponse.fromJson(
    Map<String, dynamic> json, {
    required String fallbackSessionId,
  }) {
    final payload = _unwrapJoinPayload(json);
    final material = payload['material'] is Map
        ? SessionJoinMaterial.fromJson(
            Map<String, dynamic>.from(payload['material'] as Map),
          )
        : null;

    return SessionJoinResponse(
      sessionId:
          payload['sessionId']?.toString() ??
          payload['roomId']?.toString() ??
          fallbackSessionId,
      classId: payload['classId']?.toString(),
      materialId: payload['materialId']?.toString() ?? material?.id,
      material: material,
      status: payload['status']?.toString(),
    );
  }

  static Map<String, dynamic> _unwrapJoinPayload(Map<String, dynamic> json) {
    for (final key in const ['data', 'payload']) {
      final value = json[key];
      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }
    }
    return json;
  }
}

class SessionJoinMaterial {
  final String id;
  final String name;
  final String type;
  final String url;

  SessionJoinMaterial({
    required this.id,
    required this.name,
    required this.type,
    required this.url,
  });

  factory SessionJoinMaterial.fromJson(Map<String, dynamic> json) {
    return SessionJoinMaterial(
      id: json['id']?.toString().trim() ?? '',
      name: json['name']?.toString().trim() ?? '자료',
      type: json['type']?.toString().trim() ?? '',
      url:
          json['url']?.toString().trim() ??
          json['downloadUrl']?.toString().trim() ??
          '',
    );
  }
}

class ClassCreateResponse {
  final String id;
  final String title;
  final String? teacherId;
  final String? createdAt;

  ClassCreateResponse({
    required this.id,
    required this.title,
    this.teacherId,
    this.createdAt,
  });

  factory ClassCreateResponse.fromJson(Map<String, dynamic> json) {
    return ClassCreateResponse(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      teacherId: json['teacherId']?.toString(),
      createdAt: json['createdAt']?.toString(),
    );
  }
}

class SessionCreateResponse {
  final String sessionId;
  final String? materialId;
  final String? joinUrl;
  final String? joinUrlTeacher;
  final String? joinUrlStudent;
  final int? ttlSeconds;

  SessionCreateResponse({
    required this.sessionId,
    this.materialId,
    this.joinUrl,
    this.joinUrlTeacher,
    this.joinUrlStudent,
    this.ttlSeconds,
  });

  factory SessionCreateResponse.fromJson(Map<String, dynamic> json) {
    final ttlRaw = json['ttlSeconds'];
    return SessionCreateResponse(
      sessionId: json['sessionId']?.toString() ?? '',
      materialId: json['materialId']?.toString(),
      joinUrl: json['joinUrl']?.toString(),
      joinUrlTeacher: json['joinUrlTeacher']?.toString(),
      joinUrlStudent: json['joinUrlStudent']?.toString(),
      ttlSeconds: ttlRaw is num
          ? ttlRaw.toInt()
          : int.tryParse(ttlRaw?.toString() ?? ''),
    );
  }
}

class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? error;
  final String? message;

  ApiResponse({required this.success, this.data, this.error, this.message});
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
    final payload = _unwrapMaterialPayload(json);

    String toStringValue(dynamic value, {required String fallback}) {
      if (value == null) return fallback;
      final result = value.toString().trim();
      return result.isEmpty ? fallback : result;
    }

    final resolvedName =
        [
              payload['name'],
              payload['title'],
              payload['fileName'],
              payload['filename'],
            ]
            .map((value) => value?.toString().trim() ?? '')
            .firstWhere((value) => value.isNotEmpty, orElse: () => 'untitled');

    final resolvedUrl =
        [
              payload['url'],
              payload['downloadUrl'],
              payload['fileUrl'],
              payload['s3Key'],
              payload['key'],
            ]
            .map((value) => value?.toString().trim() ?? '')
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    final resolvedCreatedAt =
        [payload['createdAt'], payload['uploadedAt'], payload['updatedAt']]
            .map((value) => value?.toString().trim() ?? '')
            .firstWhere(
              (value) => value.isNotEmpty,
              orElse: () => DateTime.now().toIso8601String(),
            );

    return MaterialUploadResponse(
      id: toStringValue(payload['id'], fallback: ''),
      type: toStringValue(payload['type'], fallback: 'pdf'),
      url: resolvedUrl,
      name: resolvedName,
      classId: toStringValue(payload['classId'], fallback: ''),
      createdAt: resolvedCreatedAt,
    );
  }

  static Map<String, dynamic> _unwrapMaterialPayload(
    Map<String, dynamic> json,
  ) {
    for (final key in const ['material', 'data', 'payload']) {
      final value = json[key];
      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }
    }
    return json;
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

  const PdfExportBinaryResponse({required this.bytes, this.fileName});
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}
