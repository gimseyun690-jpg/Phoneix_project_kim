import 'package:flutter_test/flutter_test.dart';
import 'package:paragliding_mvp_frontend/core/korea_flight_guide.dart';
import 'package:paragliding_mvp_frontend/models/app_models.dart';

void main() {
  group('한국형 참고 구역 판정', () {
    const guide = KoreaFlightGuide();

    test('등록 비행장 반경 안에서는 비행 가능으로 본다', () {
      final selectedSite = SiteSummary(
        id: 4,
        name: '문경 활공랜드',
        region: '경북 문경',
        difficulty: 'advanced',
        shortDescription: '산악 지형 활공장',
        beginnerAllowed: false,
        weather: WeatherSnapshot(
          observedAt: DateTime(2026, 3, 31, 10),
          averageWindSpeed: 4.2,
          windDirection: 220,
          gustSpeed: 6.5,
          summary: '안정적인 계곡풍',
          hourlyForecast: [],
        ),
        assessment: const Assessment(
          score: 82,
          status: FlightStatus.good,
          reasons: ['바람 안정'],
          summaryText: '비행 가능',
        ),
      );

      final advisory = guide.assess(
        latitude: 36.5862,
        longitude: 128.1861,
        selectedSite: selectedSite,
      );

      expect(advisory.status, KoreaZoneStatus.flyable);
      expect(advisory.confidence, KoreaZoneConfidence.curated);
      expect(advisory.nearbySite?.name, '문경 활공랜드');
    });

    test('등록 비행장과 충분히 멀면 제한 가능성 있음으로 본다', () {
      final advisory = guide.assess(
        latitude: 35.1796,
        longitude: 129.0756,
      );

      expect(advisory.status, KoreaZoneStatus.potentiallyRestricted);
      expect(advisory.confidence, KoreaZoneConfidence.inferred);
    });
  });
}
