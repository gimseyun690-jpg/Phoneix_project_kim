import 'package:flutter_test/flutter_test.dart';
import 'package:paragliding_mvp_frontend/core/korea_weather_map_service.dart';
import 'package:paragliding_mvp_frontend/core/live_weather_service.dart';
import 'package:paragliding_mvp_frontend/models/app_models.dart';

class _FakeLiveWeatherService extends LiveWeatherService {
  _FakeLiveWeatherService({
    required this.snapshots,
    required this.forecasts,
  });

  final List<LiveWeatherSnapshot> snapshots;
  final List<List<LiveWeatherForecastItem>> forecasts;
  int weatherCalls = 0;
  int areaLabelCalls = 0;
  int forecastCalls = 0;

  @override
  Future<LiveWeatherSnapshot> getCurrentWeather({
    required double latitude,
    required double longitude,
    SiteSummary? selectedSite,
  }) async {
    weatherCalls += 1;
    final index = weatherCalls - 1;
    return snapshots[index < snapshots.length ? index : snapshots.length - 1];
  }

  @override
  Future<List<LiveWeatherForecastItem>> getShortTermForecast({
    required double latitude,
    required double longitude,
    SiteSummary? selectedSite,
    int count = 6,
  }) async {
    forecastCalls += 1;
    final index = forecastCalls - 1;
    return forecasts[index < forecasts.length ? index : forecasts.length - 1];
  }

  @override
  Future<String?> resolveAreaLabel({
    required double latitude,
    required double longitude,
  }) async {
    areaLabelCalls += 1;
    return '경기 양평';
  }

  @override
  void dispose() {}
}

void main() {
  LiveWeatherSnapshot buildSnapshot(int hour) {
    return LiveWeatherSnapshot(
      observedAt: DateTime(2026, 3, 31, hour),
      temperatureCelsius: 12.0 + hour,
      windSpeedMps: 4.0 + hour,
      windDirection: 200 + hour,
      summary: '테스트 날씨 $hour',
      sourceLabel: '테스트',
    );
  }

  List<LiveWeatherForecastItem> buildForecast(int startHour) {
    return List.generate(
      3,
      (index) => LiveWeatherForecastItem(
        time: DateTime(2026, 3, 31, startHour + index),
        temperatureCelsius: 10 + index.toDouble(),
        windSpeedMps: 3 + index.toDouble(),
        windDirection: 180 + (index * 10),
        precipitationMm: index == 0 ? 0 : 0.1 * index,
      ),
    );
  }

  SiteSummary buildSite() {
    return SiteSummary(
      id: 1,
      name: '양평 패러밸리',
      region: '경기 양평',
      difficulty: 'beginner',
      shortDescription: '테스트 비행장',
      beginnerAllowed: true,
      weather: WeatherSnapshot(
        observedAt: DateTime(2026, 3, 31, 9),
        averageWindSpeed: 4.1,
        windDirection: 215,
        gustSpeed: 6.2,
        summary: '기본 요약',
        hourlyForecast: const [],
      ),
      assessment: const Assessment(
        score: 90,
        status: FlightStatus.good,
        reasons: ['테스트'],
        summaryText: '비행 가능',
      ),
    );
  }

  group('한국 지도 날씨 서비스', () {
    test('강제 새로고침은 사이트 캐시를 우회한다', () async {
      final fakeService = _FakeLiveWeatherService(
        snapshots: [
          buildSnapshot(10),
          buildSnapshot(11),
        ],
        forecasts: [
          buildForecast(10),
        ],
      );
      final service = KoreaWeatherMapService(liveWeatherService: fakeService);
      final site = buildSite();

      final first = await service.loadSiteSnapshots([site]);
      final second = await service.loadSiteSnapshots([site]);
      final third = await service.loadSiteSnapshots([site], forceRefresh: true);

      expect(first.single.weather.observedAt.hour, 10);
      expect(second.single.weather.observedAt.hour, 10);
      expect(third.single.weather.observedAt.hour, 11);
      expect(fakeService.weatherCalls, 2);
    });

    test('강제 새로고침은 지역 캐시를 우회한다', () async {
      final fakeService = _FakeLiveWeatherService(
        snapshots: [
          buildSnapshot(12),
          buildSnapshot(13),
        ],
        forecasts: [
          buildForecast(12),
        ],
      );
      final service = KoreaWeatherMapService(liveWeatherService: fakeService);
      final siteSnapshots = await service.loadSiteSnapshots([buildSite()]);

      final first = await service.loadAreaWeather(
        latitude: 37.54,
        longitude: 127.51,
        siteSnapshots: siteSnapshots,
      );
      final second = await service.loadAreaWeather(
        latitude: 37.54,
        longitude: 127.51,
        siteSnapshots: siteSnapshots,
      );
      final third = await service.loadAreaWeather(
        latitude: 37.54,
        longitude: 127.51,
        siteSnapshots: siteSnapshots,
        forceRefresh: true,
      );

      expect(first.weather.observedAt.hour, 13);
      expect(second.weather.observedAt.hour, 13);
      expect(third.weather.observedAt.hour, 13);
      expect(fakeService.weatherCalls, 3);
      expect(fakeService.areaLabelCalls, 2);
    });

    test('강제 새로고침은 단기 예보 캐시를 우회한다', () async {
      final fakeService = _FakeLiveWeatherService(
        snapshots: [
          buildSnapshot(14),
        ],
        forecasts: [
          buildForecast(14),
          buildForecast(17),
        ],
      );
      final service = KoreaWeatherMapService(liveWeatherService: fakeService);
      final site = buildSite();

      final first = await service.loadShortTermForecast(
        latitude: 37.54,
        longitude: 127.51,
        selectedSite: site,
      );
      final second = await service.loadShortTermForecast(
        latitude: 37.54,
        longitude: 127.51,
        selectedSite: site,
      );
      final third = await service.loadShortTermForecast(
        latitude: 37.54,
        longitude: 127.51,
        selectedSite: site,
        forceRefresh: true,
      );

      expect(first.first.time.hour, 14);
      expect(second.first.time.hour, 14);
      expect(third.first.time.hour, 17);
      expect(fakeService.forecastCalls, 2);
    });
  });
}
