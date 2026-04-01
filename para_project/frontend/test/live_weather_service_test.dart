import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:paragliding_mvp_frontend/core/live_weather_service.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.body);

  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stream = Stream<List<int>>.fromIterable([utf8.encode(body)]);
    return http.StreamedResponse(stream, 200);
  }
}

void main() {
  test('장기 예보를 16일 범위 구조로 파싱한다', () async {
    final service = LiveWeatherService(
      client: _FakeClient(jsonEncode({
        'daily': {
          'time': ['2026-04-01', '2026-04-02', '2026-04-03'],
          'temperature_2m_min': [7.0, 8.0, 9.5],
          'temperature_2m_max': [17.0, 18.5, 19.0],
          'wind_speed_10m_max': [4.2, 6.1, 8.4],
          'wind_gusts_10m_max': [6.0, 8.8, 11.2],
          'wind_direction_10m_dominant': [180, 205, 240],
          'precipitation_sum': [0.0, 1.8, 6.2],
          'precipitation_probability_max': [10, 45, 80],
          'weather_code': [1, 3, 61],
        },
      })),
    );

    final items = await service.getExtendedForecast(
      latitude: 36.58,
      longitude: 128.18,
      days: 16,
    );

    expect(items, hasLength(3));
    expect(items.first.minTemperatureCelsius, 7.0);
    expect(items.first.maxTemperatureCelsius, 17.0);
    expect(items[1].windSpeedMps, 6.1);
    expect(items[1].precipitationProbability, 45);
    expect(items.last.gustSpeedMps, 11.2);
    expect(items.last.summaryText, '강수 가능성 높음');

    service.dispose();
  });

  test('날씨 해석 경고에 돌풍과 풍향 변화가 반영된다', () {
    final service = LiveWeatherService();
    final weather = LiveWeatherSnapshot(
      observedAt: DateTime(2026, 4, 1, 10),
      temperatureCelsius: 13,
      windSpeedMps: 4.1,
      windDirection: 200,
      weatherCode: 2,
      summary: '대체로 맑음',
      sourceLabel: '사이트 기준',
    );
    final forecast = [
      LiveWeatherForecastItem(
        time: DateTime(2026, 4, 1, 10),
        windSpeedMps: 4.1,
        windDirection: 180,
        gustSpeedMps: 8.4,
        precipitationMm: 0,
        weatherCode: 2,
      ),
      LiveWeatherForecastItem(
        time: DateTime(2026, 4, 1, 13),
        windSpeedMps: 4.6,
        windDirection: 285,
        gustSpeedMps: 8.8,
        precipitationMm: 0,
        weatherCode: 3,
      ),
    ];

    final alerts = service.buildOperationalAlerts(
      weather: weather,
      forecast: forecast,
      selectedForecast: forecast.first,
    );

    expect(alerts.map((item) => item.label), contains('돌풍 가능성'));
    expect(alerts.map((item) => item.label), contains('풍향 변화 주의'));
    service.dispose();
  });
}
