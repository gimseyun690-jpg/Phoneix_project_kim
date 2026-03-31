class AppConfig {
  static const bool useMockApi =
      bool.fromEnvironment('USE_MOCK_API', defaultValue: true);
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api/v1',
  );
}
