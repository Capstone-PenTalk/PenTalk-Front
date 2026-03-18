import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';  // Color 사용
import '../models/drawing_models.dart';
import 'auth_service.dart';

/// ===============================
/// REST API 클라이언트 서비스
/// 판서 데이터 저장/불러오기
/// ===============================
class ApiService {
  // 서버 베이스 URL (개발 환경)
  static const String baseUrl = 'http://localhost:3000';

  /// ===============================
  /// 판서 데이터 저장 (POST /strokes)
  /// ===============================
  static Future<ApiResponse> saveStrokes({
    required String sessionId,
    required List<Stroke> strokes,
  }) async {
    try {
      // JWT 토큰 가져오기
      final token = await AuthService.getToken();

      // Stroke → JSON 변환
      final strokesJson = strokes.map((stroke) => {
        'sId': stroke.strokeId,  // id → strokeId
        'pts': stroke.points.map((p) => {
          'x': p.x,
          'y': p.y,
        }).toList(),
        'c': '#${stroke.color.value.toRadixString(16).padLeft(8, '0').substring(2)}',
        'w': stroke.width,
      }).toList();

      final body = {
        'sessionId': sessionId,
        'strokes': strokesJson,
      };

      debugPrint('📤 POST /strokes: ${strokes.length} strokes');

      // HTTP 요청
      final response = await http.post(
        Uri.parse('$baseUrl/strokes'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Request timeout');
        },
      );

      // 응답 처리
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Saved ${data['count']} strokes');

        return ApiResponse(
          success: true,
          data: data,
        );
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
      // JWT 토큰 가져오기
      final token = await AuthService.getToken();

      debugPrint('📥 GET /strokes?sessionId=$sessionId');

      // HTTP 요청
      final response = await http.get(
        Uri.parse('$baseUrl/strokes?sessionId=$sessionId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Request timeout');
        },
      );

      // 응답 처리
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final strokesJson = data['strokes'] as List;

        // JSON → Stroke 변환
        final strokes = strokesJson.map((json) {
          final points = (json['pts'] as List).map((p) =>
              DrawPoint(
                x: (p['x'] as num).toDouble(),
                y: (p['y'] as num).toDouble(),
              )
          ).toList();

          // 색상 파싱 (#RRGGBB → Color)
          final colorString = json['c'] as String;
          final colorInt = int.parse(colorString.replaceFirst('#', ''), radix: 16);
          final color = Color(0xFF000000 | colorInt);

          return Stroke(
            strokeId: json['sId'] as int,
            points: points,
            color: color,
            width: (json['w'] as num).toDouble(),
          );
        }).toList();

        debugPrint('✅ Loaded ${strokes.length} strokes');

        return ApiResponse<List<Stroke>>(
          success: true,
          data: strokes,
        );
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
  /// 로그인 (POST /auth/dev-login)
  /// ===============================
  static Future<ApiResponse<LoginResponse>> login({
    required String userId,
    required String role,
  }) async {
    try {
      debugPrint('📤 POST /auth/dev-login: userId=$userId, role=$role');

      final body = {
        'userId': userId,
        'role': role,
      };

      // HTTP 요청
      final response = await http.post(
        Uri.parse('$baseUrl/auth/dev-login'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Login timeout');
        },
      );

      // 응답 처리
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
  /// 교사 전용
  /// ===============================
  static Future<ApiResponse<EndSessionResponse>> endSession({
    required String sessionId,
  }) async {
    try {
      // JWT 토큰 가져오기
      final token = await AuthService.getToken();

      debugPrint('📤 POST /sessions/$sessionId/end');

      // HTTP 요청
      final response = await http.post(
        Uri.parse('$baseUrl/sessions/$sessionId/end'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Request timeout');
        },
      );

      // 응답 처리
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
  /// 읽기 전용 뷰어용
  /// ===============================
  static Future<ApiResponse<WhiteboardData>> getWhiteboard({
    required String sessionId,
  }) async {
    try {
      // JWT 토큰 가져오기
      final token = await AuthService.getToken();

      debugPrint('📤 GET /sessions/$sessionId/whiteboard');

      // HTTP 요청
      final response = await http.get(
        Uri.parse('$baseUrl/sessions/$sessionId/whiteboard'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Request timeout');
        },
      );

      // 응답 처리
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Whiteboard loaded: ${data['strokes']?.length ?? 0} strokes');

        return ApiResponse<WhiteboardData>(
          success: true,
          data: WhiteboardData(
            sessionId: data['sessionId'],
            readOnly: data['readOnly'] ?? true,
            strokes: (data['strokes'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ?? [],
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
  /// 자동 재join용 - 세션이 ACTIVE인지 확인
  /// ===============================
  static Future<ApiResponse<SessionStatus>> getSessionStatus({
    required String sessionId,
  }) async {
    try {
      // JWT 토큰 가져오기
      final token = await AuthService.getToken();

      debugPrint('📤 GET /sessions/$sessionId/status');

      // HTTP 요청
      final response = await http.get(
        Uri.parse('$baseUrl/sessions/$sessionId/status'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Request timeout');
        },
      );

      // 응답 처리
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
        // 세션이 없음
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
}

/// ===============================
/// 세션 종료 응답 모델
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

/// ===============================
/// 로그인 응답 모델
/// ===============================
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

/// ===============================
/// Whiteboard 데이터 모델
/// ===============================
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

/// ===============================
/// 세션 상태 모델
/// ===============================
class SessionStatus {
  final String sessionId;
  final String status;  // 'ACTIVE' | 'ARCHIVED' | 'UNKNOWN'

  SessionStatus({
    required this.sessionId,
    required this.status,
  });

  bool get isActive => status == 'ACTIVE';
  bool get isArchived => status == 'ARCHIVED';
}

/// ===============================
/// API 응답 모델
/// ===============================
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
/// 타임아웃 예외
/// ===============================
class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}