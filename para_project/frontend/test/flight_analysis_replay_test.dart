import 'package:flutter_test/flutter_test.dart';

import 'package:paragliding_mvp_frontend/core/flight_analysis_replay.dart';
import 'package:paragliding_mvp_frontend/models/app_models.dart';

void main() {
  group('FlightReplayData', () {
    test('실제 기록 점을 바탕으로 진행률과 최고 고도 지점을 계산한다', () {
      final replay = FlightReplayData.fromPoints([
        _point(
          index: 0,
          latitude: 36.6000,
          longitude: 128.1000,
          altitude: 120,
          timestamp: DateTime(2026, 4, 1, 9, 0, 0),
          speed: 0,
        ),
        _point(
          index: 1,
          latitude: 36.6004,
          longitude: 128.1003,
          altitude: 145,
          timestamp: DateTime(2026, 4, 1, 9, 1, 0),
          speed: 4.8,
        ),
        _point(
          index: 2,
          latitude: 36.6010,
          longitude: 128.1010,
          altitude: 265,
          timestamp: DateTime(2026, 4, 1, 9, 2, 0),
          speed: 7.4,
        ),
        _point(
          index: 3,
          latitude: 36.6015,
          longitude: 128.1014,
          altitude: 190,
          timestamp: DateTime(2026, 4, 1, 9, 3, 0),
          speed: 5.4,
        ),
        _point(
          index: 4,
          latitude: 36.6020,
          longitude: 128.1020,
          altitude: 160,
          timestamp: DateTime(2026, 4, 1, 9, 4, 0),
          speed: 2.2,
        ),
      ]);

      expect(replay.frames, hasLength(5));
      expect(replay.totalDuration, const Duration(minutes: 4));
      expect(replay.totalDistanceMeters, greaterThan(0));
      expect(replay.frames.first.progress, 0);
      expect(replay.frames.last.progress, 1);
      expect(replay.highestFrameIndex, 2);
      expect(replay.highestFrame?.sourceIndex, 2);
      expect(replay.frames[2].displayAltitudeMeters, lessThan(265));
      expect(replay.frames[2].displayAltitudeMeters, greaterThan(170));
      expect(replay.frames.first.elapsedDuration, Duration.zero);
      expect(replay.frames.last.elapsedDuration, const Duration(minutes: 4));
      expect(replay.frames.first.altitudeFromStartMeters, closeTo(0, 0.1));
      expect(replay.frames[2].altitudeFromStartMeters, greaterThan(40));
      expect(replay.frames[2].verticalSpeedMps, greaterThan(0));
      expect(replay.takeoffFrameIndex, greaterThanOrEqualTo(1));
      expect(replay.landingFrameIndex, lessThan(replay.frames.length));
    });

    test('재생 시각과 진행률로 가까운 프레임을 찾는다', () {
      final replay = FlightReplayData.fromPoints([
        _point(
          index: 0,
          latitude: 37.0000,
          longitude: 127.0000,
          altitude: 110,
          timestamp: DateTime(2026, 4, 1, 10, 0, 0),
        ),
        _point(
          index: 1,
          latitude: 37.0005,
          longitude: 127.0005,
          altitude: 125,
          timestamp: DateTime(2026, 4, 1, 10, 0, 30),
        ),
        _point(
          index: 2,
          latitude: 37.0010,
          longitude: 127.0010,
          altitude: 140,
          timestamp: DateTime(2026, 4, 1, 10, 1, 0),
        ),
      ]);

      expect(
        replay.nearestFrameIndex(DateTime(2026, 4, 1, 10, 0, 28)),
        1,
      );
      expect(replay.indexForProgress(0.49), 1);
      expect(replay.indexForProgress(1.0), 2);
    });

    test('지속 상승 구간을 써멀 추정으로 묶는다', () {
      final replay = FlightReplayData.fromPoints([
        _point(
          index: 0,
          latitude: 37.1000,
          longitude: 127.1000,
          altitude: 100,
          timestamp: DateTime(2026, 4, 1, 8, 0, 0),
          speed: 1.2,
        ),
        _point(
          index: 1,
          latitude: 37.1002,
          longitude: 127.1002,
          altitude: 135,
          timestamp: DateTime(2026, 4, 1, 8, 0, 25),
          speed: 4.6,
        ),
        _point(
          index: 2,
          latitude: 37.1005,
          longitude: 127.1005,
          altitude: 175,
          timestamp: DateTime(2026, 4, 1, 8, 0, 50),
          speed: 5.0,
        ),
        _point(
          index: 3,
          latitude: 37.1008,
          longitude: 127.1009,
          altitude: 220,
          timestamp: DateTime(2026, 4, 1, 8, 1, 15),
          speed: 5.4,
        ),
        _point(
          index: 4,
          latitude: 37.1012,
          longitude: 127.1013,
          altitude: 228,
          timestamp: DateTime(2026, 4, 1, 8, 1, 40),
          speed: 4.8,
        ),
        _point(
          index: 5,
          latitude: 37.1017,
          longitude: 127.1019,
          altitude: 210,
          timestamp: DateTime(2026, 4, 1, 8, 2, 5),
          speed: 3.2,
        ),
      ]);

      expect(replay.thermalSegments, isNotEmpty);
      expect(replay.thermalSegments.first.label, '써멀 1');
      expect(replay.thermalSegments.first.altitudeGainMeters, greaterThan(30));
      expect(
        replay.thermalSegments.first.duration,
        greaterThan(const Duration(seconds: 20)),
      );
    });
  });
}

FlightTrackPoint _point({
  required int index,
  required double latitude,
  required double longitude,
  required double altitude,
  required DateTime timestamp,
  double? speed,
}) {
  return FlightTrackPoint(
    id: 'point-$index',
    sessionId: 'session-1',
    timestamp: timestamp,
    latitude: latitude,
    longitude: longitude,
    altitude: altitude,
    speed: speed,
    heading: null,
    accuracy: 8,
  );
}
