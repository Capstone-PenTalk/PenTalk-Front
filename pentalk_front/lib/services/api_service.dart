import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
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
        'sId': stroke.id,
        'pts': stroke.points.map((p) => {
          'x': p.x,
          'y': p.y,
        }).toList(),
        'c': stroke.color,
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
              DrawPoint(p['x'], p['y'])
          ).toList();

          return Stroke(
            id: json['sId'],
            points: points,
            color: json['c'],
            width: json['w'],
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