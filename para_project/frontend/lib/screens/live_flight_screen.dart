import 'dart:async';
import 'dart:math';

// ignore_for_file: unused_element, unused_element_parameter, prefer_final_fields

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app.dart';
import '../core/community_manager.dart';
import '../core/flight_live_metrics.dart';
import '../core/map_view_type.dart';
import '../core/flight_record_manager.dart';
import '../core/korea_flight_guide.dart';
import '../core/live_weather_service.dart';
import '../core/utils.dart';
import '../models/app_models.dart';
import '../repositories/app_repository.dart';
import '../widgets/flight_map_3d_view.dart';
import '../widgets/flight_map_view.dart';
import '../widgets/map_view_toggle.dart';

enum _LiveFlightMapMode { twoD, threeD }

class LiveFlightScreen extends StatefulWidget {
  const LiveFlightScreen({
    super.key,
    required this.repository,
    required this.user,
    required this.flightRecordManager,
    required this.communityManager,
  });

  final AppRepository repository;
  final AppUser user;
  final FlightRecordManager flightRecordManager;
  final CommunityManager communityManager;

  @override
  State<LiveFlightScreen> createState() => _LiveFlightScreenState();
}

class _LiveFlightScreenState extends State<LiveFlightScreen>
    with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final KoreaFlightGuide _flightGuide = const KoreaFlightGuide();
  final MapViewPreferenceStore _mapViewPreferenceStore =
      MapViewPreferenceStore();
  late final LiveWeatherService _liveWeatherService = LiveWeatherService();
  final GlobalKey<FlightMap3DViewState> _threeDMapKey =
      GlobalKey<FlightMap3DViewState>();

  Timer? _clockTimer;
  Timer? _contextRefreshTimer;
  List<SiteSummary> _sites = [];
  String? _areaLabel;
  LiveWeatherSnapshot? _weatherSnapshot;
  DateTime? _lastContextFetchedAt;
  FlightTrackPoint? _lastContextPoint;
  LatLng? _mapCenter;
  double _mapZoom = 14.5;
  bool _followLocation = true;
  bool _detailsCollapsed = true;
  _LiveFlightMapMode _mapMode =
      kIsWeb ? _LiveFlightMapMode.twoD : _LiveFlightMapMode.threeD;
  ParaglidingMapViewType _mapViewType = ParaglidingMapViewType.satellite;
  bool _loadingSites = true;
  bool _refreshingContext = false;
  bool _refreshingSites = false;
  String? _siteLoadError;
  String? _contextError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.flightRecordManager.addListener(_handleRecordingUpdate);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
    _contextRefreshTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      unawaited(_refreshCurrentContext(force: true));
    });
    unawaited(_loadMapViewType());
    _loadSites();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.flightRecordManager.removeListener(_handleRecordingUpdate);
    _clockTimer?.cancel();
    _contextRefreshTimer?.cancel();
    _liveWeatherService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }

    unawaited(_loadSites());
    unawaited(_refreshCurrentContext(force: true));
  }

  Future<void> _loadSites() async {
    if (_refreshingSites) {
      return;
    }

    _refreshingSites = true;
    setState(() {
      _loadingSites = true;
      _siteLoadError = null;
    });

    try {
      final sites =
          await widget.repository.getSites(pilotLevel: widget.user.pilotLevel);
      if (!mounted) {
        return;
      }
      setState(() {
        _sites = sites;
        _loadingSites = false;
      });
      _handleRecordingUpdate();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingSites = false;
        _siteLoadError = '비행장 정보를 불러오지 못했습니다.';
      });
    } finally {
      _refreshingSites = false;
    }
  }

  Future<void> _loadMapViewType() async {
    final loaded = await _mapViewPreferenceStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _mapViewType = loaded;
    });
  }

  Future<void> _changeMapViewType(ParaglidingMapViewType type) async {
    if (_mapViewType == type) {
      return;
    }
    setState(() {
      _mapViewType = type;
    });
    await _mapViewPreferenceStore.save(type);
  }

  void _handleRecordingUpdate() {
    final lastPoint = widget.flightRecordManager.lastPoint;
    if (lastPoint == null) {
      return;
    }

    if (_followLocation && _mapMode == _LiveFlightMapMode.twoD) {
      _moveCameraToPoint(lastPoint);
    }

    if (_shouldRefreshContext(lastPoint)) {
      unawaited(_refreshContext(lastPoint));
    }
  }

  bool _shouldRefreshContext(FlightTrackPoint point) {
    if (_lastContextPoint == null || _lastContextFetchedAt == null) {
      return true;
    }

    final elapsed = DateTime.now().difference(_lastContextFetchedAt!);
    if (elapsed >= const Duration(seconds: 90)) {
      return true;
    }

    final movedMeters = const Distance().as(
      LengthUnit.Meter,
      LatLng(_lastContextPoint!.latitude, _lastContextPoint!.longitude),
      LatLng(point.latitude, point.longitude),
    );
    return movedMeters >= 400;
  }

  Future<void> _refreshCurrentContext({bool force = false}) async {
    final point = widget.flightRecordManager.lastPoint;
    if (point == null) {
      return;
    }

    if (!force && !_shouldRefreshContext(point)) {
      return;
    }

    await _refreshContext(point, force: force);
  }

  Future<void> _refreshContext(
    FlightTrackPoint point, {
    bool force = false,
  }) async {
    if (_refreshingContext && !force) {
      return;
    }

    final session = widget.flightRecordManager.activeSession;
    if (session == null) {
      return;
    }

    _refreshingContext = true;
    final selectedSite = _selectedSiteForSession(session);
    try {
      final results = await Future.wait([
        _liveWeatherService.getCurrentWeather(
          latitude: point.latitude,
          longitude: point.longitude,
          selectedSite: selectedSite,
        ),
        _liveWeatherService.resolveAreaLabel(
          latitude: point.latitude,
          longitude: point.longitude,
        ),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _weatherSnapshot = results[0] as LiveWeatherSnapshot;
        _areaLabel = results[1] as String?;
        _lastContextFetchedAt = DateTime.now();
        _lastContextPoint = point;
        _contextError = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _contextError = '현재 위치 기준 날씨를 새로고침하지 못했습니다.';
      });
    } finally {
      _refreshingContext = false;
    }
  }

  SiteSummary? _selectedSiteForSession(FlightSession session) {
    for (final site in _sites) {
      if (site.id == session.siteId) {
        return site;
      }
    }
    return null;
  }

  Future<void> _handleManualRefresh() async {
    await _loadSites();
    await _refreshCurrentContext(force: true);
  }

  Future<void> _stopRecording() async {
    final controller = TextEditingController();
    final memo = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('비행 기록 저장'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: '메모',
            hintText: '착륙 상태, 바람 변화, 공유할 포인트를 적어 주세요.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('분석 보기'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (memo == null) {
      return;
    }

    final session = await widget.flightRecordManager.stopRecording(memo: memo);
    if (!mounted || session == null) {
      return;
    }

    await _openPostFlightActions(session.id);
  }

  Future<void> _openPostFlightActions(String sessionId) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '비행을 마쳤습니다.',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                '지금 바로 비행 분석을 보거나, 비행일지를 작성해 이륙장 커뮤니티와 연결할 수 있습니다.',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Navigator.pushReplacementNamed(
                      context,
                      AppRoutes.flightJournalComposer,
                      arguments:
                          FlightJournalComposerArgs(sessionId: sessionId),
                    );
                  },
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('비행일지 작성'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Navigator.pushReplacementNamed(
                      context,
                      AppRoutes.flightRecordDetail,
                      arguments: FlightRecordDetailArgs(sessionId: sessionId),
                    );
                  },
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('비행 분석 보기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmClose() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('실시간 화면 닫기'),
        content: const Text(
          '실시간 화면만 닫고 기록은 계속 유지할까요? 위치 추적은 백그라운드에서도 최대한 이어집니다. 장시간 비행 전에는 위치 권한과 배터리 최적화 예외를 함께 확인해 주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('계속 보기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('화면 닫기'),
          ),
        ],
      ),
    );

    return shouldLeave ?? false;
  }

  void _recenter() {
    final lastPoint = widget.flightRecordManager.lastPoint;
    if (lastPoint == null) {
      return;
    }
    if (_mapMode == _LiveFlightMapMode.threeD) {
      _threeDMapKey.currentState?.recenter(force: true);
      return;
    }

    _moveCameraToPoint(lastPoint, force: true);
  }

  void _moveCameraToPoint(
    FlightTrackPoint point, {
    bool force = false,
  }) {
    final target = LatLng(point.latitude, point.longitude);
    final currentCenter = _mapCenter;
    final currentZoom = _mapZoom < 13.8 ? 13.8 : _mapZoom;
    final shouldMove = force ||
        currentCenter == null ||
        const Distance().as(
              LengthUnit.Meter,
              currentCenter,
              target,
            ) >=
            12;

    if (!shouldMove) {
      return;
    }

    try {
      _mapController.move(target, currentZoom);
      _mapCenter = target;
      _mapZoom = currentZoom;
    } catch (_) {
      // 지도가 아직 붙기 전이면 다음 위치 갱신에서 다시 이동한다.
    }
  }

  void _handleMapPositionChanged(MapCamera camera, bool hasGesture) {
    _mapCenter = camera.center;
    _mapZoom = camera.zoom;
  }

  void _toggleDetailsCollapsed() {
    setState(() {
      _detailsCollapsed = !_detailsCollapsed;
    });
  }

  void _changeMapMode(_LiveFlightMapMode mode) {
    if (kIsWeb && mode == _LiveFlightMapMode.threeD) {
      return;
    }

    if (_mapMode == mode) {
      return;
    }

    setState(() {
      _mapMode = mode;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_followLocation) {
        _recenter();
      }
    });
  }

  Future<void> _handleBackPressed(NavigatorState navigator) async {
    final shouldClose = await _confirmClose();
    if (!mounted || !shouldClose) {
      return;
    }
    navigator.pop();
  }

  Future<void> _toggleRecordingState() async {
    if (widget.flightRecordManager.isWorking) {
      return;
    }

    final handled = widget.flightRecordManager.isPaused
        ? await widget.flightRecordManager.resumeRecording()
        : await widget.flightRecordManager.pauseRecording();
    if (!mounted) {
      return;
    }

    if (handled) {
      if (widget.flightRecordManager.isRecording && _followLocation) {
        _recenter();
      }
      return;
    }

    final message = widget.flightRecordManager.errorMessage;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Widget _buildDetailsToggleBar(
    BuildContext context, {
    required String summaryText,
  }) {
    final theme = Theme.of(context);
    final borderColor = Colors.black.withValues(alpha: 0.06);
    final isPaused = widget.flightRecordManager.isPaused;

    return Material(
      color: Colors.white,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: borderColor),
            bottom: BorderSide(
              color: _detailsCollapsed ? Colors.transparent : borderColor,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: _toggleDetailsCollapsed,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      _detailsCollapsed
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _detailsCollapsed ? '비행 정보 펼치기' : '비행 정보 접기',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      _detailsCollapsed ? '지도 중심 모드' : '세부 수치 보기',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_detailsCollapsed) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  summaryText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: widget.flightRecordManager.isWorking
                        ? null
                        : _toggleRecordingState,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(40),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: Icon(
                      isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    ),
                    label: Text(
                      widget.flightRecordManager.isWorking
                          ? '처리 중...'
                          : isPaused
                              ? '다시 시작'
                              : '일시정지',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: widget.flightRecordManager.isWorking
                        ? null
                        : _stopRecording,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(40),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(
                      widget.flightRecordManager.isWorking
                          ? '저장 중...'
                          : '종료하고 분석 보기',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveBody(
    BuildContext context, {
    required NavigatorState navigator,
    required FlightSession session,
    required FlightLiveMetrics metrics,
    required List<FlightTrackPoint> points,
    required KoreaFlightSiteMetadata? siteMetadata,
    required String currentLocationText,
    required String currentWindText,
    required String currentTemperatureText,
    required String currentWindDirectionText,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final panelHeight = _detailsCollapsed
            ? 102.0
            : min(max(availableHeight * 0.30, 206.0), 264.0);
        final metricsBottom = panelHeight + 8;
        final FlightTrackingNotice? trackingNotice = null;

        return Stack(
          fit: StackFit.expand,
          children: [
            _mapMode == _LiveFlightMapMode.threeD
                ? FlightMap3DView(
                    key: _threeDMapKey,
                    points: points,
                    height: availableHeight,
                    borderRadius: 0,
                    followLocation: _followLocation,
                    mapViewType: _mapViewType,
                    siteLatitude: null,
                    siteLongitude: null,
                    siteLabel: null,
                  )
                : FlightMapView(
                    points: points,
                    height: availableHeight,
                    borderRadius: 0,
                    mapController: _mapController,
                    currentHeadingDegrees: metrics.headingDegrees,
                    onPositionChanged: _handleMapPositionChanged,
                    mapViewType: _mapViewType,
                    emptyMessage: '위치가 잡히면 실시간 비행 지도가 바로 표시됩니다.',
                    siteLatitude: null,
                    siteLongitude: null,
                    siteLabel: null,
                    showSiteLabel: false,
                  ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.16),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.18),
                    ],
                    stops: const [0, 0.28, 1],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Stack(
                children: [
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Row(
                      children: [
                        _MapOverlayActionButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: '비행 화면 닫기',
                          onPressed: () => _handleBackPressed(navigator),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _CompactFlightStatusStrip(
                            siteName: session.displaySiteName,
                            regionName: session.displayRegion,
                            locationText: currentLocationText,
                            startedAtText: formatTime(metrics.startedAt),
                            currentTimeText: formatTime(metrics.currentTime),
                            elapsedText: formatDuration(metrics.elapsed),
                            statusLabel: session.status.label,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 72,
                    right: 12,
                    child: Column(
                      children: [
                        MapViewToggle(
                          value: _mapViewType,
                          onChanged: _changeMapViewType,
                          compact: true,
                        ),
                        if (!kIsWeb) ...[
                          const SizedBox(height: 8),
                          _CompactFlightMapModeToggle(
                            value: _mapMode,
                            onChanged: _changeMapMode,
                            compact: true,
                          ),
                        ],
                        const SizedBox(height: 8),
                        _MapOverlayActionButton(
                          icon: Icons.my_location_rounded,
                          tooltip: '현재 위치로 이동',
                          onPressed: _recenter,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: metricsBottom,
                    child: _CompactHeroMetricsCard(
                      currentAltitudeText:
                          formatAltitudeMeters(metrics.currentAltitudeMeters),
                      maxAltitudeText:
                          formatAltitudeMeters(session.maxAltitudeMeters),
                      speedText: formatSpeedKmh(metrics.currentSpeedMps),
                      verticalSpeedText:
                          formatVerticalSpeed(metrics.verticalSpeedMps),
                      distanceText:
                          formatDistanceMeters(metrics.totalDistanceMeters),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                height: panelHeight,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                    decoration: BoxDecoration(
                      color: const Color(0xF7111C24),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x26000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 34,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: _toggleDetailsCollapsed,
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                    vertical: 1,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _detailsCollapsed
                                                ? Icons
                                                    .keyboard_arrow_up_rounded
                                                : Icons
                                                    .keyboard_arrow_down_rounded,
                                            size: 16,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            _detailsCollapsed
                                                ? '추가 정보 보기'
                                                : '추가 정보 접기',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                  height: 1.05,
                                                ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        '$currentTemperatureText · $currentWindText · $currentWindDirectionText',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Colors.white
                                                  .withValues(alpha: 0.72),
                                              fontSize: 11,
                                              height: 1.05,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            _PanelIconButton(
                              icon: session.isPaused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                              tooltip: session.isPaused
                                  ? '비행 기록 다시 시작'
                                  : '비행 기록 일시정지',
                              onPressed: widget.flightRecordManager.isWorking
                                  ? null
                                  : _toggleRecordingState,
                            ),
                            const SizedBox(width: 4),
                            _PanelIconButton(
                              icon: Icons.stop_rounded,
                              tooltip: '비행 기록 종료',
                              onPressed: widget.flightRecordManager.isWorking
                                  ? null
                                  : _stopRecording,
                              destructive: true,
                            ),
                          ],
                        ),
                        if (!_detailsCollapsed) ...[
                          const SizedBox(height: 12),
                          Expanded(
                            child: ListView(
                              padding: EdgeInsets.zero,
                              children: [
                                _ContextCard(
                                  title: '현재 날씨',
                                  trailing: _weatherSnapshot == null
                                      ? null
                                      : Text(
                                          _weatherSnapshot!.sourceLabel,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          _MetricTile(
                                            label: '기온',
                                            value: currentTemperatureText,
                                          ),
                                          _MetricTile(
                                            label: '풍속',
                                            value: currentWindText,
                                          ),
                                          _MetricTile(
                                            label: '풍향',
                                            value: currentWindDirectionText,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        _weatherSnapshot?.summary ??
                                            '현재 위치 기준 날씨를 불러오는 중입니다.',
                                      ),
                                      if (_weatherSnapshot != null) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          '관측 시각 ${formatDateTime(_weatherSnapshot!.observedAt)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                      if (_contextError != null) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          _contextError!,
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _ContextCard(
                                  title: '비행 메모',
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          _MiniInfo(
                                            label: '현재 위치',
                                            value: currentLocationText,
                                          ),
                                          _MiniInfo(
                                            label: '이동 거리',
                                            value: formatDistanceMeters(
                                              metrics.totalDistanceMeters,
                                            ),
                                          ),
                                          _MiniInfo(
                                            label: '진행 방향',
                                            value: formatHeading(
                                              metrics.headingDegrees,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        siteMetadata?.safetyText ??
                                            '배터리와 위치 권한 상태만 확인해 두고, 현장 바람은 마지막으로 한 번 더 확인해 주세요.',
                                      ),
                                      if (trackingNotice != null) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          '${trackingNotice.title} · ${trackingNotice.description}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Colors.white
                                                    .withValues(alpha: 0.78),
                                              ),
                                        ),
                                      ],
                                      if (_siteLoadError != null) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          _siteLoadError!,
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                        ),
                                      ] else if (_loadingSites) ...[
                                        const SizedBox(height: 8),
                                        const Text('비행장 정보를 불러오는 중입니다.'),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final rootNavigator = Navigator.of(context);
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        final shouldClose = await _confirmClose();
        if (!mounted || !shouldClose) {
          return;
        }
        rootNavigator.pop();
      },
      child: AnimatedBuilder(
        animation: widget.flightRecordManager,
        builder: (context, _) {
          final navigator = Navigator.of(context);
          final session = widget.flightRecordManager.activeSession;
          if (session == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('실시간 비행')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('진행 중인 비행 기록이 없습니다.'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('기록 화면으로 돌아가기'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final points = widget.flightRecordManager.activePoints;
          final lastPoint = widget.flightRecordManager.lastPoint;
          final selectedSite = _selectedSiteForSession(session);
          final siteMetadata = _flightGuide.metadataForSite(
            siteId: selectedSite?.id ?? session.siteId,
            siteName: session.siteName,
          );
          final metrics = FlightLiveMetrics.fromSession(
            session: session,
            points: points,
          );
          final currentLocationText = _areaLabel ??
              (lastPoint == null
                  ? '위치 확인 중'
                  : formatCoordinates(
                      lastPoint.latitude,
                      lastPoint.longitude,
                    ));
          final currentWindText = _weatherSnapshot?.windSpeedMps == null
              ? '정보 준비 중'
              : formatSpeedMps(_weatherSnapshot!.windSpeedMps!);
          final currentTemperatureText =
              formatTemperature(_weatherSnapshot?.temperatureCelsius);
          final currentWindDirectionText =
              formatHeading(_weatherSnapshot?.windDirection?.toDouble());
          return Scaffold(
            body: _buildLiveBody(
              context,
              navigator: navigator,
              session: session,
              metrics: metrics,
              points: points,
              siteMetadata: siteMetadata,
              currentLocationText: currentLocationText,
              currentWindText: currentWindText,
              currentTemperatureText: currentTemperatureText,
              currentWindDirectionText: currentWindDirectionText,
            ),
          );
/*
          return Scaffold(
            appBar: AppBar(
              toolbarHeight: 52,
              titleSpacing: 8,
              title: const Text('비행 모드'),
              actions: [
                IconButton(
                  onPressed: _handleManualRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: '날씨와 주변 정보를 새로고침',
                ),
              ],
            ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                const collapsedPanelHeight = 124.0;
                const minExpandedPanelHeight = 280.0;
                final availableHeight = constraints.maxHeight;
                final maxMapHeight =
                    max(220.0, availableHeight - minExpandedPanelHeight);
                final minMapHeight = min(320.0, maxMapHeight);
                final preferredMapHeight = availableHeight * 0.74;
                final mapHeight = _detailsCollapsed
                    ? max(0.0, availableHeight - collapsedPanelHeight)
                    : min(max(preferredMapHeight, minMapHeight), maxMapHeight);
                final detailsHeight = _detailsCollapsed
                    ? collapsedPanelHeight
                    : max(collapsedPanelHeight, availableHeight - mapHeight);

                return Column(
                  children: [
                    SizedBox(
                      height: mapHeight,
                      child: Stack(
                        children: [
                          _mapMode == _LiveFlightMapMode.threeD
                              ? FlightMap3DView(
                                  key: _threeDMapKey,
                                  points: points,
                                  height: mapHeight,
                                  followLocation: _followLocation,
                                  mapViewType: _mapViewType,
                                  siteLatitude: siteMetadata?.latitude,
                                  siteLongitude: siteMetadata?.longitude,
                                  siteLabel: siteMetadata?.name,
                                  onFollowDisabled: () {
                                    if (!mounted || !_followLocation) {
                                      return;
                                    }
                                    setState(() {
                                      _followLocation = false;
                                    });
                                  },
                                )
                              : FlightMapView(
                                  points: points,
                                  height: mapHeight,
                                  mapController: _mapController,
                                  onPositionChanged: _handleMapPositionChanged,
                                  mapViewType: _mapViewType,
                                  emptyMessage: '위치가 확보되면 실시간 비행 지도가 표시됩니다.',
                                  siteLatitude: siteMetadata?.latitude,
                                  siteLongitude: siteMetadata?.longitude,
                                  siteLabel: siteMetadata?.name,
                                ),
                          Positioned(
                            top: 16,
                            left: 16,
                            right: 72,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _FlightStatusStrip(
                                  siteName: session.displaySiteName,
                                  regionName: session.displayRegion,
                                  locationText: currentLocationText,
                                  startedAtText: formatTime(metrics.startedAt),
                                  currentTimeText:
                                      formatTime(metrics.currentTime),
                                  elapsedText: formatDuration(metrics.elapsed),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _InfoBadge(
                                      label: session.status.label,
                                      backgroundColor: session.isPaused
                                          ? const Color(0xFFFFF2DB)
                                          : const Color(0xFFFCE9E4),
                                      textColor: session.isPaused
                                          ? const Color(0xFF8C5B00)
                                          : const Color(0xFFAE4A1E),
                                      icon: session.isPaused
                                          ? Icons.pause_rounded
                                          : Icons.fiber_manual_record_rounded,
                                    ),
                                    _InfoBadge(
                                      label: metrics.locationStatusLabel,
                                      backgroundColor:
                                          metrics.accuracyMeters != null &&
                                                  metrics.accuracyMeters! <= 25
                                              ? const Color(0xFFE7F4EE)
                                              : const Color(0xFFFFF2DB),
                                      textColor:
                                          metrics.accuracyMeters != null &&
                                                  metrics.accuracyMeters! <= 25
                                              ? const Color(0xFF217A4C)
                                              : const Color(0xFF8C5B00),
                                      icon: Icons.gps_fixed_rounded,
                                    ),
                                    if (!_followLocation)
                                      const _InfoBadge(
                                        label: '자동 추적 해제됨',
                                        backgroundColor: Color(0xFFFFF2DB),
                                        textColor: Color(0xFF8C5B00),
                                        icon: Icons.pan_tool_alt_rounded,
                                      ),
                                    if (_refreshingContext)
                                      const _InfoBadge(
                                        label: '날씨 갱신 중',
                                        backgroundColor: Color(0xFFE8F0F8),
                                        textColor: Color(0xFF29546C),
                                        icon: Icons.cloud_sync_rounded,
                                      ),
                                    if (zoneAdvisory != null &&
                                        zoneAdvisory.status !=
                                            KoreaZoneStatus.flyable)
                                      _InfoBadge(
                                        label: zoneAdvisory.status.label,
                                        backgroundColor: _zoneBackgroundColor(
                                          zoneAdvisory.status,
                                        ),
                                        textColor:
                                            _zoneTextColor(zoneAdvisory.status),
                                        icon: Icons.verified_user_outlined,
                                      ),
                                  ],
                                ),
                                if (trackingNotice != null) ...[
                                  const SizedBox(height: 8),
                                  _TrackingNoticeBanner(notice: trackingNotice),
                                ],
                              ],
                            ),
                          ),
                          Positioned(
                            top: 16,
                            right: 16,
                            child: Material(
                              color: _followLocation
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.94)
                                  : Colors.white.withValues(alpha: 0.94),
                              shape: const CircleBorder(),
                              elevation: 4,
                              child: IconButton(
                                onPressed: _recenter,
                                color: _followLocation
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.primary,
                                icon: Icon(
                                  _followLocation
                                      ? Icons.gps_fixed_rounded
                                      : Icons.my_location_rounded,
                                ),
                                tooltip: _followLocation
                                    ? '현재 위치 자동 추적 중'
                                    : '현재 위치로 이동',
                              ),
                            ),
                          ),
                          Positioned(
                            top: 72,
                            right: 16,
                            child: MapViewToggle(
                              value: _mapViewType,
                              onChanged: _changeMapViewType,
                            ),
                          ),
                          Positioned(
                            top: 128,
                            right: 16,
                            child: _FlightMapModeToggle(
                              value: _mapMode,
                              onChanged: _changeMapMode,
                            ),
                          ),
                          Positioned(
                            right: 16,
                            bottom: 16,
                            left: 16,
                            child: _HeroMetricsCard(
                              currentAltitudeText: formatAltitudeMeters(
                                  metrics.currentAltitudeMeters),
                              maxAltitudeText: formatAltitudeMeters(
                                session.maxAltitudeMeters,
                              ),
                              speedText:
                                  formatSpeedKmh(metrics.currentSpeedMps),
                              verticalSpeedText:
                                  formatVerticalSpeed(metrics.verticalSpeedMps),
                              distanceText: formatDistanceMeters(
                                  metrics.totalDistanceMeters),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      height: detailsHeight,
                      child: Column(
                        children: [
                          _buildDetailsToggleBar(
                            context,
                            summaryText:
                                '$currentTemperatureText · $currentWindText · $currentWindDirectionText',
                          ),
                          if (!_detailsCollapsed)
                            Expanded(
                              child: ListView(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 24),
                                children: [
                                  _ContextCard(
                                    title: '비행 상태 요약',
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${session.displayRegion} / ${session.displaySiteName}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          zoneAdvisory?.summary ??
                                              '현재 위치 기준 참고 상태를 계산 중입니다.',
                                        ),
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 10,
                                          runSpacing: 10,
                                          children: [
                                            _MiniInfo(
                                                label: '시작 시각',
                                                value: formatTime(
                                                    metrics.startedAt)),
                                            _MiniInfo(
                                                label: '현재 시각',
                                                value: formatTime(
                                                    metrics.currentTime)),
                                            _MiniInfo(
                                              label: '현재 위치',
                                              value: currentLocationText,
                                            ),
                                            _MiniInfo(
                                              label: '위치 상태',
                                              value:
                                                  metrics.locationStatusLabel,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _ContextCard(
                                    title: '현재 온도와 바람',
                                    trailing: _weatherSnapshot == null
                                        ? null
                                        : Text(
                                            _weatherSnapshot!.sourceLabel,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (_refreshingContext)
                                          const Padding(
                                            padding:
                                                EdgeInsets.only(bottom: 12),
                                            child: LinearProgressIndicator(
                                                minHeight: 3),
                                          ),
                                        Wrap(
                                          spacing: 10,
                                          runSpacing: 10,
                                          children: [
                                            _MetricTile(
                                              label: '현재 온도',
                                              value: formatTemperature(
                                                  _weatherSnapshot
                                                      ?.temperatureCelsius),
                                            ),
                                            _MetricTile(
                                              label: '평균 바람',
                                              value: _weatherSnapshot
                                                          ?.windSpeedMps ==
                                                      null
                                                  ? '정보 준비 중'
                                                  : formatSpeedMps(
                                                      _weatherSnapshot!
                                                          .windSpeedMps!,
                                                    ),
                                            ),
                                            _MetricTile(
                                              label: '풍향',
                                              value: formatHeading(
                                                  _weatherSnapshot
                                                      ?.windDirection
                                                      ?.toDouble()),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          _weatherSnapshot?.summary ??
                                              '위치 기반 기온과 등록 비행장 바람 정보를 가져오는 중입니다.',
                                        ),
                                        if (_contextError != null) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            _contextError!,
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                            ),
                                          ),
                                        ],
                                        if (_weatherSnapshot != null) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            '관측 시각 ${formatDateTime(_weatherSnapshot!.observedAt)}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _ContextCard(
                                    title: '실시간 비행 지표',
                                    child: Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        _MetricTile(
                                          label: '이동 거리',
                                          value: formatDistanceMeters(
                                              metrics.totalDistanceMeters),
                                        ),
                                        _MetricTile(
                                          label: '진행 방향',
                                          value: formatHeading(
                                              metrics.headingDegrees),
                                        ),
                                        _MetricTile(
                                          label: 'GPS 정확도',
                                          value: formatAccuracy(
                                              metrics.accuracyMeters),
                                        ),
                                        _MetricTile(
                                          label: '기록 상태',
                                          value: metrics.hasTakeoffSignal
                                              ? '비행 추적 중'
                                              : '이륙 대기',
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _ContextCard(
                                    title: zoneAdvisory?.title ??
                                        '현재 위치 기준 참고용 구역 상태',
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          zoneAdvisory?.status.label ?? '확인 중',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          zoneAdvisory?.detail ??
                                              '위치가 확보되면 한국형 참고용 구역 상태를 표시합니다.',
                                        ),
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 10,
                                          runSpacing: 10,
                                          children: [
                                            _MiniInfo(
                                              label: '신뢰 수준',
                                              value: zoneAdvisory
                                                      ?.confidence.label ??
                                                  '확인 중',
                                            ),
                                            _MiniInfo(
                                              label: '기준 비행장',
                                              value: zoneAdvisory
                                                      ?.nearbySite?.name ??
                                                  selectedSite?.name ??
                                                  '주변 비행장 확인 중',
                                            ),
                                            if (zoneAdvisory?.distanceMeters !=
                                                null)
                                              _MiniInfo(
                                                label: '기준 비행장 거리',
                                                value: formatDistanceMeters(
                                                    zoneAdvisory!
                                                        .distanceMeters!),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          zoneAdvisory?.disclaimer ??
                                              '정확한 공역 정보는 추가 확인이 필요합니다.',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _ContextCard(
                                    title: '안전 안내',
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          siteMetadata?.safetyText ??
                                              '기록 중에는 위치 추적을 계속 유지합니다. 장시간 비행 전에는 위치 권한과 배터리 최적화 예외를 함께 확인해 주세요.',
                                        ),
                                        if (_siteLoadError != null) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            _siteLoadError!,
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                            ),
                                          ),
                                        ] else if (_loadingSites) ...[
                                          const SizedBox(height: 8),
                                          const Text('비행장 기준 정보를 불러오는 중입니다.'),
                                        ],
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton(
                                      onPressed: () async {
                                        final shouldClose =
                                            await _confirmClose();
                                        if (!mounted || !shouldClose) {
                                          return;
                                        }
                                        navigator.pop();
                                      },
                                      child: const Text('기록은 유지한 채 화면 닫기'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          );
*/
        },
      ),
    );
  }

  Color _zoneBackgroundColor(KoreaZoneStatus status) {
    return switch (status) {
      KoreaZoneStatus.flyable => const Color(0xFFE7F4EE),
      KoreaZoneStatus.caution => const Color(0xFFFFF2DB),
      KoreaZoneStatus.confirmationRequired => const Color(0xFFFFEFE0),
      KoreaZoneStatus.potentiallyRestricted => const Color(0xFFFCE9E4),
    };
  }

  Color _zoneTextColor(KoreaZoneStatus status) {
    return switch (status) {
      KoreaZoneStatus.flyable => const Color(0xFF217A4C),
      KoreaZoneStatus.caution => const Color(0xFF8C5B00),
      KoreaZoneStatus.confirmationRequired => const Color(0xFFB06500),
      KoreaZoneStatus.potentiallyRestricted => const Color(0xFFAE4A1E),
    };
  }
}

class _FlightStatusStrip extends StatelessWidget {
  const _FlightStatusStrip({
    required this.siteName,
    required this.regionName,
    required this.locationText,
    required this.startedAtText,
    required this.currentTimeText,
    required this.elapsedText,
    required this.statusLabel,
  });

  final String siteName;
  final String regionName;
  final String locationText;
  final String startedAtText;
  final String currentTimeText;
  final String elapsedText;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1C24).withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  siteName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFD94B4B),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$regionName · $locationText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.76),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _HeaderStat(label: '시작', value: startedAtText),
              _HeaderStat(label: '현재', value: currentTimeText),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: _HeaderStat(label: '경과', value: elapsedText),
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FlightMapModeToggle extends StatelessWidget {
  const _FlightMapModeToggle({
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final _LiveFlightMapMode value;
  final ValueChanged<_LiveFlightMapMode> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(compact ? 14 : 16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 3 : 4),
        child: SegmentedButton<_LiveFlightMapMode>(
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: WidgetStateProperty.all(
              EdgeInsets.symmetric(
                horizontal: compact ? 8 : 10,
                vertical: compact ? 5 : 6,
              ),
            ),
          ),
          segments: const [
            ButtonSegment<_LiveFlightMapMode>(
              value: _LiveFlightMapMode.twoD,
              label: Text('2D'),
              icon: Icon(Icons.map_outlined, size: 16),
            ),
            ButtonSegment<_LiveFlightMapMode>(
              value: _LiveFlightMapMode.threeD,
              label: Text('3D'),
              icon: Icon(Icons.threed_rotation_rounded, size: 16),
            ),
          ],
          selected: {value},
          onSelectionChanged: (selection) {
            if (selection.isEmpty) {
              return;
            }
            onChanged(selection.first);
          },
        ),
      ),
    );
  }
}

class _HeroMetricsCard extends StatelessWidget {
  const _HeroMetricsCard({
    required this.currentAltitudeText,
    required this.maxAltitudeText,
    required this.speedText,
    required this.verticalSpeedText,
    required this.distanceText,
  });

  final String currentAltitudeText;
  final String maxAltitudeText;
  final String speedText;
  final String verticalSpeedText;
  final String distanceText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 520;
          final items = [
            _HeroValue(label: '현재 고도', value: currentAltitudeText),
            _HeroValue(label: '최고 고도', value: maxAltitudeText),
            _HeroValue(label: '현재 속도', value: speedText),
            _HeroValue(label: '상승/하강률', value: verticalSpeedText),
          ];

          final primaryWidth = isCompact
              ? (constraints.maxWidth - 10) / 2
              : (constraints.maxWidth - 12) / 2;
          final secondaryWidth = isCompact
              ? (constraints.maxWidth - 16) / 3
              : (constraints.maxWidth - 16) / 3;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  SizedBox(width: primaryWidth, child: items[0]),
                  SizedBox(width: primaryWidth, child: items[1]),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(width: secondaryWidth, child: items[2]),
                  SizedBox(width: secondaryWidth, child: items[3]),
                  SizedBox(
                    width: secondaryWidth,
                    child: _HeroValue(
                      label: '이동 거리',
                      value: distanceText,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeroValue extends StatelessWidget {
  const _HeroValue({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isPrimary = label.contains('고도');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF5E6D76),
              ),
        ),
        SizedBox(height: isPrimary ? 6 : 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (isPrimary
                  ? Theme.of(context).textTheme.headlineSmall
                  : Theme.of(context).textTheme.titleMedium)
              ?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF17324D),
          ),
        ),
      ],
    );
  }
}

class _TrackingNoticeBanner extends StatelessWidget {
  const _TrackingNoticeBanner({required this.notice});

  final FlightTrackingNotice notice;

  @override
  Widget build(BuildContext context) {
    final scheme = switch (notice.tone) {
      FlightTrackingNoticeTone.info => (
          background: const Color(0xFFE8F0F8),
          border: const Color(0xFFB8CFDF),
          foreground: const Color(0xFF29546C),
          icon: Icons.sync_rounded,
        ),
      FlightTrackingNoticeTone.caution => (
          background: const Color(0xFFFFF4DE),
          border: const Color(0xFFE9C46A),
          foreground: const Color(0xFF8C5B00),
          icon: Icons.gps_off_rounded,
        ),
      FlightTrackingNoticeTone.warning => (
          background: const Color(0xFFFDE9E4),
          border: const Color(0xFFE5987A),
          foreground: const Color(0xFF9A3412),
          icon: Icons.warning_amber_rounded,
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.background.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(scheme.icon, size: 18, color: scheme.foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.foreground,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  notice.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.foreground,
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextCard extends StatelessWidget {
  const _ContextCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 136,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  const _MiniInfo({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
          children: [
            TextSpan(
              text: '$label  ',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    required this.icon,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: textColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapOverlayActionButton extends StatelessWidget {
  const _MapOverlayActionButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      child: Material(
        color: const Color(0xFF0F1C24).withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 17, color: Colors.white),
          ),
        ),
      ),
    );

    if (tooltip == null || tooltip!.isEmpty) {
      return button;
    }
    return Tooltip(message: tooltip!, child: button);
  }
}

class _PanelIconButton extends StatelessWidget {
  const _PanelIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.destructive = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      child: Material(
        color: destructive
            ? const Color(0x55D94B4B)
            : Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              icon,
              size: 17,
              color: destructive
                  ? const Color(0xFFFFD9D9)
                  : Colors.white.withValues(alpha: 0.94),
            ),
          ),
        ),
      ),
    );

    if (tooltip == null || tooltip!.isEmpty) {
      return button;
    }
    return Tooltip(message: tooltip!, child: button);
  }
}

class _CompactFlightStatusStrip extends StatelessWidget {
  const _CompactFlightStatusStrip({
    required this.siteName,
    required this.regionName,
    required this.locationText,
    required this.startedAtText,
    required this.currentTimeText,
    required this.elapsedText,
    required this.statusLabel,
  });

  final String siteName;
  final String regionName;
  final String locationText;
  final String startedAtText;
  final String currentTimeText;
  final String elapsedText;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = siteName.trim() == '사이트 미지정' ? '미지정' : siteName.trim();
    final subtitle = [
      if (regionName.trim().isNotEmpty && regionName.trim() != title)
        regionName.trim(),
      locationText.trim(),
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1C24).withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFD94B4B),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.70),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              _CompactHeaderStat(label: '시작', value: startedAtText),
              _CompactHeaderStat(label: '현재', value: currentTimeText),
            ],
          ),
          const SizedBox(height: 5),
          Align(
            alignment: Alignment.centerLeft,
            child: _CompactHeaderStat(label: '경과', value: elapsedText),
          ),
        ],
      ),
    );
  }
}

class _CompactHeaderStat extends StatelessWidget {
  const _CompactHeaderStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
      ),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.labelSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.72),
          ),
          children: [
            TextSpan(text: '$label '),
            TextSpan(
              text: value,
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactFlightMapModeToggle extends StatelessWidget {
  const _CompactFlightMapModeToggle({
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final _LiveFlightMapMode value;
  final ValueChanged<_LiveFlightMapMode> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(compact ? 3 : 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(compact ? 14 : 16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _LiveFlightMapMode.values.map((mode) {
          final selected = mode == value;
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 1 : 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(compact ? 11 : 14),
              onTap: selected ? null : () => onChanged(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 9 : 12,
                  vertical: compact ? 7 : 9,
                ),
                decoration: BoxDecoration(
                  color:
                      selected ? theme.colorScheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(compact ? 11 : 14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      mode == _LiveFlightMapMode.twoD
                          ? Icons.map_outlined
                          : Icons.threed_rotation_rounded,
                      size: compact ? 14 : 16,
                      color: selected ? Colors.white : const Color(0xFF304654),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      mode == _LiveFlightMapMode.twoD ? '2D' : '3D',
                      style: (compact
                              ? theme.textTheme.labelMedium
                              : theme.textTheme.labelLarge)
                          ?.copyWith(
                        color:
                            selected ? Colors.white : const Color(0xFF304654),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class _CompactHeroMetricsCard extends StatelessWidget {
  const _CompactHeroMetricsCard({
    required this.currentAltitudeText,
    required this.maxAltitudeText,
    required this.speedText,
    required this.verticalSpeedText,
    required this.distanceText,
  });

  final String currentAltitudeText;
  final String maxAltitudeText;
  final String speedText;
  final String verticalSpeedText;
  final String distanceText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final primaryWidth = (constraints.maxWidth - 10) / 2;
          final secondaryWidth = (constraints.maxWidth - 16) / 3;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: primaryWidth,
                    child: _CompactHeroValue(
                      label: '현재 고도',
                      value: currentAltitudeText,
                      primary: true,
                    ),
                  ),
                  SizedBox(
                    width: primaryWidth,
                    child: _CompactHeroValue(
                      label: '최고 고도',
                      value: maxAltitudeText,
                      primary: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  SizedBox(
                    width: secondaryWidth,
                    child: _CompactHeroValue(label: '현재 속도', value: speedText),
                  ),
                  SizedBox(
                    width: secondaryWidth,
                    child: _CompactHeroValue(
                      label: '상승·하강',
                      value: verticalSpeedText,
                    ),
                  ),
                  SizedBox(
                    width: secondaryWidth,
                    child:
                        _CompactHeroValue(label: '이동 거리', value: distanceText),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CompactHeroValue extends StatelessWidget {
  const _CompactHeroValue({
    required this.label,
    required this.value,
    this.primary = false,
  });

  final String label;
  final String value;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF5E6D76),
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: primary ? 4 : 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (primary
                  ? theme.textTheme.headlineSmall
                  : theme.textTheme.titleMedium)
              ?.copyWith(
            color: const Color(0xFF17324D),
            fontWeight: FontWeight.w800,
            fontSize: primary ? 26 : 17,
          ),
        ),
      ],
    );
  }
}
