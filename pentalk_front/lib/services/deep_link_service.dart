import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';

import '../config/app_config.dart';

/// ===============================
/// Deep Link 처리 서비스
/// pentalk://material/{sessionId}/{materialId}
/// ===============================
class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final _appLinks = AppLinks();

  /// Deep Link 데이터
  String? initialLink;

  /// 앱 시작 시 초기 링크 확인
  Future<String?> getInitialLink() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) {
        debugPrint('📱 Initial Deep Link: $uri');
        initialLink = uri.toString();
        return initialLink;
      }
    } catch (e) {
      debugPrint('❌ Failed to get initial link: $e');
    }
    return null;
  }

  /// 백그라운드에서 복귀 시 링크 감지
  Stream<Uri> get uriLinkStream => _appLinks.uriLinkStream;

  /// URL 파싱: pentalk://join/{sessionId}, https://도메인/join/{sessionId}
  String? parseJoinSessionId(String uriString) {
    try {
      final uri = Uri.parse(uriString);

      if (uri.scheme == 'pentalk' && uri.host == 'join') {
        final sessionId = uri.pathSegments.isNotEmpty
            ? uri.pathSegments.first.trim()
            : '';
        return sessionId.isEmpty ? null : sessionId;
      }

      final querySessionId = uri.queryParameters['sessionId']?.trim();
      if (querySessionId != null && querySessionId.isNotEmpty) {
        return querySessionId;
      }

      final pathSegments = uri.pathSegments;
      if (pathSegments.length >= 2 && pathSegments[0] == 'join') {
        final sessionId = pathSegments[1].trim();
        return sessionId.isEmpty ? null : sessionId;
      }
    } catch (e) {
      debugPrint('❌ Failed to parse join link: $e');
    }
    return null;
  }

  String? parseJoinClassId(String uriString) {
    try {
      final uri = Uri.parse(uriString);
      final classId = uri.queryParameters['classId']?.trim();
      return (classId == null || classId.isEmpty) ? null : classId;
    } catch (e) {
      debugPrint('❌ Failed to parse join classId: $e');
    }
    return null;
  }

  String? parseJoinMaterialId(String uriString) {
    try {
      final uri = Uri.parse(uriString);
      final materialId = uri.queryParameters['materialId']?.trim();
      return (materialId == null || materialId.isEmpty) ? null : materialId;
    } catch (e) {
      debugPrint('❌ Failed to parse join materialId: $e');
    }
    return null;
  }

  /// URL 파싱: pentalk://material/{sessionId}/{materialId}
  Map<String, String>? parseMaterialLink(String uriString) {
    try {
      final uri = Uri.parse(uriString);

      // scheme 확인
      if (uri.scheme != 'pentalk') {
        debugPrint('⚠️ Invalid scheme: ${uri.scheme}');
        return null;
      }

      // path 파싱: /material/s1/m1
      final pathSegments = uri.pathSegments;

      if (pathSegments.isEmpty) {
        debugPrint('⚠️ Empty path');
        return null;
      }

      // material 링크인지 확인
      if (pathSegments[0] == 'material' && pathSegments.length >= 3) {
        final sessionId = pathSegments[1];
        final materialId = pathSegments[2];

        debugPrint('✅ Parsed: sessionId=$sessionId, materialId=$materialId');

        return {'sessionId': sessionId, 'materialId': materialId};
      }

      debugPrint('⚠️ Unknown path: ${uri.path}');
      return null;
    } catch (e) {
      debugPrint('❌ Failed to parse link: $e');
      return null;
    }
  }

  /// Deep Link URL 생성
  String generateMaterialLink(String sessionId, String materialId) {
    return 'pentalk://material/$sessionId/$materialId';
  }

  String generateJoinDeepLink(String sessionId) {
    return 'pentalk://join/$sessionId';
  }

  String generateJoinWebLink(
    String sessionId, {
    String? baseUrl,
    String? classId,
    String? materialId,
  }) {
    final normalizedBaseUrl = (baseUrl ?? AppConfig.apiBaseUrl).trim();
    final uri = Uri.parse(
      '${normalizedBaseUrl.replaceFirst(RegExp(r'/$'), '')}/join/$sessionId',
    );
    final queryParameters = <String, String>{};
    final trimmedClassId = classId?.trim();
    if (trimmedClassId != null && trimmedClassId.isNotEmpty) {
      queryParameters['classId'] = trimmedClassId;
    }
    final trimmedMaterialId = materialId?.trim();
    if (trimmedMaterialId != null && trimmedMaterialId.isNotEmpty) {
      queryParameters['materialId'] = trimmedMaterialId;
    }
    if (queryParameters.isEmpty) return uri.toString();
    return uri.replace(queryParameters: queryParameters).toString();
  }

  /// Deep Link를 웹 링크로도 변환 (선택사항)
  String generateWebLink(String sessionId, String materialId) {
    return 'https://pentalk.app/material/$sessionId/$materialId';
  }
}
