import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:paragliding_mvp_frontend/core/telemetry_filter.dart';

void main() {
  group('TelemetryFilter', () {
    const filter = TelemetryFilter();

    test('정지 상태의 작은 흔들림과 센서 속도 튐은 억제한다', () {
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

    test('의미 있는 이동은 거리와 속도를 유지한다', () {
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
  });
}

Position _position({
  required double latitude,
  required double longitude,
  required double altitude,
  required double accuracy,
  required double speed,
  required double heading,
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
    headingAccuracy: 6,
    speed: speed,
    speedAccuracy: 1,
  );
}
