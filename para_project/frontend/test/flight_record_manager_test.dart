import 'package:flutter_test/flutter_test.dart';
import 'package:paragliding_mvp_frontend/core/flight_record_manager.dart';
import 'package:paragliding_mvp_frontend/models/app_models.dart';

void main() {
  group('비행 기록 공유 데이터', () {
    final session = FlightSession(
      id: 'session-1',
      userId: 2,
      startedAt: DateTime(2026, 3, 31, 9, 0),
      endedAt: DateTime(2026, 3, 31, 10, 15),
      status: FlightSessionStatus.completed,
      siteId: 4,
      siteName: '문경 활공랜드',
      region: '경북 문경',
      durationSeconds: 4500,
      totalDistanceMeters: 12850,
      minAltitudeMeters: 152,
      maxAltitudeMeters: 812,
      avgSpeedMps: 2.9,
      maxSpeedMps: 8.4,
      memo: '오전 약한 계곡풍에서 안정적으로 비행했습니다.',
      trackPointCount: 2,
      lastLatitude: 36.586,
      lastLongitude: 128.186,
      lastAccuracyMeters: 6,
      createdAt: DateTime(2026, 3, 31, 9, 0),
      updatedAt: DateTime(2026, 3, 31, 10, 15),
    );

    final points = [
      FlightTrackPoint(
        id: 'point-1',
        sessionId: 'session-1',
        timestamp: DateTime(2026, 3, 31, 9, 0),
        latitude: 36.581,
        longitude: 128.181,
        altitude: 152,
        speed: 0.0,
        heading: 214,
        accuracy: 8,
      ),
      FlightTrackPoint(
        id: 'point-2',
        sessionId: 'session-1',
        timestamp: DateTime(2026, 3, 31, 10, 15),
        latitude: 36.586,
        longitude: 128.186,
        altitude: 812,
        speed: 7.8,
        heading: 228,
        accuracy: 6,
      ),
    ];

    test('공유 요약에 핵심 항목이 포함된다', () {
      final manager = FlightRecordManager();
      final summary = manager.buildShareSummary(session);

      expect(summary, contains('비행 날짜: 2026-03-31'));
      expect(summary, contains('지역/비행장: 경북 문경 / 문경 활공랜드'));
      expect(summary, contains('총 거리: 12.8km'));
      expect(summary, contains('최고 고도: 812m'));
      expect(summary, contains('메모: 오전 약한 계곡풍에서 안정적으로 비행했습니다.'));
    });

    test('내보내기 데이터에 세션과 트랙 포인트가 포함된다', () {
      final manager = FlightRecordManager();
      final payload = manager.buildExportPayload(
        FlightSessionDetail(session: session, points: points),
      );

      expect(payload['schema_version'], 1);
      expect(payload['session'], isA<Map<String, dynamic>>());
      expect((payload['track_points'] as List<dynamic>).length, 2);
      expect((payload['summary'] as String), contains('비행 기록 공유'));
    });
  });
}
