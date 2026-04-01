import 'package:flutter_test/flutter_test.dart';
import 'package:paragliding_mvp_frontend/core/flight_analysis_summary.dart';
import 'package:paragliding_mvp_frontend/models/app_models.dart';

void main() {
  group('비행 분석 요약 계산', () {
    test('최고 고도와 핵심 시점을 계산한다', () {
      final startedAt = DateTime(2026, 4, 1, 9, 0);
      final detail = FlightSessionDetail(
        session: FlightSession(
          id: 'session-1',
          userId: 7,
          startedAt: startedAt,
          endedAt: DateTime(2026, 4, 1, 9, 45),
          status: FlightSessionStatus.completed,
          siteId: 4,
          siteName: '문경 활공랜드',
          region: '경북 문경',
          durationSeconds: 2700,
          totalDistanceMeters: 12400,
          minAltitudeMeters: 220,
          maxAltitudeMeters: 980,
          avgSpeedMps: 4.2,
          maxSpeedMps: 13.8,
          memo: '상승이 좋은 편이었습니다.',
          trackPointCount: 4,
          pausedDurationSeconds: 0,
          lastLatitude: 36.586,
          lastLongitude: 128.186,
          lastAccuracyMeters: 7,
          createdAt: startedAt,
          updatedAt: DateTime(2026, 4, 1, 9, 45),
        ),
        points: [
          FlightTrackPoint(
            id: 'p1',
            sessionId: 'session-1',
            timestamp: startedAt,
            latitude: 36.580,
            longitude: 128.180,
            altitude: 220,
            speed: 0.0,
            heading: 180,
            accuracy: 8,
          ),
          FlightTrackPoint(
            id: 'p2',
            sessionId: 'session-1',
            timestamp: DateTime(2026, 4, 1, 9, 10),
            latitude: 36.582,
            longitude: 128.182,
            altitude: 640,
            speed: 6.4,
            heading: 196,
            accuracy: 7,
          ),
          FlightTrackPoint(
            id: 'p3',
            sessionId: 'session-1',
            timestamp: DateTime(2026, 4, 1, 9, 22),
            latitude: 36.585,
            longitude: 128.185,
            altitude: 980,
            speed: 8.1,
            heading: 205,
            accuracy: 6,
          ),
          FlightTrackPoint(
            id: 'p4',
            sessionId: 'session-1',
            timestamp: DateTime(2026, 4, 1, 9, 45),
            latitude: 36.586,
            longitude: 128.186,
            altitude: 410,
            speed: 5.3,
            heading: 220,
            accuracy: 7,
          ),
        ],
      );

      final summary = FlightAnalysisSummary.fromDetail(detail);

      expect(summary.highestPoint?.altitude, 980);
      expect(summary.keyMoments.length, 4);
      expect(summary.overview, contains('12.4km'));
      expect(summary.insights.first.title, '최고 고도 시점');
      expect(summary.totalAltitudeGainMeters, greaterThan(700));
    });
  });
}
