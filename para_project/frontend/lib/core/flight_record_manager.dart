import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_models.dart';
import 'telemetry_filter.dart';
import 'utils.dart';

class FlightRecordStore {
  static const _sessionsKey = 'flight_sessions_v1';
  static const _activeSessionKey = 'flight_active_session_v1';
  static const _activePointsKey = 'flight_track_points_active_v1';
  static const _trackingRuntimeStateKey = 'flight_tracking_runtime_v1';

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

  Future<Map<String, dynamic>?> loadTrackingRuntimeState() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_trackingRuntimeStateKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> saveTrackingRuntimeState(Map<String, dynamic> state) async {
    final prefs = await _prefs();
    await prefs.setString(_trackingRuntimeStateKey, jsonEncode(state));
  }

  Future<void> clearTrackingRuntimeState() async {
    final prefs = await _prefs();
    await prefs.remove(_trackingRuntimeStateKey);
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

  Future<void> clearTrackPoints(String sessionId) async {
    final prefs = await _prefs();
    await prefs.remove(_pointsKey(sessionId));
  }
}

enum FlightTrackingNoticeTone { info, caution, warning }

class FlightTrackingNotice {
  const FlightTrackingNotice({
    required this.code,
    required this.title,
    required this.description,
    required this.tone,
    required this.updatedAt,
  });

  final String code;
  final String title;
  final String description;
  final FlightTrackingNoticeTone tone;
  final DateTime updatedAt;

  factory FlightTrackingNotice.fromJson(Map<String, dynamic> json) {
    final toneValue = json['tone'] as String? ?? 'info';
    final tone = FlightTrackingNoticeTone.values.firstWhere(
      (item) => item.name == toneValue,
      orElse: () => FlightTrackingNoticeTone.info,
    );

    return FlightTrackingNotice(
      code: json['code'] as String? ?? 'unknown',
      title: json['title'] as String? ?? '추적 상태 안내',
      description: json['description'] as String? ?? '',
      tone: tone,
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'title': title,
        'description': description,
        'tone': tone.name,
        'updated_at': updatedAt.toIso8601String(),
      };
}

class FlightRecordManager extends ChangeNotifier with WidgetsBindingObserver {
  FlightRecordManager({FlightRecordStore? store})
      : _store = store ?? FlightRecordStore() {
    WidgetsBinding.instance.addObserver(this);
  }

  final FlightRecordStore _store;
  final TelemetryFilter _telemetryFilter = const TelemetryFilter();

  StreamSubscription<Position>? _positionSubscription;

  bool _initialized = false;
  int? _userId;
  bool _loading = false;
  bool _working = false;
  bool _resumingTracking = false;
  String? _errorMessage;
  String? _statusMessage;
  FlightTrackingNotice? _trackingNotice;
  DateTime? _lastPositionSampleAt;
  FlightSession? _activeSession;
  List<FlightTrackPoint> _activePoints = [];
  List<FlightSession> _sessions = [];

  bool get isLoading => _loading;
  bool get isWorking => _working;
  bool get isRecording => _activeSession != null;
  bool get isPaused => _activeSession?.isPaused ?? false;
  bool get isRecoveringTracking => _resumingTracking;
  String? get errorMessage => _errorMessage;
  String? get statusMessage => _statusMessage;
  FlightTrackingNotice? get trackingNotice => _trackingNotice;
  FlightSession? get activeSession => _activeSession;
  FlightTrackPoint? get lastPoint =>
      _activePoints.isEmpty ? null : _activePoints.last;
  List<FlightTrackPoint> get activePoints => List.unmodifiable(_activePoints);
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
      await _normalizeStoredSessions();

      final activeSession = await _store.loadActiveSession();
      final runtimeState = await _store.loadTrackingRuntimeState();
      if (activeSession != null && activeSession.userId == userId) {
        _activeSession = activeSession;
        _activePoints = await _store.loadActiveTrackPoints();
        _lastPositionSampleAt = _restoreLastSampleAt(
          runtimeState,
          activeSession: activeSession,
          points: _activePoints,
        );
        final persistedNotice = _restoreTrackingNotice(runtimeState);
        if (persistedNotice != null) {
          _trackingNotice = persistedNotice;
        }
        if (activeSession.isRecording) {
          _setTrackingNotice(
            code: 'restored_after_restart',
            title: '앱 재시작 후 비행 세션을 복원했습니다.',
            description: _activePoints.isEmpty
                ? '저장된 비행 상태를 불러왔고 위치 추적을 다시 연결하는 중입니다.'
                : '저장된 경로 ${_activePoints.length}개를 불러왔고 위치 추적을 다시 연결하는 중입니다.',
            tone: FlightTrackingNoticeTone.info,
            notify: false,
          );
          await _resumeTrackingIfPossible(fromRestore: true);
        } else if (activeSession.isPaused) {
          _statusMessage = '일시정지된 비행 기록을 불러왔습니다.';
        }
      } else {
        _activeSession = null;
        _activePoints = [];
        _trackingNotice = null;
        _lastPositionSampleAt = null;
        await _store.clearTrackingRuntimeState();
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
        locationSettings: _singleLocationSettings(),
      );
      final timestamp = _normalizeRecordedTime(position.timestamp);
      final sessionId = 'flight_${timestamp.millisecondsSinceEpoch}';
      final firstPoint = _telemetryFilter.filter(
            sessionId: sessionId,
            position: position,
            existingPoints: const [],
          )?.point ??
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
        pausedDurationSeconds: 0,
        lastLatitude: firstPoint.latitude,
        lastLongitude: firstPoint.longitude,
        lastAccuracyMeters: firstPoint.accuracy,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      _activePoints = [firstPoint];
      _lastPositionSampleAt = firstPoint.timestamp;
      _trackingNotice = null;

      await _store.saveActiveSession(_activeSession!);
      await _store.saveActiveTrackPoints(_activePoints);
      await _persistTrackingRuntimeState();
      await _startTracking();

      _statusMessage = '비행 기록을 시작했습니다. 화면을 벗어나도 추적을 최대한 유지합니다.';
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
      final finalDurationSeconds = currentSession.isPaused
          ? currentSession.durationSeconds
          : _calculateElapsedSeconds(
              currentSession,
              referenceTime: completedAt,
            );
      final completedSession = _sessionWithResolvedTimeline(
        session: currentSession.copyWith(
          endedAt: completedAt,
          status: FlightSessionStatus.completed,
          durationSeconds:
              max(currentSession.durationSeconds, finalDurationSeconds),
          memo: memo.trim(),
          pausedAt: null,
          updatedAt: completedAt,
        ),
        points: _activePoints,
      );

      _sessions = [
        completedSession,
        ..._sessions.where((item) => item.id != completedSession.id)
      ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));

      await _store.saveTrackPoints(completedSession.id, _activePoints);
      await _store.saveSessions(_sessions);
      await _store.clearActiveSession();
      await _store.clearActiveTrackPoints();
      await _store.clearTrackingRuntimeState();

      _activeSession = null;
      _activePoints = [];
      _trackingNotice = null;
      _lastPositionSampleAt = null;
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
      final points = List<FlightTrackPoint>.from(_activePoints);
      return FlightSessionDetail(
        session: _sessionWithResolvedTimeline(
          session: activeSession,
          points: points,
        ),
        points: points,
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
    return FlightSessionDetail(
      session: _sessionWithResolvedTimeline(session: session, points: points),
      points: points,
    );
  }

  Future<bool> deleteSession(String sessionId) async {
    if (_working) {
      return false;
    }

    if (_activeSession?.id == sessionId) {
      _errorMessage = '진행 중인 비행 기록은 삭제할 수 없습니다.';
      notifyListeners();
      return false;
    }

    final existingIndex = _sessions.indexWhere((item) => item.id == sessionId);
    if (existingIndex < 0) {
      _errorMessage = '삭제할 비행 기록을 찾지 못했습니다.';
      notifyListeners();
      return false;
    }

    _working = true;
    _errorMessage = null;
    _statusMessage = null;
    notifyListeners();

    try {
      _sessions = [
        for (final session in _sessions)
          if (session.id != sessionId) session,
      ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));

      await _store.saveSessions(_sessions);
      await _store.clearTrackPoints(sessionId);

      _statusMessage = '비행 기록이 삭제되었습니다.';
      return true;
    } catch (_) {
      _errorMessage = '비행 기록을 삭제하지 못했습니다.';
      return false;
    } finally {
      _working = false;
      notifyListeners();
    }
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

  Future<void> _normalizeStoredSessions() async {
    if (_sessions.isEmpty) {
      return;
    }

    var changed = false;
    final normalizedSessions = <FlightSession>[];
    for (final session in _sessions) {
      if (session.trackPointCount <= 0) {
        normalizedSessions.add(session);
        continue;
      }

      final points = await _store.loadTrackPoints(session.id);
      final normalized = _sessionWithResolvedTimeline(
        session: session,
        points: points,
      );
      if (!_sameTimeline(session, normalized)) {
        changed = true;
      }
      normalizedSessions.add(normalized);
    }

    normalizedSessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    _sessions = normalizedSessions;

    if (changed) {
      await _store.saveSessions(_sessions);
    }
  }

  FlightSession _sessionWithResolvedTimeline({
    required FlightSession session,
    required List<FlightTrackPoint> points,
  }) {
    if (points.isEmpty) {
      return session;
    }

    FlightTrackPoint earliest = points.first;
    FlightTrackPoint latest = points.first;
    for (final point in points.skip(1)) {
      if (point.timestamp.isBefore(earliest.timestamp)) {
        earliest = point;
      }
      if (point.timestamp.isAfter(latest.timestamp)) {
        latest = point;
      }
    }

    final resolvedDuration = latest.timestamp.difference(earliest.timestamp);
    return session.copyWith(
      startedAt: earliest.timestamp,
      endedAt: session.status == FlightSessionStatus.completed
          ? latest.timestamp
          : session.endedAt,
      durationSeconds: resolvedDuration > Duration.zero
          ? resolvedDuration.inSeconds
          : session.durationSeconds,
      trackPointCount: max(session.trackPointCount, points.length),
      updatedAt: latest.timestamp.isAfter(session.updatedAt)
          ? latest.timestamp
          : session.updatedAt,
    );
  }

  bool _sameTimeline(FlightSession previous, FlightSession next) {
    return previous.startedAt == next.startedAt &&
        previous.endedAt == next.endedAt &&
        previous.durationSeconds == next.durationSeconds &&
        previous.trackPointCount == next.trackPointCount &&
        previous.updatedAt == next.updatedAt;
  }

  void clearMessages() {
    _errorMessage = null;
    _statusMessage = null;
    notifyListeners();
  }

  Future<bool> pauseRecording() async {
    final session = _activeSession;
    if (_working || session == null || !session.isRecording) {
      return false;
    }

    _working = true;
    _errorMessage = null;
    _statusMessage = null;
    notifyListeners();

    try {
      await _positionSubscription?.cancel();
      _positionSubscription = null;

      final pausedAt = DateTime.now();
      _activeSession = session.copyWith(
        status: FlightSessionStatus.paused,
        durationSeconds: _calculateElapsedSeconds(
          session,
          referenceTime: pausedAt,
        ),
        pausedAt: pausedAt,
        updatedAt: pausedAt,
      );

      await _store.saveActiveSession(_activeSession!);
      await _persistTrackingRuntimeState(stopReason: 'paused');
      _statusMessage = '비행 기록을 일시정지했습니다.';
      return true;
    } catch (_) {
      _errorMessage = '비행 기록을 일시정지하지 못했습니다.';
      return false;
    } finally {
      _working = false;
      notifyListeners();
    }
  }

  Future<bool> resumeRecording() async {
    final session = _activeSession;
    if (_working || session == null || !session.isPaused) {
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

      final resumedAt = DateTime.now();
      final pausedSeconds = session.pausedAt == null
          ? 0
          : max(0, resumedAt.difference(session.pausedAt!).inSeconds);
      _activeSession = session.copyWith(
        status: FlightSessionStatus.recording,
        pausedDurationSeconds: session.pausedDurationSeconds + pausedSeconds,
        pausedAt: null,
        updatedAt: resumedAt,
      );

      await _store.saveActiveSession(_activeSession!);
      _setTrackingNotice(
        code: 'recovering',
        title: '백그라운드 추적 상태를 확인하는 중입니다.',
        description: '현재 위치와 비행 세션 상태를 다시 연결하고 있습니다.',
        tone: FlightTrackingNoticeTone.info,
        notify: false,
      );
      await _persistTrackingRuntimeState();
      await _startTracking(forceRestart: true);
      await _captureCurrentPosition();
      _statusMessage = '비행 기록을 다시 시작했습니다.';
      return true;
    } catch (_) {
      _errorMessage = '비행 기록을 다시 시작하지 못했습니다.';
      return false;
    } finally {
      _working = false;
      notifyListeners();
    }
  }

  Future<void> _resumeTrackingIfPossible({bool fromRestore = false}) async {
    final permissionError = await _ensureLocationReady(requestIfNeeded: false);
    if (permissionError != null) {
      _setTrackingNotice(
        code: 'tracking_interrupted',
        title: '추적이 일시 중단되었습니다.',
        description: permissionError,
        tone: FlightTrackingNoticeTone.warning,
        notify: false,
      );
      await _persistTrackingRuntimeState(stopReason: 'permission');
      _statusMessage = '진행 중이던 비행 기록은 불러왔지만 위치 추적을 다시 연결하지 못했습니다.';
      return;
    }
    await _startTracking(forceRestart: true);
    await _captureCurrentPosition();
    _statusMessage = fromRestore
        ? '앱 재시작 후 비행 세션을 복원했습니다.'
        : '진행 중이던 비행 기록을 복구하고 위치 추적을 다시 연결했습니다.';
    await _persistTrackingRuntimeState();
  }

  Future<void> _startTracking({bool forceRestart = false}) async {
    if (!forceRestart && _positionSubscription != null) {
      return;
    }

    await _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _streamLocationSettings(),
    ).listen(
      (position) async {
        await _appendPosition(position);
      },
      onError: (_) {
        _setTrackingNotice(
          code: 'system_restricted',
          title: '시스템에 의해 추적이 제한될 수 있습니다.',
          description:
              '배터리 최적화나 백그라운드 제한으로 위치 추적이 끊겼을 수 있습니다. 앱을 다시 열어 상태를 확인해 주세요.',
          tone: FlightTrackingNoticeTone.warning,
          notify: false,
        );
        _errorMessage = '위치 추적이 중단되었습니다. 기기 위치 상태를 확인해 주세요.';
        unawaited(
            _persistTrackingRuntimeState(stopReason: 'system_restricted'));
        notifyListeners();
      },
    );
  }

  Future<void> _captureCurrentPosition() async {
    if (_activeSession == null) {
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: _singleLocationSettings(),
      );
      await _appendPosition(position);
    } catch (_) {
      // 다음 위치 스트림 샘플에서 자연스럽게 복구한다.
    }
  }

  LocationSettings _singleLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
    );
  }

  LocationSettings _streamLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: '비행 기록 추적 중',
          notificationText: '앱이 화면 뒤에 있어도 위치 기록을 계속 유지합니다.',
          notificationChannelName: '비행 기록 추적',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );
  }

  Future<void> _appendPosition(Position position) async {
    final session = _activeSession;
    if (session == null || !session.isRecording) {
      return;
    }

    final filteredSample = _telemetryFilter.filter(
      sessionId: session.id,
      position: position,
      existingPoints: _activePoints,
    );
    if (filteredSample == null) {
      return;
    }

    final point = filteredSample.point;
    final previousPoint = _activePoints.isEmpty ? null : _activePoints.last;
    final safeDistance = filteredSample.distanceDeltaMeters.isFinite
        ? max(0.0, filteredSample.distanceDeltaMeters)
        : 0.0;
    final durationSeconds = _calculateElapsedSeconds(
      session,
      referenceTime: point.timestamp,
    );

    final segmentSeconds = previousPoint == null
        ? 0
        : max(0, point.timestamp.difference(previousPoint.timestamp).inSeconds);
    final fallbackSpeed =
        segmentSeconds > 0 ? safeDistance / segmentSeconds : 0.0;
    final currentSpeed =
        _safeSpeed(point.speed) > 0 ? _safeSpeed(point.speed) : fallbackSpeed;
    final totalDistance = session.totalDistanceMeters + safeDistance;

    _activePoints = [..._activePoints, point];
    _lastPositionSampleAt = point.timestamp;
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

    _updateTrackingNoticeForPoint(point);

    await _store.saveActiveSession(_activeSession!);
    await _store.saveActiveTrackPoints(_activePoints);
    await _persistTrackingRuntimeState();
    notifyListeners();
  }

  void _updateTrackingNoticeForPoint(FlightTrackPoint point) {
    final accuracy = point.accuracy;
    if (accuracy != null && accuracy > 35) {
      _setTrackingNotice(
        code: 'gps_weak',
        title: 'GPS 신호가 약합니다.',
        description: '위치 정확도가 낮아 기록 정확도가 떨어질 수 있습니다. 개활지에서 GPS 상태를 다시 확인해 주세요.',
        tone: FlightTrackingNoticeTone.caution,
        notify: false,
      );
      return;
    }

    if (_trackingNotice != null &&
        {
          'gps_weak',
          'recovering',
          'restored_after_restart',
        }.contains(_trackingNotice!.code)) {
      _trackingNotice = null;
    }
  }

  Future<void> _persistTrackingRuntimeState({
    String? stopReason,
    String lifecycleState = 'foreground',
  }) async {
    final session = _activeSession;
    if (session == null) {
      await _store.clearTrackingRuntimeState();
      return;
    }

    await _store.saveTrackingRuntimeState({
      'session_id': session.id,
      'tracking_status': session.status.value,
      'last_sample_at': _lastPositionSampleAt?.toIso8601String(),
      'last_stop_reason': stopReason,
      'lifecycle_state': lifecycleState,
      'notice': _trackingNotice?.toJson(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  DateTime? _restoreLastSampleAt(
    Map<String, dynamic>? runtimeState, {
    required FlightSession activeSession,
    required List<FlightTrackPoint> points,
  }) {
    final raw = runtimeState?['last_sample_at'] as String?;
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    if (parsed != null) {
      return parsed;
    }
    if (points.isNotEmpty) {
      return points.last.timestamp;
    }
    return activeSession.updatedAt;
  }

  FlightTrackingNotice? _restoreTrackingNotice(
    Map<String, dynamic>? runtimeState,
  ) {
    final json = runtimeState?['notice'];
    if (json is! Map<String, dynamic>) {
      return null;
    }
    return FlightTrackingNotice.fromJson(json);
  }

  void _setTrackingNotice({
    required String code,
    required String title,
    required String description,
    required FlightTrackingNoticeTone tone,
    bool notify = true,
  }) {
    _trackingNotice = FlightTrackingNotice(
      code: code,
      title: title,
      description: description,
      tone: tone,
      updatedAt: DateTime.now(),
    );
    if (notify) {
      notifyListeners();
    }
  }

  FlightTrackPoint _buildTrackPoint({
    required String sessionId,
    required Position position,
  }) {
    final timestamp = _normalizeRecordedTime(position.timestamp);
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

  DateTime _normalizeRecordedTime(DateTime timestamp) =>
      timestamp.isUtc ? timestamp.toLocal() : timestamp;

  double _safeSpeed(double? speed) {
    if (speed == null || !speed.isFinite || speed < 0) {
      return 0;
    }
    return speed;
  }

  int _calculateElapsedSeconds(
    FlightSession session, {
    DateTime? referenceTime,
  }) {
    if (session.isPaused) {
      return session.durationSeconds;
    }

    final baseTime = referenceTime ?? DateTime.now();
    return max(
      0,
      baseTime.difference(session.startedAt).inSeconds -
          session.pausedDurationSeconds,
    );
  }

  Future<String?> _ensureLocationReady({bool requestIfNeeded = true}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _setTrackingNotice(
        code: 'location_service_disabled',
        title: '위치 서비스가 꺼져 있습니다.',
        description: '기기 설정에서 위치 서비스를 다시 켜야 비행 기록을 이어갈 수 있습니다.',
        tone: FlightTrackingNoticeTone.warning,
        notify: false,
      );
      return '위치 서비스가 꺼져 있습니다. 기기 설정에서 위치 서비스를 켜 주세요.';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestIfNeeded) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      _setTrackingNotice(
        code: 'location_permission_required',
        title: '위치 권한이 필요합니다.',
        description: '위치 권한이 꺼져 있어 추적을 계속할 수 없습니다. 권한을 허용한 뒤 다시 시도해 주세요.',
        tone: FlightTrackingNoticeTone.warning,
        notify: false,
      );
      return '위치 권한이 필요합니다. 권한을 허용한 뒤 다시 시도해 주세요.';
    }
    if (permission == LocationPermission.deniedForever) {
      _setTrackingNotice(
        code: 'location_permission_denied_forever',
        title: '위치 권한이 꺼져 있습니다.',
        description: '기기 설정에서 위치 권한을 직접 다시 허용해야 추적을 복구할 수 있습니다.',
        tone: FlightTrackingNoticeTone.warning,
        notify: false,
      );
      return '위치 권한이 영구적으로 거부되었습니다. 기기 설정에서 권한을 직접 허용해 주세요.';
    }

    if (_trackingNotice != null &&
        {
          'location_service_disabled',
          'location_permission_required',
          'location_permission_denied_forever',
        }.contains(_trackingNotice!.code)) {
      _trackingNotice = null;
    }

    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(
        _persistTrackingRuntimeState(
          lifecycleState: 'background',
        ),
      );
    }

    if (state != AppLifecycleState.resumed ||
        _activeSession == null ||
        _activeSession!.isPaused ||
        _resumingTracking) {
      return;
    }

    _resumingTracking = true;
    _setTrackingNotice(
      code: 'recovering',
      title: '백그라운드 추적 상태를 확인하는 중입니다.',
      description: '앱 복귀 후 현재 위치와 저장된 비행 세션을 다시 맞추고 있습니다.',
      tone: FlightTrackingNoticeTone.info,
      notify: true,
    );
    unawaited(_restoreTrackingAfterResume());
  }

  Future<void> _restoreTrackingAfterResume() async {
    try {
      final permissionError =
          await _ensureLocationReady(requestIfNeeded: false);
      if (permissionError != null) {
        _errorMessage = permissionError;
        notifyListeners();
        return;
      }

      await _startTracking(forceRestart: true);
      await _captureCurrentPosition();
      await _persistTrackingRuntimeState();
    } finally {
      _resumingTracking = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSubscription?.cancel();
    super.dispose();
  }
}
