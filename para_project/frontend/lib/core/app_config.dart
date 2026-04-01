import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _useMockApiOverride = String.fromEnvironment(
    'USE_MOCK_API',
    defaultValue: '',
  );

  static bool get useMockApi {
    if (_useMockApiOverride.isNotEmpty) {
      return _useMockApiOverride.toLowerCase() == 'true';
    }
    return !kReleaseMode;
  }

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api/v1',
  );
}
