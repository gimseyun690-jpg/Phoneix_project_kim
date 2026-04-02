import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:paragliding_mvp_frontend/core/telemetry_filter.dart';

void main() {
  group('TelemetryFilter', () {
    const filter = TelemetryFilter();

    test('정지에 가까운 흔들림과 속도 튐은 방향 갱신에서 억제한다', () {
      final first = filter.filter(
        sessionId: 'session-1',
        position: _position(
          latitude: 37.50000,
          longitude: 127.10000,
          altitude: 120,
          accuracy: 12,
          speed: 0,
          heading: 180,
          timestamp: DateTime(2026, 4, 1, 10, 0, 0),
        ),
        existingPoints: const [],
      )!;

      final second = filter.filter(
        sessionId: 'session-1',
        position: _position(
          latitude: 37.50001,
          longitude: 127.10001,
          altitude: 121,
          accuracy: 10,
          speed: 5.8,
          heading: 270,
          timestamp: DateTime(2026, 4, 1, 10, 0, 3),
        ),
        existingPoints: [first.point],
      );

      expect(second, isNotNull);
      expect(second!.distanceDeltaMeters, 0);
      expect(second.point.speed, 0);
      expect(second.point.latitude, first.point.latitude);
      expect(second.point.longitude, first.point.longitude);
      expect(second.point.heading, first.point.heading);
    });

    test('의미 있는 이동은 거리와 속도를 반영해 추적한다', () {
      final first = filter.filter(
        sessionId: 'session-2',
        position: _position(
          latitude: 36.58000,
          longitude: 128.18000,
          altitude: 320,
          accuracy: 8,
          speed: 0,
          heading: 0,
          timestamp: DateTime(2026, 4, 1, 11, 0, 0),
        ),
        existingPoints: const [],
      )!;

      final second = filter.filter(
        sessionId: 'session-2',
        position: _position(
          latitude: 36.58080,
          longitude: 128.18075,
          altitude: 346,
          accuracy: 7,
          speed: 9.2,
          heading: 42,
          timestamp: DateTime(2026, 4, 1, 11, 0, 12),
        ),
        existingPoints: [first.point],
      );

      expect(second, isNotNull);
      expect(second!.distanceDeltaMeters, greaterThan(50));
      expect(second.point.speed, greaterThan(4));
      expect(second.point.heading, isNotNull);
      expect(second.point.latitude, isNot(first.point.latitude));
      expect(second.point.longitude, isNot(first.point.longitude));
    });

    test('최근 이동 경로가 분명하면 센서 heading보다 진행 방향을 우선한다', () {
      final first = filter.filter(
        sessionId: 'session-route-priority',
        position: _position(
          latitude: 36.58000,
          longitude: 128.18000,
          altitude: 320,
          accuracy: 8,
          speed: 0,
          heading: 0,
          timestamp: DateTime(2026, 4, 1, 11, 30, 0),
        ),
        existingPoints: const [],
      )!;

      final second = filter.filter(
        sessionId: 'session-route-priority',
        position: _position(
          latitude: 36.58055,
          longitude: 128.18003,
          altitude: 338,
          accuracy: 7,
          speed: 8.4,
          heading: 190,
          timestamp: DateTime(2026, 4, 1, 11, 30, 5),
        ),
        existingPoints: [first.point],
      )!;

      expect(second.point.heading, isNotNull);
      expect(second.point.heading!, lessThan(60));
    });

    test('북쪽 경계 근처 heading 변화는 자연스럽게 연결한다', () {
      final first = filter.filter(
        sessionId: 'session-3',
        position: _position(
          latitude: 35.10000,
          longitude: 128.10000,
          altitude: 420,
          accuracy: 7,
          speed: 7.2,
          heading: 358,
          timestamp: DateTime(2026, 4, 1, 12, 0, 0),
        ),
        existingPoints: const [],
      )!;

      final second = filter.filter(
        sessionId: 'session-3',
        position: _position(
          latitude: 35.10055,
          longitude: 128.10003,
          altitude: 432,
          accuracy: 7,
          speed: 8.6,
          heading: 4,
          timestamp: DateTime(2026, 4, 1, 12, 0, 5),
        ),
        existingPoints: [first.point],
      )!;

      expect(second.point.heading, isNotNull);
      final heading = second.point.heading!;
      expect(heading <= 20 || heading >= 340, isTrue);
    });

    test('저속 상태에서는 이전 방향을 유지해 흔들림을 줄인다', () {
      final first = filter.filter(
        sessionId: 'session-4',
        position: _position(
          latitude: 35.62000,
          longitude: 127.21000,
          altitude: 188,
          accuracy: 9,
          speed: 5.5,
          heading: 112,
          timestamp: DateTime(2026, 4, 1, 12, 20, 0),
        ),
        existingPoints: const [],
      )!;

      final second = filter.filter(
        sessionId: 'session-4',
        position: _position(
          latitude: 35.62003,
          longitude: 127.21002,
          altitude: 190,
          accuracy: 11,
          speed: 1.1,
          heading: 246,
          timestamp: DateTime(2026, 4, 1, 12, 20, 4),
        ),
        existingPoints: [first.point],
      )!;

      expect(second.point.heading, first.point.heading);
    });
  });
}

Position _position({
  required double latitude,
  required double longitude,
  required double altitude,
  required double accuracy,
  required double speed,
  required double heading,
  double headingAccuracy = 6,
  required DateTime timestamp,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp,
    accuracy: accuracy,
    altitude: altitude,
    altitudeAccuracy: 3,
    heading: heading,
    headingAccuracy: headingAccuracy,
    speed: speed,
    speedAccuracy: 1,
  );
}
