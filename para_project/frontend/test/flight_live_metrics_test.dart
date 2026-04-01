import 'package:flutter_test/flutter_test.dart';
import 'package:paragliding_mvp_frontend/core/flight_live_metrics.dart';
import 'package:paragliding_mvp_frontend/models/app_models.dart';

void main() {
  group('실시간 비행 지표 계산', () {
    test('일시정지 상태에서는 저장된 경과 시간이 유지된다', () {
      final startedAt = DateTime(2026, 4, 1, 9, 0);
      final session = FlightSession(
        id: 'paused-session',
        userId: 1,
        startedAt: startedAt,
        endedAt: null,
        status: FlightSessionStatus.paused,
        siteId: 1,
        siteName: '문경 활공랜드',
        region: '경북 문경',
        durationSeconds: 1800,
        totalDistanceMeters: 5400,
        minAltitudeMeters: 220,
        maxAltitudeMeters: 860,
        avgSpeedMps: 3.2,
        maxSpeedMps: 10.4,
        memo: '',
        trackPointCount: 3,
        pausedDurationSeconds: 300,
        pausedAt: DateTime(2026, 4, 1, 9, 35),
        lastLatitude: 36.58,
        lastLongitude: 128.18,
        lastAccuracyMeters: 8,
        createdAt: startedAt,
        updatedAt: DateTime(2026, 4, 1, 9, 35),
      );

      final metrics = FlightLiveMetrics.fromSession(
        session: session,
        points: const [],
        now: DateTime(2026, 4, 1, 10, 10),
      );

      expect(metrics.elapsed, const Duration(minutes: 30));
    });

    test('기록 중 상태에서는 누적 일시정지 시간을 제외하고 경과 시간을 계산한다', () {
      final startedAt = DateTime(2026, 4, 1, 9, 0);
      final session = FlightSession(
        id: 'recording-session',
        userId: 1,
        startedAt: startedAt,
        endedAt: null,
        status: FlightSessionStatus.recording,
        siteId: 1,
        siteName: '문경 활공랜드',
        region: '경북 문경',
        durationSeconds: 0,
        totalDistanceMeters: 6400,
        minAltitudeMeters: 220,
        maxAltitudeMeters: 1020,
        avgSpeedMps: 3.8,
        maxSpeedMps: 11.2,
        memo: '',
        trackPointCount: 4,
        pausedDurationSeconds: 420,
        pausedAt: null,
        lastLatitude: 36.58,
        lastLongitude: 128.18,
        lastAccuracyMeters: 7,
        createdAt: startedAt,
        updatedAt: DateTime(2026, 4, 1, 9, 47),
      );

      final metrics = FlightLiveMetrics.fromSession(
        session: session,
        points: const [],
        now: DateTime(2026, 4, 1, 10, 0),
      );

      expect(metrics.elapsed, const Duration(minutes: 53));
    });
  });
}
