import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../models/drawing_models.dart';
import 'auth_service.dart';

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

      debugPrint('📤 POST /strokes: ${strokes.length} strokes');

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
  ///   { sId, color(int), width, page(1~), points:[{x,y,p?}] }
  ///
  /// 반환: PDF 바이너리 (Uint8List)
  /// ===============================
  static Future<Uint8List> exportPdf({
    required String sessionId,
    required List<Map<String, dynamic>> strokes,
  }) async {
    final token = await AuthService.getToken();

    final body = {
      'sessionId': sessionId,
      'strokes': strokes,
    };

    debugPrint('📤 POST /export/pdf');
    debugPrint('   sessionId: $sessionId');
    debugPrint('   strokes: ${strokes.length}개');

    final response = await http
        .post(
      Uri.parse('$baseUrl/export/pdf'),
      headers: {
        'Content-Type': 'application/json',
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
      debugPrint('✅ PDF received: ${response.bodyBytes.length} bytes');
      return response.bodyBytes;
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
  /// 로그인 (POST /auth/dev-login)
  /// ===============================
  static Future<ApiResponse<LoginResponse>> login({
    required String userId,
    required String role,
  }) async {
    try {
      debugPrint('📤 POST /auth/dev-login: userId=$userId, role=$role');

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
        final data = jsonDecode(response.body);
        debugPrint('✅ Login success: ${data['user']['userId']}');

        return ApiResponse<LoginResponse>(
          success: true,
          data: LoginResponse(
            token: data['token'],
            userId: data['user']['userId'],
            role: data['user']['role'],
          ),
        );
      } else {
        final error = jsonDecode(response.body);
        debugPrint('❌ Login failed: ${error['message']}');
        return ApiResponse<LoginResponse>(
          success: false,
          error: error['code'] ?? 'LOGIN_FAILED',
          message: error['message'] ?? 'Login failed',
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

      debugPrint('📤 POST /sessions/$sessionId/end');

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

      debugPrint('📤 GET /sessions/$sessionId/whiteboard');

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

      debugPrint('📤 GET /sessions/$sessionId/status');

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

    debugPrint('📤 POST /materials/pdf: $fileName (classId: $classId)');

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
    String _toStringValue(dynamic value, {required String fallback}) {
      if (value == null) return fallback;
      final result = value.toString().trim();
      return result.isEmpty ? fallback : result;
    }

    return MaterialUploadResponse(
      id: _toStringValue(json['id'], fallback: ''),
      type: _toStringValue(json['type'], fallback: 'pdf'),
      url: _toStringValue(json['url'], fallback: ''),
      name: _toStringValue(json['name'], fallback: 'untitled'),
      classId: _toStringValue(json['classId'], fallback: ''),
      createdAt: _toStringValue(
        json['createdAt'],
        fallback: DateTime.now().toIso8601String(),
      ),
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

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}
