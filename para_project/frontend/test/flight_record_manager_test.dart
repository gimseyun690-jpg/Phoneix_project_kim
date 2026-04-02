import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:paragliding_mvp_frontend/core/flight_record_manager.dart';
import 'package:paragliding_mvp_frontend/models/app_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('추적 안내는 JSON으로 안전하게 직렬화된다', () {
    final notice = FlightTrackingNotice(
      code: 'gps_weak',
      title: 'GPS 신호가 약합니다.',
      description: '정확도가 낮아 기록 품질이 잠시 떨어질 수 있습니다.',
      tone: FlightTrackingNoticeTone.caution,
      updatedAt: DateTime(2026, 4, 1, 12, 30),
    );

    final restored = FlightTrackingNotice.fromJson(notice.toJson());

    expect(restored.code, 'gps_weak');
    expect(restored.title, 'GPS 신호가 약합니다.');
    expect(restored.tone, FlightTrackingNoticeTone.caution);
  });

  test('저장된 비행 기록은 실제 첫 track point를 시작 시간으로 보정한다', () async {
    final session = FlightSession(
      id: 'session-1',
      userId: 2,
      startedAt: DateTime(2026, 3, 31, 9, 10),
      endedAt: DateTime(2026, 3, 31, 10, 0),
      status: FlightSessionStatus.completed,
      siteId: 4,
      siteName: '문경 이륙장',
      region: '경북 문경',
      durationSeconds: 3000,
      totalDistanceMeters: 12850,
      minAltitudeMeters: 152,
      maxAltitudeMeters: 812,
      avgSpeedMps: 2.9,
      maxSpeedMps: 8.4,
      memo: '',
      trackPointCount: 2,
      pausedDurationSeconds: 0,
      lastLatitude: 36.586,
      lastLongitude: 128.186,
      lastAccuracyMeters: 6,
      createdAt: DateTime(2026, 3, 31, 9, 0),
      updatedAt: DateTime(2026, 3, 31, 10, 0),
    );

    final points = [
      FlightTrackPoint(
        id: 'point-1',
        sessionId: 'session-1',
        timestamp: DateTime(2026, 3, 31, 9, 0),
        latitude: 36.581,
        longitude: 128.181,
        altitude: 152,
        speed: 0,
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

    SharedPreferences.setMockInitialValues({
      'flight_sessions_v1': jsonEncode([session.toJson()]),
      'flight_track_points_v1_session-1':
          jsonEncode(points.map((item) => item.toJson()).toList()),
    });

    final manager = FlightRecordManager();
    addTearDown(manager.dispose);

    await manager.initialize(userId: 2);

    expect(manager.sessions, hasLength(1));
    expect(manager.sessions.first.startedAt, DateTime(2026, 3, 31, 9, 0));
    expect(manager.sessions.first.endedAt, DateTime(2026, 3, 31, 10, 15));
    expect(manager.sessions.first.durationSeconds, 4500);
  });

  test('UTC로 저장된 비행 시작 시간도 로컬 시각으로 보정된다', () async {
    final expectedStart = DateTime.utc(2026, 4, 2, 11, 23).toLocal();
    final expectedEnd = DateTime.utc(2026, 4, 2, 12, 5).toLocal();

    SharedPreferences.setMockInitialValues({
      'flight_sessions_v1': jsonEncode([
        {
          'id': 'session-utc',
          'user_id': 2,
          'started_at': '2026-04-02T11:23:00Z',
          'ended_at': '2026-04-02T12:05:00Z',
          'status': 'completed',
          'site_id': 4,
          'site_name': '양평 패러밸리',
          'region': '경기 양평',
          'duration_seconds': 2520,
          'total_distance_meters': 12850,
          'min_altitude_meters': 152,
          'max_altitude_meters': 812,
          'avg_speed_mps': 2.9,
          'max_speed_mps': 8.4,
          'memo': '',
          'track_point_count': 2,
          'paused_duration_seconds': 0,
          'last_latitude': 37.512,
          'last_longitude': 127.521,
          'last_accuracy_meters': 6,
          'created_at': '2026-04-02T11:23:00Z',
          'updated_at': '2026-04-02T12:05:00Z',
        },
      ]),
      'flight_track_points_v1_session-utc': jsonEncode([
        {
          'id': 'point-1',
          'session_id': 'session-utc',
          'timestamp': '2026-04-02T11:23:00Z',
          'latitude': 37.512,
          'longitude': 127.521,
          'altitude': 152,
          'speed': 0,
          'heading': 214,
          'accuracy': 8,
        },
        {
          'id': 'point-2',
          'session_id': 'session-utc',
          'timestamp': '2026-04-02T12:05:00Z',
          'latitude': 37.522,
          'longitude': 127.531,
          'altitude': 812,
          'speed': 7.8,
          'heading': 228,
          'accuracy': 6,
        },
      ]),
    });

    final manager = FlightRecordManager();
    addTearDown(manager.dispose);

    await manager.initialize(userId: 2);

    expect(manager.sessions, hasLength(1));
    expect(manager.sessions.first.startedAt, expectedStart);
    expect(manager.sessions.first.endedAt, expectedEnd);
  });

  test('비행 기록 삭제 시 세션과 저장된 경로가 함께 정리된다', () async {
    final session = FlightSession(
      id: 'session-1',
      userId: 2,
      startedAt: DateTime(2026, 3, 31, 9, 0),
      endedAt: DateTime(2026, 3, 31, 10, 15),
      status: FlightSessionStatus.completed,
      siteId: 4,
      siteName: '문경 이륙장',
      region: '경북 문경',
      durationSeconds: 4500,
      totalDistanceMeters: 12850,
      minAltitudeMeters: 152,
      maxAltitudeMeters: 812,
      avgSpeedMps: 2.9,
      maxSpeedMps: 8.4,
      memo: '',
      trackPointCount: 2,
      pausedDurationSeconds: 0,
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
        speed: 0,
        heading: 214,
        accuracy: 8,
      ),
    ];

    SharedPreferences.setMockInitialValues({
      'flight_sessions_v1': jsonEncode([session.toJson()]),
      'flight_track_points_v1_session-1':
          jsonEncode(points.map((item) => item.toJson()).toList()),
    });

    final manager = FlightRecordManager();
    addTearDown(manager.dispose);

    await manager.initialize(userId: 2);
    final deleted = await manager.deleteSession('session-1');
    final prefs = await SharedPreferences.getInstance();

    expect(deleted, isTrue);
    expect(manager.sessions, isEmpty);
    expect(await manager.getSessionDetail('session-1'), isNull);
    expect(prefs.getString('flight_track_points_v1_session-1'), isNull);
  });
}
