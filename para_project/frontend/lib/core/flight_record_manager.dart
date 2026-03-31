import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_models.dart';
import 'utils.dart';

class FlightRecordStore {
  static const _sessionsKey = 'flight_sessions_v1';
  static const _activeSessionKey = 'flight_active_session_v1';
  static const _activePointsKey = 'flight_track_points_active_v1';

  SharedPreferences? _preferences;

  Future<SharedPreferences> _prefs() async {
    _preferences ??= await SharedPreferences.getInstance();
    return _preferences!;
  }

  String _pointsKey(String sessionId) => 'flight_track_points_v1_$sessionId';

  Future<List<FlightSession>> loadSessions() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_sessionsKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => FlightSession.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveSessions(List<FlightSession> sessions) async {
    final prefs = await _prefs();
    await prefs.setString(
      _sessionsKey,
      jsonEncode(sessions.map((item) => item.toJson()).toList()),
    );
  }

  Future<FlightSession?> loadActiveSession() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_activeSessionKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return FlightSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveActiveSession(FlightSession session) async {
    final prefs = await _prefs();
    await prefs.setString(_activeSessionKey, jsonEncode(session.toJson()));
  }

  Future<void> clearActiveSession() async {
    final prefs = await _prefs();
    await prefs.remove(_activeSessionKey);
  }

  Future<List<FlightTrackPoint>> loadActiveTrackPoints() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_activePointsKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => FlightTrackPoint.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveActiveTrackPoints(List<FlightTrackPoint> points) async {
    final prefs = await _prefs();
    await prefs.setString(
      _activePointsKey,
      jsonEncode(points.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> clearActiveTrackPoints() async {
    final prefs = await _prefs();
    await prefs.remove(_activePointsKey);
  }

  Future<List<FlightTrackPoint>> loadTrackPoints(String sessionId) async {
    final prefs = await _prefs();
    final raw = prefs.getString(_pointsKey(sessionId));
    if (raw == null || raw.isEmpty) {
      return [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => FlightTrackPoint.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveTrackPoints(
      String sessionId, List<FlightTrackPoint> points) async {
    final prefs = await _prefs();
    await prefs.setString(
      _pointsKey(sessionId),
      jsonEncode(points.map((item) => item.toJson()).toList()),
    );
  }
}

class FlightRecordManager extends ChangeNotifier {
  FlightRecordManager({FlightRecordStore? store})
      : _store = store ?? FlightRecordStore();

  final FlightRecordStore _store;

  StreamSubscription<Position>? _positionSubscription;

  bool _initialized = false;
  int? _userId;
  bool _loading = false;
  bool _working = false;
  String? _errorMessage;
  String? _statusMessage;
  FlightSession? _activeSession;
  List<FlightTrackPoint> _activePoints = [];
  List<FlightSession> _sessions = [];

  bool get isLoading => _loading;
  bool get isWorking => _working;
  bool get isRecording => _activeSession != null;
  String? get errorMessage => _errorMessage;
  String? get statusMessage => _statusMessage;
  FlightSession? get activeSession => _activeSession;
  FlightTrackPoint? get lastPoint =>
      _activePoints.isEmpty ? null : _activePoints.last;
  List<FlightSession> get sessions => List.unmodifiable(_sessions);

  Future<void> initialize({required int userId}) async {
    if (_initialized && _userId == userId) {
      return;
    }

    _userId = userId;
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final loadedSessions = await _store.loadSessions();
      _sessions = loadedSessions.where((item) => item.userId == userId).toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

      final activeSession = await _store.loadActiveSession();
      if (activeSession != null && activeSession.userId == userId) {
        _activeSession = activeSession;
        _activePoints = await _store.loadActiveTrackPoints();
        await _resumeTrackingIfPossible();
      } else {
        _activeSession = null;
        _activePoints = [];
      }

      _initialized = true;
    } catch (_) {
      _errorMessage = '비행 기록 데이터를 불러오지 못했습니다.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> startRecording({
    required int userId,
    SiteSummary? site,
  }) async {
    if (_working) {
      return false;
    }

    await initialize(userId: userId);

    if (_activeSession != null) {
      _errorMessage = '이미 진행 중인 비행 기록이 있습니다.';
      notifyListeners();
      return false;
    }

    _working = true;
    _errorMessage = null;
    _statusMessage = null;
    notifyListeners();

    try {
      final permissionError = await _ensureLocationReady();
      if (permissionError != null) {
        _errorMessage = permissionError;
        return false;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.best),
      );
      final timestamp = position.timestamp;
      final sessionId = 'flight_${timestamp.millisecondsSinceEpoch}';
      final firstPoint =
          _buildTrackPoint(sessionId: sessionId, position: position);
      final initialSpeed = _safeSpeed(firstPoint.speed);

      _activeSession = FlightSession(
        id: sessionId,
        userId: userId,
        startedAt: timestamp,
        status: FlightSessionStatus.recording,
        siteId: site?.id,
        siteName: site?.name ?? '',
        region: site?.region ?? '',
        durationSeconds: 0,
        totalDistanceMeters: 0,
        minAltitudeMeters: firstPoint.altitude,
        maxAltitudeMeters: firstPoint.altitude,
        avgSpeedMps: initialSpeed,
        maxSpeedMps: initialSpeed,
        trackPointCount: 1,
        lastLatitude: firstPoint.latitude,
        lastLongitude: firstPoint.longitude,
        lastAccuracyMeters: firstPoint.accuracy,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      _activePoints = [firstPoint];

      await _store.saveActiveSession(_activeSession!);
      await _store.saveActiveTrackPoints(_activePoints);
      await _startTracking();

      _statusMessage = '비행 기록을 시작했습니다.';
      return true;
    } catch (_) {
      _errorMessage = '비행 기록을 시작하지 못했습니다. 위치 상태를 확인해 주세요.';
      return false;
    } finally {
      _working = false;
      notifyListeners();
    }
  }

  Future<FlightSession?> stopRecording({String memo = ''}) async {
    if (_working || _activeSession == null) {
      return null;
    }

    _working = true;
    _errorMessage = null;
    _statusMessage = null;
    notifyListeners();

    try {
      await _positionSubscription?.cancel();
      _positionSubscription = null;

      final currentSession = _activeSession!;
      final completedAt = DateTime.now();
      final completedSession = currentSession.copyWith(
        endedAt: completedAt,
        status: FlightSessionStatus.completed,
        durationSeconds: max(currentSession.durationSeconds,
            completedAt.difference(currentSession.startedAt).inSeconds),
        memo: memo.trim(),
        updatedAt: completedAt,
      );

      _sessions = [
        completedSession,
        ..._sessions.where((item) => item.id != completedSession.id)
      ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));

      await _store.saveTrackPoints(completedSession.id, _activePoints);
      await _store.saveSessions(_sessions);
      await _store.clearActiveSession();
      await _store.clearActiveTrackPoints();

      _activeSession = null;
      _activePoints = [];
      _statusMessage = '비행 기록을 저장했습니다.';
      return completedSession;
    } catch (_) {
      _errorMessage = '비행 기록 저장에 실패했습니다.';
      return null;
    } finally {
      _working = false;
      notifyListeners();
    }
  }

  Future<FlightSessionDetail?> getSessionDetail(String sessionId) async {
    final activeSession = _activeSession;
    if (activeSession != null && activeSession.id == sessionId) {
      return FlightSessionDetail(
        session: activeSession,
        points: List<FlightTrackPoint>.from(_activePoints),
      );
    }

    FlightSession? session;
    for (final item in _sessions) {
      if (item.id == sessionId) {
        session = item;
        break;
      }
    }
    if (session == null) {
      return null;
    }

    final points = await _store.loadTrackPoints(sessionId);
    return FlightSessionDetail(session: session, points: points);
  }

  Future<bool> shareSession(String sessionId) async {
    _errorMessage = null;
    _statusMessage = null;
    notifyListeners();

    try {
      final detail = await getSessionDetail(sessionId);
      if (detail == null) {
        _errorMessage = '공유할 비행 기록을 찾지 못했습니다.';
        notifyListeners();
        return false;
      }

      final summary = buildShareSummary(detail.session);
      final payload = jsonEncode(buildExportPayload(detail));
      final fileName = buildExportFileName(detail.session);

      await Share.shareXFiles(
        [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(payload)),
            mimeType: 'application/json',
            name: fileName,
          ),
        ],
        text: summary,
        subject: '${detail.session.displaySiteName} 비행 기록',
        fileNameOverrides: [fileName],
      );

      _statusMessage = '비행 기록을 공유했습니다.';
      notifyListeners();
      return true;
    } catch (_) {
      _errorMessage = '비행 기록 공유에 실패했습니다.';
      notifyListeners();
      return false;
    }
  }

  String buildShareSummary(FlightSession session) {
    final lines = [
      '비행 기록 공유',
      '비행 날짜: ${formatDate(session.startedAt)}',
      '비행 시간: ${formatDuration(session.duration)}',
      '지역/비행장: ${session.displayRegion} / ${session.displaySiteName}',
      '총 거리: ${formatDistanceMeters(session.totalDistanceMeters)}',
      '최고 고도: ${formatAltitudeMeters(session.maxAltitudeMeters)}',
    ];

    if (session.memo.trim().isNotEmpty) {
      lines.add('메모: ${session.memo.trim()}');
    }

    return lines.join('\n');
  }

  Map<String, dynamic> buildExportPayload(FlightSessionDetail detail) {
    return {
      'schema_version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'summary': buildShareSummary(detail.session),
      'session': detail.session.toJson(),
      'track_points': detail.points.map((item) => item.toJson()).toList(),
    };
  }

  String buildExportFileName(FlightSession session) {
    final dateToken = formatDate(session.startedAt).replaceAll('-', '');
    return '비행기록_$dateToken.json';
  }

  void clearMessages() {
    _errorMessage = null;
    _statusMessage = null;
    notifyListeners();
  }

  Future<void> _resumeTrackingIfPossible() async {
    final permissionError = await _ensureLocationReady(requestIfNeeded: false);
    if (permissionError != null) {
      _statusMessage = '진행 중이던 비행 기록을 불러왔지만 위치 추적은 자동 재개되지 않았습니다.';
      return;
    }
    await _startTracking();
    _statusMessage = '진행 중이던 비행 기록을 복구했습니다.';
  }

  Future<void> _startTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 8,
      ),
    ).listen(
      (position) async {
        await _appendPosition(position);
      },
      onError: (_) {
        _errorMessage = '위치 추적이 중단되었습니다. 기기 위치 상태를 확인해 주세요.';
        notifyListeners();
      },
    );
  }

  Future<void> _appendPosition(Position position) async {
    final session = _activeSession;
    if (session == null) {
      return;
    }

    final point = _buildTrackPoint(sessionId: session.id, position: position);
    final previousPoint = _activePoints.isEmpty ? null : _activePoints.last;
    final segmentDistance = previousPoint == null
        ? 0.0
        : Geolocator.distanceBetween(
            previousPoint.latitude,
            previousPoint.longitude,
            point.latitude,
            point.longitude,
          );
    final safeDistance =
        segmentDistance.isFinite ? max(0.0, segmentDistance) : 0.0;
    final durationSeconds =
        max(0, point.timestamp.difference(session.startedAt).inSeconds);

    final segmentSeconds = previousPoint == null
        ? 0
        : max(0, point.timestamp.difference(previousPoint.timestamp).inSeconds);
    final fallbackSpeed =
        segmentSeconds > 0 ? safeDistance / segmentSeconds : 0.0;
    final currentSpeed =
        _safeSpeed(point.speed) > 0 ? _safeSpeed(point.speed) : fallbackSpeed;
    final totalDistance = session.totalDistanceMeters + safeDistance;

    _activePoints = [..._activePoints, point];
    _activeSession = session.copyWith(
      durationSeconds: durationSeconds,
      totalDistanceMeters: totalDistance,
      minAltitudeMeters: min(session.minAltitudeMeters, point.altitude),
      maxAltitudeMeters: max(session.maxAltitudeMeters, point.altitude),
      avgSpeedMps:
          durationSeconds > 0 ? totalDistance / durationSeconds : currentSpeed,
      maxSpeedMps: max(session.maxSpeedMps, currentSpeed),
      trackPointCount: _activePoints.length,
      lastLatitude: point.latitude,
      lastLongitude: point.longitude,
      lastAccuracyMeters: point.accuracy,
      updatedAt: point.timestamp,
    );

    await _store.saveActiveSession(_activeSession!);
    await _store.saveActiveTrackPoints(_activePoints);
    notifyListeners();
  }

  FlightTrackPoint _buildTrackPoint({
    required String sessionId,
    required Position position,
  }) {
    final timestamp = position.timestamp;
    return FlightTrackPoint(
      id: '${sessionId}_${timestamp.microsecondsSinceEpoch}',
      sessionId: sessionId,
      timestamp: timestamp,
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
      speed: position.speed >= 0 ? position.speed : null,
      heading: position.heading >= 0 ? position.heading : null,
      accuracy: position.accuracy >= 0 ? position.accuracy : null,
    );
  }

  double _safeSpeed(double? speed) {
    if (speed == null || !speed.isFinite || speed < 0) {
      return 0;
    }
    return speed;
  }

  Future<String?> _ensureLocationReady({bool requestIfNeeded = true}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return '위치 서비스가 꺼져 있습니다. 기기 설정에서 위치 서비스를 켜 주세요.';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestIfNeeded) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return '위치 권한이 필요합니다. 권한을 허용한 뒤 다시 시도해 주세요.';
    }
    if (permission == LocationPermission.deniedForever) {
      return '위치 권한이 영구적으로 거부되었습니다. 기기 설정에서 권한을 직접 허용해 주세요.';
    }

    return null;
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }
}
