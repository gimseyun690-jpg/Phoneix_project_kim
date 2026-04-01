import 'package:flutter_test/flutter_test.dart';
import 'package:paragliding_mvp_frontend/core/kmz_site_catalog.dart';
import 'package:paragliding_mvp_frontend/core/live_weather_service.dart';

void main() {
  test('KMZ 활공장 데이터는 사이트 상세 모델로 변환된다', () {
    final site = ImportedParaglidingSite.fromJson({
      'source_id': 'kmz-site-001',
      'order': 0,
      'name': '문경 활공장',
      'region_hint': '경북 문경',
      'latitude': 36.58,
      'longitude': 128.18,
      'site_type': 'takeoff',
      'summary_line': '경북 문경 문경 활공장 - 서풍 / 북서풍',
      'description_text': '문경 활공장 설명',
      'wind_note': '서풍 / 북서풍',
      'image_url': null,
      'windguru_url': null,
      'windy_url': null,
      'kma_forecast_url': null,
      'aws_observation_url': null,
      'station_label': '문경',
      'folder_name': '제목없는 레이어',
      'style_id': 'icon-22',
    });

    final weather = LiveWeatherSnapshot(
      observedAt: DateTime(2026, 4, 1, 10),
      temperatureCelsius: 14,
      windSpeedMps: 4.2,
      windDirection: 300,
      summary: '대체로 맑음',
      sourceLabel: '좌표 기준 실황',
    );
    final forecast = [
      LiveWeatherForecastItem(
        time: DateTime(2026, 4, 1, 10),
        temperatureCelsius: 14,
        windSpeedMps: 4.2,
        windDirection: 300,
        gustSpeedMps: 6.1,
        precipitationMm: 0,
        summaryText: '대체로 맑음',
      ),
    ];

    final detail = site.toSiteDetail(weather: weather, forecast: forecast);
    final quality = site.dataQuality;

    expect(detail.site.name, '문경 활공장');
    expect(detail.site.region, '경북 문경');
    expect(detail.allowedDirectionRange, '서풍 / 북서풍');
    expect(detail.site.weather.gustSpeed, 6.1);
    expect(detail.site.assessment.reasons, isNotEmpty);
    expect(quality.label, '정보 충분');
    expect(quality.missingFields, isEmpty);
  });

  test('결측 정보가 많으면 품질 상태를 보수적으로 표시한다', () {
    final site = ImportedParaglidingSite.fromJson({
      'source_id': 'kmz-site-002',
      'order': 1,
      'name': '임시 이륙장',
      'region_hint': '',
      'latitude': 0,
      'longitude': 0,
      'site_type': 'takeoff',
      'summary_line': '',
      'description_text': '',
      'wind_note': '',
    });

    final quality = site.dataQuality;

    expect(quality.label, '정보 보완 필요');
    expect(quality.missingFields, contains('좌표 미등록'));
    expect(quality.missingFields, contains('대표 풍향 정보 없음'));
    expect(quality.missingFields, contains('설명 미등록'));
  });
}
