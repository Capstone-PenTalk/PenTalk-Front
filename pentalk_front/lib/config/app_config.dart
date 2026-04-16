import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _defaultHost =
      'pentalk-server-production.up.railway.app';

  static const String _apiUrlOverride = String.fromEnvironment(
    'PENTALK_API_URL',
    defaultValue: '',
  );
  static const String _apiHostOverride = String.fromEnvironment(
    'PENTALK_API_HOST',
    defaultValue: _defaultHost,
  );
  static const String _apiPortOverride = String.fromEnvironment(
    'PENTALK_API_PORT',
    defaultValue: '',
  );
  static const String _apiSchemeOverride = String.fromEnvironment(
    'PENTALK_API_SCHEME',
    defaultValue: 'https',
  );

  static const String _socketHostOverride = String.fromEnvironment(
    'PENTALK_SOCKET_HOST',
    defaultValue: _defaultHost,
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

  static String get apiBaseUrl {
    if (_apiUrlOverride.trim().isNotEmpty) {
      return _normalizeUrl(_apiUrlOverride.trim());
    }
    return _buildUrl(
      scheme: _apiSchemeOverride,
      host: _apiHostOverride,
      port: _apiPortOverride,
    );
  }

  static String resolveSocketUrl({required bool isTeacher}) {
    final explicit =
        (isTeacher ? _teacherSocketUrlOverride : _studentSocketUrlOverride)
            .trim();
    if (explicit.isNotEmpty) return _normalizeUrl(explicit);

    return _buildUrl(
      scheme: _socketSchemeOverride,
      host: _socketHostOverride,
      port: _socketPortOverride,
    );
  }

  static String _buildUrl({
    required String scheme,
    required String host,
    required String port,
  }) {
    final normalizedHost = host.trim().isNotEmpty ? host.trim() : _fallbackHost;
    final normalizedPort = port.trim();
    final authority = normalizedPort.isEmpty
        ? normalizedHost
        : '$normalizedHost:$normalizedPort';
    return _normalizeUrl('${scheme.trim()}://$authority');
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
}
