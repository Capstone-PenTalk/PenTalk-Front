import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _serverUrlOverride = String.fromEnvironment(
    'PENTALK_SERVER_URL',
    defaultValue: 'https://api.pentalkedu.com',
  );
  static const String _apiUrlOverride = String.fromEnvironment(
    'PENTALK_API_URL',
    defaultValue: '',
  );
  static const String _apiHostOverride = String.fromEnvironment(
    'PENTALK_API_HOST',
    defaultValue: '',
  );
  static const String _apiPortOverride = String.fromEnvironment(
    'PENTALK_API_PORT',
    defaultValue: '',
  );
  static const String _apiSchemeOverride = String.fromEnvironment(
    'PENTALK_API_SCHEME',
    defaultValue: 'https',
  );
  static const String _webUrlOverride = String.fromEnvironment(
    'PENTALK_WEB_URL',
    defaultValue: 'https://pentalkedu.com',
  );

  static const String _socketHostOverride = String.fromEnvironment(
    'PENTALK_SOCKET_HOST',
    defaultValue: '',
  );
  static const String _socketPortOverride = String.fromEnvironment(
    'PENTALK_SOCKET_PORT',
    defaultValue: '',
  );
  static const String _socketSchemeOverride = String.fromEnvironment(
    'PENTALK_SOCKET_SCHEME',
    defaultValue: 'https',
  );
  static const String _teacherSocketUrlOverride = String.fromEnvironment(
    'PENTALK_SOCKET_URL_TEACHER',
    defaultValue: '',
  );
  static const String _studentSocketUrlOverride = String.fromEnvironment(
    'PENTALK_SOCKET_URL_STUDENT',
    defaultValue: '',
  );
  static const bool _useServerLoginOverride = bool.fromEnvironment(
    'PENTALK_USE_SERVER_LOGIN',
    defaultValue: true,
  );
  static const bool _allowLocalPdfWorkspaceOverride = bool.fromEnvironment(
    'PENTALK_ALLOW_LOCAL_PDF_WORKSPACE',
    defaultValue: true,
  );
  static const bool _preferLocalPdfImportOverride = bool.fromEnvironment(
    'PENTALK_PREFER_LOCAL_PDF_IMPORT',
    defaultValue: false,
  );
  static const bool _enableNativeTeacherDrawingOverride = bool.fromEnvironment(
    'PENTALK_ENABLE_NATIVE_TEACHER_DRAWING',
    defaultValue: false,
  );
  static const bool _enableAutoLoginOverride = bool.fromEnvironment(
    'PENTALK_ENABLE_AUTO_LOGIN',
    defaultValue: false,
  );

  static bool get shouldUseServerLogin => _useServerLoginOverride;
  static bool get allowLocalPdfWorkspace => _allowLocalPdfWorkspaceOverride;
  static bool get preferLocalPdfImport => _preferLocalPdfImportOverride;
  static bool get enableNativeTeacherDrawing =>
      _enableNativeTeacherDrawingOverride;
  static bool get enableAutoLogin => _enableAutoLoginOverride;
  static String get googleOAuthStartUrl => '$apiBaseUrl/auth/google';
  static String get kakaoOAuthStartUrl => '$apiBaseUrl/auth/kakao';
  static String get webBaseUrl {
    if (kIsWeb) {
      final origin = Uri.base.origin.trim();
      if (origin.isNotEmpty && origin != 'null') {
        return _normalizeUrl(origin);
      }
    }
    return _normalizeUrl(_webUrlOverride.trim());
  }

  static bool get hasExplicitServerUrlConfig =>
      _serverUrlOverride.trim().isNotEmpty ||
      _apiUrlOverride.trim().isNotEmpty ||
      _apiHostOverride.trim().isNotEmpty ||
      _socketHostOverride.trim().isNotEmpty ||
      _teacherSocketUrlOverride.trim().isNotEmpty ||
      _studentSocketUrlOverride.trim().isNotEmpty;

  static String get apiBaseUrl {
    final runtimeApiUrl = _runtimeApiUrl;
    if (runtimeApiUrl != null) return runtimeApiUrl;

    if (_serverUrlOverride.trim().isNotEmpty) {
      return _normalizeUrl(_serverUrlOverride.trim());
    }
    if (_apiUrlOverride.trim().isNotEmpty) {
      return _normalizeUrl(_apiUrlOverride.trim());
    }
    if (_apiHostOverride.trim().isEmpty) {
      return _defaultLocalServerUrl;
    }
    return _buildUrl(
      scheme: _apiSchemeOverride,
      host: _apiHostOverride,
      port: _apiPortOverride,
    );
  }

  static String resolveSocketUrl({required bool isTeacher}) {
    final runtimeSocketUrl = _runtimeSocketUrl;
    if (runtimeSocketUrl != null) return runtimeSocketUrl;

    if (_serverUrlOverride.trim().isNotEmpty) {
      return _normalizeUrl(_serverUrlOverride.trim());
    }
    final explicit =
        (isTeacher ? _teacherSocketUrlOverride : _studentSocketUrlOverride)
            .trim();
    if (explicit.isNotEmpty) return _normalizeUrl(explicit);
    if (_socketHostOverride.trim().isEmpty) {
      return _defaultLocalServerUrl;
    }

    return _buildUrl(
      scheme: _socketSchemeOverride,
      host: _socketHostOverride,
      port: _socketPortOverride,
    );
  }

  static bool get shouldAvoidLoopbackServerOnDevice {
    if (kIsWeb) return false;
    final uri = Uri.tryParse(apiBaseUrl);
    final host = uri?.host.toLowerCase() ?? '';
    return host == '127.0.0.1' || host == 'localhost';
  }

  static String _buildUrl({
    required String scheme,
    required String host,
    required String port,
  }) {
    final normalizedHost = _sanitizeHost(
      host.trim().isNotEmpty ? host.trim() : _fallbackHost,
    );
    final normalizedPort = _sanitizePort(port.trim());
    final authority = normalizedPort.isEmpty
        ? normalizedHost
        : '$normalizedHost:$normalizedPort';
    return _normalizeUrl('${scheme.trim()}://$authority');
  }

  static String _sanitizeHost(String host) {
    return host.replaceAll(',', '.');
  }

  static String _sanitizePort(String port) {
    // 과거 잘못된 dart-define(PENTALK_*_PORT=300) 방어
    if (port == '300') return '3000';
    return port;
  }

  static String _normalizeUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }

  static String get _fallbackHost {
    if (kIsWeb) return 'localhost';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return '10.0.2.2';
      case TargetPlatform.iOS:
        return '127.0.0.1';
      default:
        return 'localhost';
    }
  }

  static String get _defaultLocalServerUrl {
    final host = _fallbackHost;
    return 'http://$host:3000';
  }

  static String? get _runtimeApiUrl {
    if (!kIsWeb) return null;
    final composed = _composeRuntimeServerUrl();
    if (composed != null) return composed;

    final apiUrl = Uri.base.queryParameters['apiUrl']?.trim();
    if (apiUrl != null && apiUrl.isNotEmpty) return _normalizeUrl(apiUrl);

    final serverUrl = Uri.base.queryParameters['serverUrl']?.trim();
    if (serverUrl != null && serverUrl.isNotEmpty) {
      return _normalizeUrl(serverUrl);
    }
    return null;
  }

  static String? get _runtimeSocketUrl {
    if (!kIsWeb) return null;
    final composed = _composeRuntimeServerUrl();
    if (composed != null) return composed;

    final socketUrl = Uri.base.queryParameters['socketUrl']?.trim();
    if (socketUrl != null && socketUrl.isNotEmpty) {
      return _normalizeUrl(socketUrl);
    }

    final serverUrl = Uri.base.queryParameters['serverUrl']?.trim();
    if (serverUrl != null && serverUrl.isNotEmpty) {
      return _normalizeUrl(serverUrl);
    }
    return null;
  }

  static String? _composeRuntimeServerUrl() {
    final query = Uri.base.queryParameters;
    final host = query['serverHost']?.trim();
    if (host == null || host.isEmpty) return null;
    final port = query['serverPort']?.trim();
    final scheme = (query['serverScheme']?.trim().isNotEmpty == true)
        ? query['serverScheme']!.trim()
        : 'https';

    final authority = (port == null || port.isEmpty)
        ? _sanitizeHost(host)
        : '${_sanitizeHost(host)}:${_sanitizePort(port)}';
    return _normalizeUrl('$scheme://$authority');
  }
}
