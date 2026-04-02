import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/rendering.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:share_plus/share_plus.dart';

import '../core/app_config.dart';
import '../core/flight_analysis_replay.dart';
import '../core/flight_analysis_summary.dart';
import '../core/korea_flight_guide.dart';
import '../core/map_view_type.dart';
import '../core/utils.dart';
import '../models/app_models.dart';
import 'flight_analysis_3d_view.dart';
import 'flight_map_view.dart';
import 'map_view_toggle.dart';

enum FlightAnalysisViewMode { twoD, threeD }

class FlightAnalysisReplaySection extends StatefulWidget {
  const FlightAnalysisReplaySection({
    super.key,
    required this.detail,
    required this.summary,
    required this.siteMetadata,
    required this.selectedMoment,
    required this.onFocusMoment,
    required this.mapController,
    required this.mapViewType,
    required this.onMapViewTypeChanged,
    this.fullscreen = false,
    this.startInThreeD = false,
    this.initialReplayTimestamp,
    this.initialCameraMode = FlightReplayCameraMode.overview,
    this.initialAutoCameraEnabled = true,
    this.onCloseFullscreen,
  });

  final FlightSessionDetail detail;
  final FlightAnalysisSummary summary;
  final KoreaFlightSiteMetadata? siteMetadata;
  final FlightAnalysisMoment? selectedMoment;
  final ValueChanged<FlightAnalysisMoment> onFocusMoment;
  final MapController mapController;
  final ParaglidingMapViewType mapViewType;
  final ValueChanged<ParaglidingMapViewType> onMapViewTypeChanged;
  final bool fullscreen;
  final bool startInThreeD;
  final DateTime? initialReplayTimestamp;
  final FlightReplayCameraMode initialCameraMode;
  final bool initialAutoCameraEnabled;
  final VoidCallback? onCloseFullscreen;

  @override
  State<FlightAnalysisReplaySection> createState() =>
      _FlightAnalysisReplaySectionState();
}

class _FlightAnalysisReplaySectionState
    extends State<FlightAnalysisReplaySection> {
  Timer? _playbackTimer;
  DateTime? _lastPlaybackTickAt;
  FlightAnalysisViewMode _viewMode = FlightAnalysisViewMode.twoD;
  FlightReplayCameraMode _cameraMode = FlightReplayCameraMode.overview;
  FlightReplayData _replayData = const FlightReplayData(
    frames: [],
    highestFrameIndex: 0,
    takeoffFrameIndex: 0,
    landingFrameIndex: 0,
    thermalSegments: [],
    totalDuration: Duration.zero,
    totalDistanceMeters: 0,
    minAltitudeMeters: 0,
    maxAltitudeMeters: 0,
  );
  List<FlightTrackPoint> _orderedPoints = const [];
  int _replayIndex = 0;
  double _rangeProgress = 0.0;
  double _playbackSpeed = 1.0;
  FlightReplaySegment? _selectedSegment;
  bool _autoCameraEnabled = true;
  bool _secondaryPanelExpanded = false;
  bool _exportingReplay = false;
  final GlobalKey<FlightAnalysis3DViewState> _threeDViewKey =
      GlobalKey<FlightAnalysis3DViewState>();
  final GlobalKey _twoDReplayBoundaryKey = GlobalKey();

  bool get _isPlaying => _playbackTimer != null;
  bool get _canUse3D => _replayData.frames.length >= 2;
  bool get _supportsThreeDOnCurrentPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get _hasMapboxSetup => AppConfig.hasMapboxAccessToken;
  bool get _hasThreeDEntryReady =>
      _supportsThreeDOnCurrentPlatform && _hasMapboxSetup && _canUse3D;
  int get _safeReplayIndex => _clampReplayIndex(_replayIndex);
  int get _selectedRangeStart => _selectedSegment?.startIndex ?? 0;
  int get _selectedRangeEnd =>
      _selectedSegment?.endIndex ?? max(0, _replayData.frames.length - 1);
  bool get _canReplay => _replayData.frames.length >= 2;
  FlightReplayFrame? get _currentFrame => _replayData.frames.isEmpty
      ? null
      : _replayData.sampleFrameForProgress(
          _selectedSegmentProgress,
          startIndex: _selectedRangeStart,
          endIndex: _selectedRangeEnd,
        );
  Duration get _selectedRangeDuration => _replayData.durationForRange(
        startIndex: _selectedRangeStart,
        endIndex: _selectedRangeEnd,
      );

  double get _selectedSegmentProgress {
    return _rangeProgress.clamp(0.0, 1.0);
  }

  FlightReplaySegment? get _currentThermalSegment {
    for (final segment in _replayData.thermalSegments) {
      if (_safeReplayIndex >= segment.startIndex &&
          _safeReplayIndex <= segment.endIndex) {
        return segment;
      }
    }
    return null;
  }

  FlightReplaySegment? get _takeoffSegment {
    if (_replayData.frames.length < 2 || _replayData.takeoffFrameIndex <= 0) {
      return null;
    }
    final endIndex = min(
      _replayData.takeoffFrameIndex,
      _replayData.frames.length - 1,
    );
    final endFrame = _replayData.frames[endIndex];
    return FlightReplaySegment(
      type: FlightReplaySegmentType.takeoff,
      label: '이륙 구간',
      startIndex: 0,
      endIndex: endIndex,
      duration: endFrame.elapsedDuration,
      altitudeGainMeters: endFrame.altitudeFromStartMeters,
      maxClimbRateMps: _replayData.frames.take(endIndex + 1).fold<double>(
            0,
            (previousValue, frame) =>
                max(previousValue, frame.verticalSpeedMps),
          ),
    );
  }

  FlightReplaySegment? get _landingSegment {
    if (_replayData.frames.length < 2 ||
        _replayData.landingFrameIndex >= _replayData.frames.length - 1) {
      return null;
    }
    final startIndex = max(0, _replayData.landingFrameIndex);
    final startFrame = _replayData.frames[startIndex];
    final endFrame = _replayData.frames.last;
    return FlightReplaySegment(
      type: FlightReplaySegmentType.landing,
      label: '착륙 구간',
      startIndex: startIndex,
      endIndex: _replayData.frames.length - 1,
      duration: endFrame.elapsedDuration - startFrame.elapsedDuration,
      altitudeGainMeters:
          endFrame.displayAltitudeMeters - startFrame.displayAltitudeMeters,
      maxClimbRateMps: _replayData.frames.skip(startIndex).fold<double>(
            0,
            (previousValue, frame) =>
                max(previousValue, frame.verticalSpeedMps),
          ),
    );
  }

  @override
  void initState() {
    super.initState();
    _viewMode = widget.startInThreeD
        ? FlightAnalysisViewMode.threeD
        : FlightAnalysisViewMode.twoD;
    _cameraMode = widget.initialCameraMode;
    _autoCameraEnabled = widget.initialAutoCameraEnabled;
    _refreshReplayData(useInitialReplayPosition: true);
  }

  @override
  void didUpdateWidget(covariant FlightAnalysisReplaySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.session.id != widget.detail.session.id ||
        oldWidget.detail.points.length != widget.detail.points.length) {
      _cameraMode = widget.initialCameraMode;
      _autoCameraEnabled = widget.initialAutoCameraEnabled;
      _secondaryPanelExpanded = false;
      _refreshReplayData();
      return;
    }
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _lastPlaybackTickAt = null;
    super.dispose();
  }

  void _refreshReplayData({bool useInitialReplayPosition = false}) {
    _playbackTimer?.cancel();
    _lastPlaybackTickAt = null;
    _orderedPoints = List<FlightTrackPoint>.from(widget.detail.points)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _replayData = FlightReplayData.fromPoints(_orderedPoints);
    _replayIndex = useInitialReplayPosition &&
            widget.initialReplayTimestamp != null &&
            _replayData.hasFrames
        ? _replayData.nearestFrameIndex(widget.initialReplayTimestamp!)
        : 0;
    _selectedSegment = null;
    _rangeProgress = _replayData.hasFrames
        ? _replayData.progressForIndex(
            _replayIndex,
            startIndex: _selectedRangeStart,
            endIndex: _selectedRangeEnd,
          )
        : 0.0;
    _playbackSpeed = 1.0;
  }

  void _setViewMode(FlightAnalysisViewMode mode) {
    if (_viewMode == mode) {
      return;
    }
    setState(() {
      _viewMode = mode;
    });
  }

  void _togglePlayback() {
    if (!_canReplay) {
      return;
    }

    if (_isPlaying) {
      _playbackTimer?.cancel();
      _lastPlaybackTickAt = null;
      setState(() {});
      return;
    }

    final rangeStart = _selectedRangeStart;
    final rangeEnd = _selectedRangeEnd;
    if (_safeReplayIndex < rangeStart ||
        _safeReplayIndex > rangeEnd ||
        _selectedSegmentProgress >= 0.999) {
      _replayIndex = rangeStart;
      _rangeProgress = 0.0;
    }

    _lastPlaybackTickAt = DateTime.now();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted || _replayData.frames.isEmpty) {
        return;
      }

      final now = DateTime.now();
      final lastTickAt = _lastPlaybackTickAt ?? now;
      _lastPlaybackTickAt = now;
      final tickDuration = now.difference(lastTickAt);
      if (tickDuration <= Duration.zero) {
        return;
      }

      final targetDuration = _targetPlaybackDuration();
      final currentProgress = _selectedSegmentProgress;
      final progressDelta =
          (tickDuration.inMilliseconds / targetDuration.inMilliseconds) *
              _playbackSpeed;
      final nextProgress = (currentProgress + progressDelta).clamp(0.0, 1.0);
      final nextIndex = _replayData.indexForProgress(
        nextProgress,
        startIndex: rangeStart,
        endIndex: rangeEnd,
      );

      setState(() {
        _rangeProgress = nextProgress;
        _replayIndex = nextIndex;
      });

      if (nextProgress >= 1.0 || nextIndex >= rangeEnd) {
        _playbackTimer?.cancel();
        _lastPlaybackTickAt = null;
      }
    });
    setState(() {});
  }

  void _seekToIndex(int index, {bool stopPlayback = true}) {
    if (stopPlayback) {
      _playbackTimer?.cancel();
      _lastPlaybackTickAt = null;
    }
    final nextIndex = _clampReplayIndex(index);
    setState(() {
      _replayIndex = nextIndex;
      _rangeProgress = _replayData.progressForIndex(
        nextIndex,
        startIndex: _selectedRangeStart,
        endIndex: _selectedRangeEnd,
      );
    });
  }

  void _seekToProgress(double progress, {bool stopPlayback = true}) {
    if (stopPlayback) {
      _playbackTimer?.cancel();
      _lastPlaybackTickAt = null;
    }
    final nextProgress = progress.clamp(0.0, 1.0);
    setState(() {
      _rangeProgress = nextProgress;
      _replayIndex = _replayData.indexForProgress(
        nextProgress,
        startIndex: _selectedRangeStart,
        endIndex: _selectedRangeEnd,
      );
    });
  }

  void _selectSegment(FlightReplaySegment? segment) {
    _playbackTimer?.cancel();
    _lastPlaybackTickAt = null;
    setState(() {
      _selectedSegment = segment;
      _replayIndex = segment?.startIndex ?? _selectedRangeStart;
      _rangeProgress = 0.0;
    });
  }

  Duration _targetPlaybackDuration() {
    final rangeSeconds = max(1, _selectedRangeDuration.inSeconds);
    final suggestedSeconds = (rangeSeconds / 60).round().clamp(28, 96);
    return Duration(seconds: suggestedSeconds);
  }

  int _clampReplayIndex(int index) {
    if (_replayData.frames.isEmpty) {
      return 0;
    }
    return min(max(index, 0), _replayData.frames.length - 1);
  }

  String _segmentStateLabel(double verticalSpeed) {
    if (verticalSpeed >= 0.8) {
      return '상승 구간';
    }
    if (verticalSpeed <= -0.8) {
      return '하강 구간';
    }
    return '순항 구간';
  }

  String _signedAltitudeText(
    double value, {
    String zeroLabel = '이륙 고도와 유사',
  }) {
    if (value.abs() < 1) {
      return zeroLabel;
    }
    final prefix = value > 0 ? '+' : '';
    return '$prefix${value.toStringAsFixed(0)}m';
  }

  FlightReplayCameraMode _effectiveCameraMode(FlightReplayFrame currentFrame) {
    if (!_autoCameraEnabled) {
      return _cameraMode;
    }

    final rangeProgress = _selectedSegment == null
        ? currentFrame.progress
        : _selectedSegmentProgress;
    final onThermal = _currentThermalSegment != null ||
        (_safeReplayIndex - _replayData.highestFrameIndex).abs() <= 2;

    if (!_isPlaying && rangeProgress >= 0.96) {
      return FlightReplayCameraMode.overview;
    }
    if (rangeProgress <= 0.08) {
      return FlightReplayCameraMode.overview;
    }
    if (_safeReplayIndex <= _replayData.takeoffFrameIndex + 3) {
      return FlightReplayCameraMode.sideView;
    }
    if (onThermal) {
      return FlightReplayCameraMode.sideView;
    }
    if (_safeReplayIndex >= _replayData.landingFrameIndex ||
        rangeProgress >= 0.88) {
      return FlightReplayCameraMode.follow;
    }
    return FlightReplayCameraMode.perspective;
  }

  String _autoCameraStageLabel(FlightReplayFrame currentFrame) {
    if (!_autoCameraEnabled) {
      return '수동 시점';
    }

    final rangeProgress = _selectedSegment == null
        ? currentFrame.progress
        : _selectedSegmentProgress;
    final onThermal = _currentThermalSegment != null ||
        (_safeReplayIndex - _replayData.highestFrameIndex).abs() <= 2;

    if (!_isPlaying && rangeProgress >= 0.96) {
      return '자동 연출 · 마무리 전체 보기';
    }
    if (rangeProgress <= 0.08) {
      return '자동 연출 · 전체 경로 진입';
    }
    if (_safeReplayIndex <= _replayData.takeoffFrameIndex + 3) {
      return '자동 연출 · 이륙 강조';
    }
    if (onThermal) {
      return '자동 연출 · 써멀 강조';
    }
    if (_safeReplayIndex >= _replayData.landingFrameIndex ||
        rangeProgress >= 0.88) {
      return '자동 연출 · 착륙 정리';
    }
    return '자동 연출 · 경로 따라가기';
  }

  void _toggleSecondaryPanel() {
    setState(() {
      _secondaryPanelExpanded = !_secondaryPanelExpanded;
    });
  }

  Future<void> _openFullscreen() async {
    if (!_replayData.hasFrames) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FlightReplayFullscreenScreen(
          detail: widget.detail,
          summary: widget.summary,
          siteMetadata: widget.siteMetadata,
          selectedMoment: widget.selectedMoment,
          initialMapViewType: widget.mapViewType,
          startInThreeD: _viewMode == FlightAnalysisViewMode.threeD,
          initialReplayTimestamp: _currentFrame?.timestamp,
          initialCameraMode: _cameraMode,
          initialAutoCameraEnabled: _autoCameraEnabled,
        ),
      ),
    );
  }

  Future<void> _showExportOptions() async {
    if (!widget.fullscreen) {
      return;
    }

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
                '리플레이 내보내기',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                '현재는 리플레이 장면 이미지를 바로 공유할 수 있습니다. 연속 영상 내보내기는 다음 단계에서 더 확장할 수 있도록 준비해 두었습니다.',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _exportingReplay
                      ? null
                      : () async {
                          Navigator.pop(sheetContext);
                          await _shareReplayImage();
                        },
                  icon: const Icon(Icons.image_outlined),
                  label: Text(
                    _exportingReplay ? '이미지 준비 중...' : '현재 장면 이미지 공유',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    await Share.share(_buildReplayShareText());
                  },
                  icon: const Icon(Icons.notes_rounded),
                  label: const Text('분석 요약 텍스트 공유'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareReplayImage() async {
    if (_exportingReplay) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _exportingReplay = true;
    });

    try {
      final bytes = await _captureReplayImage();
      if (bytes == null || bytes.isEmpty) {
        throw StateError('리플레이 이미지를 만들지 못했습니다.');
      }

      final currentFrame = _currentFrame;
      final fileName = currentFrame == null
          ? 'flight-replay.png'
          : 'flight-replay-${currentFrame.timestamp.millisecondsSinceEpoch}.png';

      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'image/png',
            name: fileName,
          ),
        ],
        text: _buildReplayShareText(),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('리플레이 이미지를 만들지 못했습니다. 잠시 후 다시 시도해 주세요.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exportingReplay = false;
        });
      }
    }
  }

  Future<Uint8List?> _captureReplayImage() async {
    if (_viewMode == FlightAnalysisViewMode.threeD) {
      return _threeDViewKey.currentState?.captureSnapshot();
    }

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return null;
    }
    final boundary = _twoDReplayBoundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) {
      return null;
    }

    final image = await boundary.toImage(pixelRatio: 2.2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  String _buildReplayShareText() {
    final currentFrame = _currentFrame;
    final resolvedStartedAt = widget.detail.resolvedStartedAt;
    final resolvedEndedAt = widget.detail.resolvedEndedAt;
    return [
      '비행 리플레이 요약',
      widget.detail.session.displaySiteName,
      '시작 ${formatDateTime(resolvedStartedAt)}',
      if (resolvedEndedAt != null) '종료 ${formatDateTime(resolvedEndedAt)}',
      '총 비행 시간 ${formatDuration(widget.detail.resolvedDuration)}',
      if (currentFrame != null)
        '현재 재생 시점 ${formatTime(currentFrame.timestamp)} · ${formatAltitudeMeters(currentFrame.altitudeMeters)}',
      '최고 고도 ${formatAltitudeMeters(_replayData.highestFrame?.altitudeMeters ?? widget.detail.session.maxAltitudeMeters)}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final currentFrame = _currentFrame;

    if (widget.fullscreen) {
      return _buildFullscreenReplay(context, currentFrame);
    }

    final highestFrame = _replayData.highestFrame;
    final highestPoint = widget.summary.highestPoint;
    final fastestPoint = widget.summary.fastestPoint;
    final startedAt = widget.detail.resolvedStartedAt;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EmbeddedReplayHeader(
              title: _viewMode == FlightAnalysisViewMode.threeD
                  ? '입체 비행 리플레이'
                  : '비행 경로 리플레이',
              description: _viewMode == FlightAnalysisViewMode.threeD
                  ? '지형과 고도 흐름을 함께 보며 실제 비행 경로를 더 입체적으로 복기해 보세요.'
                  : '핵심 시점과 경로를 빠르게 훑어보며 비행 흐름을 부드럽게 정리해 보세요.',
            ),
            const SizedBox(height: 10),
            _buildEmbeddedReplayToolbar(context),
            const SizedBox(height: 10),
            _buildEmbeddedReplaySummaryRow(
              context,
              startTimeText: formatTime(startedAt),
              highestAltitudeText: formatAltitudeMeters(
                highestFrame?.altitudeMeters ??
                    widget.detail.session.maxAltitudeMeters,
              ),
              highestAltitudeHint: formatTime(
                highestFrame?.timestamp ?? highestPoint?.timestamp ?? startedAt,
              ),
              highestSpeedText: formatSpeedKmh(
                widget.detail.session.maxSpeedMps,
              ),
              highestSpeedHint:
                  formatTime(fastestPoint?.timestamp ?? startedAt),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7F8),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.24),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReplayPreviewModuleHeader(
                    title: _viewMode == FlightAnalysisViewMode.threeD
                        ? '입체 미리보기'
                        : '경로 미리보기',
                    description: _viewMode == FlightAnalysisViewMode.threeD
                        ? '사선 시점과 지형감을 바로 살펴보며 전체화면 분석 전에 핵심 흐름을 확인하세요.'
                        : '선택한 핵심 시점과 경로 흐름을 지도에서 빠르게 훑어볼 수 있습니다.',
                    trailing: MapViewToggle(
                      value: widget.mapViewType,
                      onChanged: widget.onMapViewTypeChanged,
                      compact: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_viewMode == FlightAnalysisViewMode.twoD)
                    _buildTwoDView(context)
                  else
                    _buildThreeDView(context, currentFrame),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmbeddedReplayToolbar(BuildContext context) {
    final segmentedButton = SegmentedButton<FlightAnalysisViewMode>(
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
      segments: const [
        ButtonSegment<FlightAnalysisViewMode>(
          value: FlightAnalysisViewMode.twoD,
          label: Text('2D 보기'),
          icon: Icon(Icons.map_outlined, size: 18),
        ),
        ButtonSegment<FlightAnalysisViewMode>(
          value: FlightAnalysisViewMode.threeD,
          label: Text('3D 보기'),
          icon: Icon(Icons.view_in_ar_rounded, size: 18),
        ),
      ],
      selected: {_viewMode},
      onSelectionChanged: (selection) {
        if (selection.isEmpty) {
          return;
        }
        _setViewMode(selection.first);
      },
    );

    final fullscreenButton = FilledButton.tonalIcon(
      onPressed: _replayData.hasFrames ? _openFullscreen : null,
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      icon: const Icon(Icons.fullscreen_rounded, size: 18),
      label: const Text('전체화면'),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          segmentedButton,
          fullscreenButton,
        ],
      ),
    );
  }

  Widget _buildEmbeddedReplaySummaryRow(
    BuildContext context, {
    required String startTimeText,
    required String highestAltitudeText,
    required String highestAltitudeHint,
    required String highestSpeedText,
    required String highestSpeedHint,
  }) {
    final cards = [
      _EmbeddedReplaySummaryCard(
        label: '비행 시작',
        value: startTimeText,
        hint: '기록 기준 시각',
      ),
      _EmbeddedReplaySummaryCard(
        label: '최고 고도',
        value: highestAltitudeText,
        hint: highestAltitudeHint,
        emphasized: true,
      ),
      _EmbeddedReplaySummaryCard(
        label: '최고 속도',
        value: highestSpeedText,
        hint: highestSpeedHint,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 360) {
          return Row(
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                Expanded(child: cards[index]),
                if (index != cards.length - 1) const SizedBox(width: 8),
              ],
            ],
          );
        }

        final itemWidth = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(width: itemWidth, child: cards[0]),
            SizedBox(width: itemWidth, child: cards[1]),
            SizedBox(width: constraints.maxWidth, child: cards[2]),
          ],
        );
      },
    );
  }

  Widget _buildTwoDView(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.summary.keyMoments.isNotEmpty) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final moment in widget.summary.keyMoments) ...[
                  _MomentChip(
                    moment: moment,
                    isSelected: widget.selectedMoment?.type == moment.type,
                    onTap: () => widget.onFocusMoment(moment),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        Stack(
          children: [
            FlightMapView(
              points: _orderedPoints,
              height: 340,
              mapController: widget.mapController,
              mapViewType: widget.mapViewType,
              showLegend: false,
              showCurrentMarker: false,
              emptyMessage: '경로 데이터가 아직 충분하지 않습니다.',
              siteLatitude: widget.siteMetadata?.latitude,
              siteLongitude: widget.siteMetadata?.longitude,
              siteLabel: widget.siteMetadata?.name,
              highlightLatitude: widget.selectedMoment?.point.latitude,
              highlightLongitude: widget.selectedMoment?.point.longitude,
              highlightLabel: widget.selectedMoment?.title,
            ),
            if (widget.selectedMoment != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: _SelectedMomentOverlay(
                  title: widget.selectedMoment!.title,
                  subtitle: widget.selectedMoment!.subtitle,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _ReplayPreviewFooter(
          selectedMomentTitle: widget.selectedMoment?.title,
          keyMomentCount: widget.summary.keyMoments.length,
        ),
      ],
    );
  }

  Widget _buildFullscreenReplay(
    BuildContext context,
    FlightReplayFrame? currentFrame,
  ) {
    if (!_replayData.hasFrames || currentFrame == null) {
      return ColoredBox(
        color: const Color(0xFF09131B),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildReplayEmptyFallback(),
          ),
        ),
      );
    }

    final highestFrame = _replayData.highestFrame ?? currentFrame;
    final effectiveCameraMode = _effectiveCameraMode(currentFrame);
    final autoCameraStageLabel = _autoCameraStageLabel(currentFrame);

    return ColoredBox(
      color: const Color(0xFF09131B),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          child: Stack(
            children: [
              Positioned.fill(
                child: _buildFullscreenMapContent(
                  context,
                  currentFrame: currentFrame,
                  effectiveCameraMode: effectiveCameraMode,
                ),
              ),
              Positioned.fill(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FullscreenReplayTopChrome(
                      viewMode: _viewMode,
                      hasThreeDEntryReady: _hasThreeDEntryReady,
                      currentTimeText: formatTime(currentFrame.timestamp),
                      totalDurationText:
                          formatDuration(_replayData.totalDuration),
                      currentAltitudeText:
                          formatAltitudeMeters(currentFrame.altitudeMeters),
                      highestAltitudeText:
                          formatAltitudeMeters(highestFrame.altitudeMeters),
                      onClose: widget.onCloseFullscreen ??
                          () => Navigator.maybePop(context),
                      onExport: _showExportOptions,
                      onModeChanged: (mode) => _setViewMode(mode),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                child: _secondaryPanelExpanded
                                    ? ConstrainedBox(
                                        key: const ValueKey('replay-secondary'),
                                        constraints: BoxConstraints(
                                          maxHeight: constraints.maxHeight,
                                        ),
                                        child: SingleChildScrollView(
                                          padding:
                                              const EdgeInsets.only(bottom: 10),
                                          child:
                                              _FullscreenReplaySecondaryPanel(
                                            autoCameraEnabled:
                                                _autoCameraEnabled,
                                            autoCameraStageLabel:
                                                autoCameraStageLabel,
                                            cameraMode: effectiveCameraMode,
                                            onAutoCameraChanged: (selected) {
                                              setState(() {
                                                _autoCameraEnabled = selected;
                                              });
                                            },
                                            onCameraModeChanged: (mode) {
                                              setState(() {
                                                _autoCameraEnabled = false;
                                                _cameraMode = mode;
                                              });
                                            },
                                            selectedSegmentLabel:
                                                _selectedSegment?.label,
                                            takeoffSegment: _takeoffSegment,
                                            landingSegment: _landingSegment,
                                            thermalSegments:
                                                _replayData.thermalSegments,
                                            onSelectFull: () =>
                                                _selectSegment(null),
                                            onSelectSegment: _selectSegment,
                                            insightPanel: _ReplayInsightPanel(
                                              segmentLabel: _segmentStateLabel(
                                                currentFrame.verticalSpeedMps,
                                              ),
                                              altitudeDeltaText:
                                                  _signedAltitudeText(
                                                currentFrame
                                                    .altitudeFromStartMeters,
                                              ),
                                              peakGapText: (highestFrame
                                                                  .displayAltitudeMeters -
                                                              currentFrame
                                                                  .displayAltitudeMeters)
                                                          .abs() <=
                                                      6
                                                  ? '최고 고도 지점'
                                                  : '${formatAltitudeMeters((highestFrame.displayAltitudeMeters - currentFrame.displayAltitudeMeters).abs())} 차이',
                                              elapsedText: formatDuration(
                                                currentFrame.elapsedDuration,
                                              ),
                                              thermalLabel:
                                                  _currentThermalSegment
                                                          ?.label ??
                                                      '써멀 추정 없음',
                                              speedText: formatSpeedKmh(
                                                currentFrame.speedMps,
                                              ),
                                              distanceText:
                                                  formatDistanceMeters(
                                                currentFrame
                                                    .cumulativeDistanceMeters,
                                              ),
                                              verticalSpeedText:
                                                  formatVerticalSpeed(
                                                currentFrame.verticalSpeedMps,
                                              ),
                                            ),
                                            altitudeProfile:
                                                _ReplayAltitudeProfile(
                                              replayData: _replayData,
                                              currentIndex: _safeReplayIndex,
                                              rangeStartIndex:
                                                  _selectedRangeStart,
                                              rangeEndIndex: _selectedRangeEnd,
                                            ),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(
                                        key: ValueKey(
                                          'replay-secondary-empty',
                                        ),
                                      ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    _FullscreenReplayControlCard(
                      isPlaying: _isPlaying,
                      progress: _selectedSegmentProgress,
                      playbackSpeed: _playbackSpeed,
                      selectedRangeLabel: _selectedSegment?.label ?? '전체 경로',
                      elapsedText: formatDuration(currentFrame.elapsedDuration),
                      durationText: formatDuration(_selectedRangeDuration),
                      progressText:
                          '${(_selectedSegmentProgress * 100).round()}%',
                      secondaryExpanded: _secondaryPanelExpanded,
                      onPlayPause: _togglePlayback,
                      onReset: () {
                        _seekToIndex(_selectedRangeStart);
                        setState(() {
                          _autoCameraEnabled = true;
                          _cameraMode = FlightReplayCameraMode.overview;
                        });
                      },
                      onProgressChanged: (value) {
                        _seekToProgress(value);
                      },
                      onSpeedChanged: (value) {
                        final wasPlaying = _isPlaying;
                        _playbackTimer?.cancel();
                        _lastPlaybackTickAt = null;
                        setState(() {
                          _playbackSpeed = value;
                        });
                        if (wasPlaying) {
                          _togglePlayback();
                        }
                      },
                      onToggleSecondary: _toggleSecondaryPanel,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullscreenMapContent(
    BuildContext context, {
    required FlightReplayFrame currentFrame,
    required FlightReplayCameraMode effectiveCameraMode,
  }) {
    if (_viewMode == FlightAnalysisViewMode.twoD) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return RepaintBoundary(
            key: _twoDReplayBoundaryKey,
            child: FlightMapView(
              points: _orderedPoints,
              height: constraints.maxHeight,
              borderRadius: 0,
              mapController: widget.mapController,
              mapViewType: widget.mapViewType,
              showLegend: false,
              showCurrentMarker: false,
              emptyMessage: '경로 데이터가 아직 충분하지 않습니다.',
              siteLatitude: widget.siteMetadata?.latitude,
              siteLongitude: widget.siteMetadata?.longitude,
              siteLabel: widget.siteMetadata?.name,
              revealUntilIndex: _safeReplayIndex,
              revealLatitude: currentFrame.latitude,
              revealLongitude: currentFrame.longitude,
              highlightLatitude: currentFrame.latitude,
              highlightLongitude: currentFrame.longitude,
              highlightLabel:
                  '현재 재생 위치 · ${formatTime(currentFrame.timestamp)}',
            ),
          );
        },
      );
    }

    if (!_supportsThreeDOnCurrentPlatform ||
        !_hasMapboxSetup ||
        !_hasThreeDEntryReady) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: _buildReplayEmptyFallback(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return FlightAnalysis3DView(
          key: _threeDViewKey,
          replayData: _replayData,
          currentIndex: _safeReplayIndex,
          playbackProgress: currentFrame.progress,
          cameraMode: effectiveCameraMode,
          mapViewType: widget.mapViewType,
          autoDirectorEnabled: _autoCameraEnabled,
          siteLatitude: widget.siteMetadata?.latitude,
          siteLongitude: widget.siteMetadata?.longitude,
          siteLabel: widget.siteMetadata?.name,
          rangeStartIndex: _selectedRangeStart,
          rangeEndIndex: _selectedRangeEnd,
          isPlaying: _isPlaying,
          height: constraints.maxHeight,
        );
      },
    );
  }

  Widget _buildReplayEmptyFallback() {
    if (!_supportsThreeDOnCurrentPlatform &&
        _viewMode == FlightAnalysisViewMode.threeD) {
      return const _ReplayEmptyState(
        icon: Icons.devices_rounded,
        title: '웹에서는 3D 분석을 지원하지 않습니다.',
        description: '모바일 앱에서 Mapbox 기반 3D 지형 리플레이를 확인해 주세요.',
      );
    }

    if (!_hasMapboxSetup && _viewMode == FlightAnalysisViewMode.threeD) {
      return const _ReplayEmptyState(
        icon: Icons.key_rounded,
        title: 'Mapbox 3D 분석 설정이 필요합니다.',
        description:
            '실행 시 MAPBOX_ACCESS_TOKEN을 설정하면 지형 기반 3D 리플레이를 사용할 수 있습니다.',
      );
    }

    return const _ReplayEmptyState(
      icon: Icons.alt_route_rounded,
      title: '리플레이 데이터를 준비하는 중입니다.',
      description: '위치 샘플과 고도 기록이 충분해야 전체화면 리플레이를 표시할 수 있습니다.',
    );
  }

  Widget _buildThreeDView(
    BuildContext context,
    FlightReplayFrame? currentFrame,
  ) {
    if (!_supportsThreeDOnCurrentPlatform) {
      return const _ReplayEmptyState(
        icon: Icons.devices_rounded,
        title: '웹에서는 3D 분석을 지원하지 않습니다.',
        description: '모바일 앱에서 Mapbox 기반 3D 지형 리플레이를 확인해 주세요.',
      );
    }

    if (!_hasMapboxSetup) {
      return const _ReplayEmptyState(
        icon: Icons.key_rounded,
        title: 'Mapbox 3D 분석 설정이 필요합니다.',
        description:
            '실행 시 MAPBOX_ACCESS_TOKEN을 설정하면 지형 기반 3D 리플레이를 사용할 수 있습니다.',
      );
    }

    if (!_canUse3D || currentFrame == null) {
      return const _ReplayEmptyState(
        icon: Icons.alt_route_rounded,
        title: '3D 분석을 준비할 경로 데이터가 아직 부족합니다.',
        description: '위치 샘플과 고도 기록이 충분해야 입체 지형 리플레이를 표시할 수 있습니다.',
      );
    }

    final highestFrame = _replayData.highestFrame ?? currentFrame;
    final currentProgress = currentFrame.progress.clamp(0.0, 1.0);
    final currentThermal = _currentThermalSegment;
    final segmentProgress =
        _selectedSegment == null ? currentProgress : _selectedSegmentProgress;
    final altitudeGapToPeak =
        highestFrame.displayAltitudeMeters - currentFrame.displayAltitudeMeters;
    final effectiveCameraMode = _effectiveCameraMode(currentFrame);
    final autoCameraStageLabel = _autoCameraStageLabel(currentFrame);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            FlightAnalysis3DView(
              key: _threeDViewKey,
              replayData: _replayData,
              currentIndex: _safeReplayIndex,
              playbackProgress: currentFrame.progress,
              cameraMode: effectiveCameraMode,
              mapViewType: widget.mapViewType,
              autoDirectorEnabled: _autoCameraEnabled,
              siteLatitude: widget.siteMetadata?.latitude,
              siteLongitude: widget.siteMetadata?.longitude,
              siteLabel: widget.siteMetadata?.name,
              rangeStartIndex: _selectedRangeStart,
              rangeEndIndex: _selectedRangeEnd,
              isPlaying: _isPlaying,
              height: 406,
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _ReplayTopOverlay(
                currentTimeText: formatTime(currentFrame.timestamp),
                currentAltitudeText:
                    formatAltitudeMeters(currentFrame.altitudeMeters),
                highestAltitudeText:
                    formatAltitudeMeters(highestFrame.altitudeMeters),
                totalDurationText: formatDuration(_replayData.totalDuration),
                progressText: '${(currentProgress * 100).round()}%',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              selected: _autoCameraEnabled,
              label: const Text('자동 연출'),
              onSelected: (selected) {
                setState(() {
                  _autoCameraEnabled = selected;
                });
              },
            ),
            if (_autoCameraEnabled)
              Chip(
                avatar: const Icon(Icons.movie_filter_rounded, size: 16),
                label: Text(autoCameraStageLabel),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<FlightReplayCameraMode>(
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
            segments: [
              for (final mode in FlightReplayCameraMode.values)
                ButtonSegment<FlightReplayCameraMode>(
                  value: mode,
                  label: Text(mode.label),
                ),
            ],
            selected: {effectiveCameraMode},
            onSelectionChanged: (selection) {
              if (selection.isEmpty) {
                return;
              }
              setState(() {
                _autoCameraEnabled = false;
                _cameraMode = selection.first;
              });
            },
          ),
        ),
        const SizedBox(height: 12),
        _ReplayControlBar(
          isPlaying: _isPlaying,
          progress: segmentProgress,
          playbackSpeed: _playbackSpeed,
          currentTimeText: formatTime(currentFrame.timestamp),
          selectedRangeLabel: _selectedSegment?.label ?? '전체 경로',
          elapsedText: formatDuration(currentFrame.elapsedDuration),
          durationText: formatDuration(_selectedRangeDuration),
          onPlayPause: _togglePlayback,
          onReset: () {
            _seekToIndex(_selectedRangeStart);
            setState(() {
              _autoCameraEnabled = true;
              _cameraMode = FlightReplayCameraMode.overview;
            });
          },
          onProgressChanged: (value) {
            _seekToProgress(value);
          },
          onSpeedChanged: (value) {
            final wasPlaying = _isPlaying;
            _playbackTimer?.cancel();
            setState(() {
              _playbackSpeed = value;
            });
            if (wasPlaying) {
              _togglePlayback();
            }
          },
        ),
        const SizedBox(height: 12),
        _ReplayInsightPanel(
          segmentLabel: _segmentStateLabel(currentFrame.verticalSpeedMps),
          altitudeDeltaText:
              _signedAltitudeText(currentFrame.altitudeFromStartMeters),
          peakGapText: altitudeGapToPeak.abs() <= 6
              ? '최고 고도 지점'
              : '${formatAltitudeMeters(altitudeGapToPeak.abs())} 차이',
          elapsedText: formatDuration(currentFrame.elapsedDuration),
          thermalLabel: currentThermal?.label ?? '써멀 추정 없음',
          speedText: formatSpeedKmh(currentFrame.speedMps),
          distanceText:
              formatDistanceMeters(currentFrame.cumulativeDistanceMeters),
          verticalSpeedText: formatVerticalSpeed(currentFrame.verticalSpeedMps),
        ),
        const SizedBox(height: 12),
        _ReplayAltitudeProfile(
          replayData: _replayData,
          currentIndex: _safeReplayIndex,
          rangeStartIndex: _selectedRangeStart,
          rangeEndIndex: _selectedRangeEnd,
        ),
        const SizedBox(height: 12),
        _ReplaySegmentSelector(
          selectedLabel: _selectedSegment?.label,
          takeoffSegment: _takeoffSegment,
          landingSegment: _landingSegment,
          thermalSegments: _replayData.thermalSegments,
          onSelectFull: () => _selectSegment(null),
          onSelectSegment: _selectSegment,
        ),
        const SizedBox(height: 10),
        Text(
          '3D 분석은 실제 기록된 위치, 시간, 고도 데이터를 바탕으로 재생됩니다. 출동 판단과 공역 확인은 현장 정보와 함께 추가로 확인해 주세요.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
        ),
      ],
    );
  }
}

class FlightReplayFullscreenScreen extends StatefulWidget {
  const FlightReplayFullscreenScreen({
    super.key,
    required this.detail,
    required this.summary,
    required this.siteMetadata,
    required this.initialMapViewType,
    this.selectedMoment,
    this.startInThreeD = false,
    this.initialReplayTimestamp,
    this.initialCameraMode = FlightReplayCameraMode.overview,
    this.initialAutoCameraEnabled = true,
  });

  final FlightSessionDetail detail;
  final FlightAnalysisSummary summary;
  final KoreaFlightSiteMetadata? siteMetadata;
  final FlightAnalysisMoment? selectedMoment;
  final ParaglidingMapViewType initialMapViewType;
  final bool startInThreeD;
  final DateTime? initialReplayTimestamp;
  final FlightReplayCameraMode initialCameraMode;
  final bool initialAutoCameraEnabled;

  @override
  State<FlightReplayFullscreenScreen> createState() =>
      _FlightReplayFullscreenScreenState();
}

class _FlightReplayFullscreenScreenState
    extends State<FlightReplayFullscreenScreen> {
  final MapController _mapController = MapController();
  late ParaglidingMapViewType _mapViewType = widget.initialMapViewType;
  FlightAnalysisMomentType? _selectedMomentType;

  @override
  void initState() {
    super.initState();
    _selectedMomentType = widget.selectedMoment?.type;
  }

  FlightAnalysisMoment? _resolvedSelectedMoment() {
    if (widget.summary.keyMoments.isEmpty) {
      return null;
    }

    final selectedType = _selectedMomentType;
    if (selectedType != null) {
      for (final moment in widget.summary.keyMoments) {
        if (moment.type == selectedType) {
          return moment;
        }
      }
    }
    return widget.selectedMoment ?? widget.summary.keyMoments.first;
  }

  void _focusMoment(FlightAnalysisMoment moment) {
    setState(() {
      _selectedMomentType = moment.type;
    });
    _mapController.move(
      LatLng(moment.point.latitude, moment.point.longitude),
      14.8,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09131B),
      body: FlightAnalysisReplaySection(
        detail: widget.detail,
        summary: widget.summary,
        siteMetadata: widget.siteMetadata,
        selectedMoment: _resolvedSelectedMoment(),
        onFocusMoment: _focusMoment,
        mapController: _mapController,
        mapViewType: _mapViewType,
        onMapViewTypeChanged: (type) {
          setState(() {
            _mapViewType = type;
          });
        },
        fullscreen: true,
        startInThreeD: widget.startInThreeD,
        initialReplayTimestamp: widget.initialReplayTimestamp,
        initialCameraMode: widget.initialCameraMode,
        initialAutoCameraEnabled: widget.initialAutoCameraEnabled,
        onCloseFullscreen: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}

class _ReplayEmptyState extends StatelessWidget {
  const _ReplayEmptyState({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}

class _FullscreenReplayTopChrome extends StatelessWidget {
  const _FullscreenReplayTopChrome({
    required this.viewMode,
    required this.hasThreeDEntryReady,
    required this.currentTimeText,
    required this.totalDurationText,
    required this.currentAltitudeText,
    required this.highestAltitudeText,
    required this.onClose,
    required this.onExport,
    required this.onModeChanged,
  });

  final FlightAnalysisViewMode viewMode;
  final bool hasThreeDEntryReady;
  final String currentTimeText;
  final String totalDurationText;
  final String currentAltitudeText;
  final String highestAltitudeText;
  final VoidCallback onClose;
  final VoidCallback onExport;
  final ValueChanged<FlightAnalysisViewMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _FullscreenOverlayIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: '전체화면 종료',
              onPressed: onClose,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ReplayGlassPanel(
                borderRadius: 16,
                padding: const EdgeInsets.all(3),
                child: SegmentedButton<FlightAnalysisViewMode>(
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? Colors.white.withValues(alpha: 0.16)
                          : Colors.transparent,
                    ),
                    foregroundColor:
                        WidgetStateProperty.all<Color>(Colors.white),
                    overlayColor: WidgetStateProperty.all(
                      Colors.white.withValues(alpha: 0.08),
                    ),
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: WidgetStateProperty.all(BorderSide.none),
                  ),
                  segments: [
                    const ButtonSegment<FlightAnalysisViewMode>(
                      value: FlightAnalysisViewMode.twoD,
                      label: Text('2D 보기'),
                      icon: Icon(Icons.map_outlined, size: 16),
                    ),
                    ButtonSegment<FlightAnalysisViewMode>(
                      value: FlightAnalysisViewMode.threeD,
                      enabled: hasThreeDEntryReady,
                      label: const Text('3D 보기'),
                      icon: const Icon(Icons.view_in_ar_rounded, size: 16),
                    ),
                  ],
                  selected: {viewMode},
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) {
                      return;
                    }
                    onModeChanged(selection.first);
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            _FullscreenOverlayIconButton(
              icon: Icons.ios_share_rounded,
              tooltip: '리플레이 내보내기',
              onPressed: onExport,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ReplayGlassPanel(
          borderRadius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _FullscreenReplayStat(label: '현재 재생 시각', value: currentTimeText),
              _FullscreenReplayStat(label: '총 비행 시간', value: totalDurationText),
              _FullscreenReplayStat(label: '현재 고도', value: currentAltitudeText),
              _FullscreenReplayStat(label: '최고 고도', value: highestAltitudeText),
            ],
          ),
        ),
      ],
    );
  }
}

class _FullscreenReplayStat extends StatelessWidget {
  const _FullscreenReplayStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.74),
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
          ),
        ],
      ),
    );
  }
}

class _FullscreenOverlayIconButton extends StatelessWidget {
  const _FullscreenOverlayIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: _ReplayGlassPanel(
        borderRadius: 16,
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, color: Colors.white, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}

class _FullscreenReplayControlCard extends StatelessWidget {
  const _FullscreenReplayControlCard({
    required this.isPlaying,
    required this.progress,
    required this.playbackSpeed,
    required this.selectedRangeLabel,
    required this.elapsedText,
    required this.durationText,
    required this.progressText,
    required this.secondaryExpanded,
    required this.onPlayPause,
    required this.onReset,
    required this.onProgressChanged,
    required this.onSpeedChanged,
    required this.onToggleSecondary,
  });

  final bool isPlaying;
  final double progress;
  final double playbackSpeed;
  final String selectedRangeLabel;
  final String elapsedText;
  final String durationText;
  final String progressText;
  final bool secondaryExpanded;
  final VoidCallback onPlayPause;
  final VoidCallback onReset;
  final ValueChanged<double> onProgressChanged;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onToggleSecondary;

  @override
  Widget build(BuildContext context) {
    return _ReplayGlassPanel(
      borderRadius: 22,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 420;
              final speedButton = PopupMenuButton<double>(
                initialValue: playbackSpeed,
                tooltip: '재생 속도',
                onSelected: onSpeedChanged,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 0.75, child: Text('0.75배속')),
                  PopupMenuItem(value: 1.0, child: Text('1배속')),
                  PopupMenuItem(value: 1.5, child: Text('1.5배속')),
                  PopupMenuItem(value: 2.0, child: Text('2배속')),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    playbackSpeed.truncateToDouble() == playbackSpeed
                        ? '${playbackSpeed.toStringAsFixed(0)}배속'
                        : '${playbackSpeed.toStringAsFixed(1)}배속',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              );

              final info = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedRangeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$elapsedText / $durationText',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    info,
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        speedButton,
                        const Spacer(),
                        Text(
                          progressText,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.88),
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 8),
                  speedButton,
                  const SizedBox(width: 8),
                  Text(
                    progressText,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              final slider = SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                  thumbColor: Colors.white,
                  overlayColor: Colors.white.withValues(alpha: 0.16),
                ),
                child: Slider(
                  value: progress.clamp(0.0, 1.0),
                  onChanged: onProgressChanged,
                ),
              );

              final actions = Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: [
                  _FullscreenReplayActionChip(
                    icon: Icons.center_focus_strong_rounded,
                    label: '초기 시점',
                    onTap: onReset,
                  ),
                  _FullscreenReplayActionChip(
                    icon: secondaryExpanded
                        ? Icons.expand_more_rounded
                        : Icons.tune_rounded,
                    label: secondaryExpanded ? '보조 정보 접기' : '보조 정보 보기',
                    onTap: onToggleSecondary,
                  ),
                ],
              );

              if (compact) {
                return Column(
                  children: [
                    Row(
                      children: [
                        IconButton.filled(
                          onPressed: onPlayPause,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF10202B),
                          ),
                          icon: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: slider),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: actions,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  IconButton.filled(
                    onPressed: onPlayPause,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF10202B),
                    ),
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: slider),
                  const SizedBox(width: 4),
                  actions,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FullscreenReplayActionChip extends StatelessWidget {
  const _FullscreenReplayActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullscreenReplaySecondaryPanel extends StatelessWidget {
  const _FullscreenReplaySecondaryPanel({
    required this.autoCameraEnabled,
    required this.autoCameraStageLabel,
    required this.cameraMode,
    required this.onAutoCameraChanged,
    required this.onCameraModeChanged,
    required this.selectedSegmentLabel,
    required this.takeoffSegment,
    required this.landingSegment,
    required this.thermalSegments,
    required this.onSelectFull,
    required this.onSelectSegment,
    required this.insightPanel,
    required this.altitudeProfile,
  });

  final bool autoCameraEnabled;
  final String autoCameraStageLabel;
  final FlightReplayCameraMode cameraMode;
  final ValueChanged<bool> onAutoCameraChanged;
  final ValueChanged<FlightReplayCameraMode> onCameraModeChanged;
  final String? selectedSegmentLabel;
  final FlightReplaySegment? takeoffSegment;
  final FlightReplaySegment? landingSegment;
  final List<FlightReplaySegment> thermalSegments;
  final VoidCallback onSelectFull;
  final ValueChanged<FlightReplaySegment?> onSelectSegment;
  final Widget insightPanel;
  final Widget altitudeProfile;

  @override
  Widget build(BuildContext context) {
    return _ReplayGlassPanel(
      borderRadius: 22,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                selected: autoCameraEnabled,
                label: const Text('자동 연출'),
                onSelected: onAutoCameraChanged,
              ),
              if (autoCameraEnabled)
                Chip(
                  avatar: const Icon(Icons.movie_filter_rounded, size: 16),
                  label: Text(autoCameraStageLabel),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Wrap(
              spacing: 8,
              children: [
                for (final mode in FlightReplayCameraMode.values)
                  ChoiceChip(
                    selected: !autoCameraEnabled && cameraMode == mode,
                    label: Text(mode.label),
                    onSelected: (_) => onCameraModeChanged(mode),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ReplaySegmentSelector(
            selectedLabel: selectedSegmentLabel,
            takeoffSegment: takeoffSegment,
            landingSegment: landingSegment,
            thermalSegments: thermalSegments,
            onSelectFull: onSelectFull,
            onSelectSegment: onSelectSegment,
          ),
          const SizedBox(height: 12),
          insightPanel,
          const SizedBox(height: 12),
          altitudeProfile,
        ],
      ),
    );
  }
}

class _ReplayTopOverlay extends StatelessWidget {
  const _ReplayTopOverlay({
    required this.currentTimeText,
    required this.currentAltitudeText,
    required this.highestAltitudeText,
    required this.totalDurationText,
    required this.progressText,
  });

  final String currentTimeText;
  final String currentAltitudeText;
  final String highestAltitudeText;
  final String totalDurationText;
  final String progressText;

  @override
  Widget build(BuildContext context) {
    return _ReplayGlassPanel(
      borderRadius: 18,
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          _ReplayCoreStat(label: '현재 재생 시각', value: currentTimeText),
          _ReplayCoreStat(label: '현재 고도', value: currentAltitudeText),
          _ReplayCoreStat(label: '최고 고도', value: highestAltitudeText),
          _ReplayCoreStat(label: '총 비행 시간', value: totalDurationText),
          _ReplayCoreStat(label: '재생 진행률', value: progressText),
        ],
      ),
    );
  }
}

class _ReplayCoreStat extends StatelessWidget {
  const _ReplayCoreStat({
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
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.76),
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _ReplayControlBar extends StatelessWidget {
  const _ReplayControlBar({
    required this.isPlaying,
    required this.progress,
    required this.playbackSpeed,
    required this.currentTimeText,
    required this.selectedRangeLabel,
    required this.elapsedText,
    required this.durationText,
    required this.onPlayPause,
    required this.onProgressChanged,
    required this.onSpeedChanged,
    required this.onReset,
  });

  final bool isPlaying;
  final double progress;
  final double playbackSpeed;
  final String currentTimeText;
  final String selectedRangeLabel;
  final String elapsedText;
  final String durationText;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onProgressChanged;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE6EB)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: onPlayPause,
                tooltip: isPlaying ? '일시정지' : '재생',
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              IconButton(
                onPressed: onReset,
                tooltip: '처음 시점으로 이동',
                icon: const Icon(Icons.replay_rounded),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currentTimeText,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$elapsedText / $durationText · $selectedRangeLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<double>(
                initialValue: playbackSpeed,
                tooltip: '재생 속도',
                onSelected: onSpeedChanged,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 0.75, child: Text('0.75배속')),
                  PopupMenuItem(value: 1.0, child: Text('1배속')),
                  PopupMenuItem(value: 1.5, child: Text('1.5배속')),
                  PopupMenuItem(value: 2.0, child: Text('2배속')),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.black.withValues(alpha: 0.08)),
                  ),
                  child: Text(
                    playbackSpeed.truncateToDouble() == playbackSpeed
                        ? '${playbackSpeed.toStringAsFixed(0)}배속'
                        : '${playbackSpeed.toStringAsFixed(1)}배속',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: progress.clamp(0.0, 1.0),
                  onChanged: onProgressChanged,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(progress * 100).round()}%',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReplayGlassPanel extends StatelessWidget {
  const _ReplayGlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.borderRadius = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: const Color(0xFF102630).withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ReplayInsightPanel extends StatelessWidget {
  const _ReplayInsightPanel({
    required this.segmentLabel,
    required this.altitudeDeltaText,
    required this.peakGapText,
    required this.elapsedText,
    required this.thermalLabel,
    required this.speedText,
    required this.distanceText,
    required this.verticalSpeedText,
  });

  final String segmentLabel;
  final String altitudeDeltaText;
  final String peakGapText;
  final String elapsedText;
  final String thermalLabel;
  final String speedText;
  final String distanceText;
  final String verticalSpeedText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE6EB)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _ReplayMetaPill(label: '현재 구간', value: segmentLabel),
          _ReplayMetaPill(label: '이륙 대비', value: altitudeDeltaText),
          _ReplayMetaPill(label: '최고점 대비', value: peakGapText),
          _ReplayMetaPill(label: '재생 시점', value: elapsedText),
          _ReplayMetaPill(label: '써멀 추정', value: thermalLabel),
          _ReplayMetaPill(label: '현재 속도', value: speedText),
          _ReplayMetaPill(label: '누적 거리', value: distanceText),
          _ReplayMetaPill(label: '상승·하강률', value: verticalSpeedText),
        ],
      ),
    );
  }
}

class _ReplayMetaPill extends StatelessWidget {
  const _ReplayMetaPill({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE6EB)),
      ),
      child: Text(
        '$label  $value',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _ReplayAltitudeProfile extends StatelessWidget {
  const _ReplayAltitudeProfile({
    required this.replayData,
    required this.currentIndex,
    required this.rangeStartIndex,
    required this.rangeEndIndex,
  });

  final FlightReplayData replayData;
  final int currentIndex;
  final int rangeStartIndex;
  final int rangeEndIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE6EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '고도 흐름',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Text(
                '${formatAltitudeMeters(replayData.minAltitudeMeters)} ~ ${formatAltitudeMeters(replayData.maxAltitudeMeters)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 76,
            width: double.infinity,
            child: CustomPaint(
              painter: _ReplayAltitudeProfilePainter(
                replayData: replayData,
                currentIndex: currentIndex,
                rangeStartIndex: rangeStartIndex,
                rangeEndIndex: rangeEndIndex,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplayAltitudeProfilePainter extends CustomPainter {
  const _ReplayAltitudeProfilePainter({
    required this.replayData,
    required this.currentIndex,
    required this.rangeStartIndex,
    required this.rangeEndIndex,
  });

  final FlightReplayData replayData;
  final int currentIndex;
  final int rangeStartIndex;
  final int rangeEndIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (replayData.frames.length < 2) {
      return;
    }

    final safeCurrentIndex = min(
      max(0, currentIndex),
      replayData.frames.length - 1,
    );
    final altitudeRange = max(
      1.0,
      replayData.maxAltitudeMeters - replayData.minAltitudeMeters,
    );
    final leftPadding = 2.0;
    final usableWidth = max(1.0, size.width - (leftPadding * 2));
    final usableHeight = max(1.0, size.height - 12);

    Offset pointAt(int index) {
      final frame = replayData.frames[index];
      final x =
          leftPadding + (index / (replayData.frames.length - 1)) * usableWidth;
      final normalized =
          (frame.displayAltitudeMeters - replayData.minAltitudeMeters) /
              altitudeRange;
      final y = usableHeight - (normalized * usableHeight) + 4;
      return Offset(x, y);
    }

    final points = List<Offset>.generate(
      replayData.frames.length,
      pointAt,
      growable: false,
    );

    final fullPath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      fullPath.lineTo(points[index].dx, points[index].dy);
    }

    canvas.drawPath(
      fullPath,
      Paint()
        ..color = const Color(0x663E6C84)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final rangeStart = min(rangeStartIndex, points.length - 1);
    final rangeEnd = min(rangeEndIndex, points.length - 1);
    final selectionRect = Rect.fromLTWH(
      points[rangeStart].dx,
      0,
      max(6, points[rangeEnd].dx - points[rangeStart].dx),
      size.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(selectionRect, const Radius.circular(12)),
      Paint()..color = const Color(0x142A9D8F),
    );

    final progressedPath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index <= safeCurrentIndex; index++) {
      progressedPath.lineTo(points[index].dx, points[index].dy);
    }
    canvas.drawPath(
      progressedPath,
      Paint()
        ..color = const Color(0xFF2EC4B6)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final currentPoint = points[safeCurrentIndex];
    final highestPoint = points[replayData.highestFrameIndex];

    canvas.drawCircle(
      highestPoint,
      4.5,
      Paint()..color = const Color(0xFFF4A261),
    );
    canvas.drawCircle(
      currentPoint,
      5.5,
      Paint()..color = const Color(0xFF4361EE),
    );
    canvas.drawCircle(
      currentPoint,
      9,
      Paint()..color = const Color(0x334361EE),
    );
  }

  @override
  bool shouldRepaint(covariant _ReplayAltitudeProfilePainter oldDelegate) {
    return oldDelegate.currentIndex != currentIndex ||
        oldDelegate.rangeStartIndex != rangeStartIndex ||
        oldDelegate.rangeEndIndex != rangeEndIndex ||
        oldDelegate.replayData.frames != replayData.frames;
  }
}

class _ReplaySegmentSelector extends StatelessWidget {
  const _ReplaySegmentSelector({
    required this.selectedLabel,
    required this.takeoffSegment,
    required this.landingSegment,
    required this.thermalSegments,
    required this.onSelectFull,
    required this.onSelectSegment,
  });

  final String? selectedLabel;
  final FlightReplaySegment? takeoffSegment;
  final FlightReplaySegment? landingSegment;
  final List<FlightReplaySegment> thermalSegments;
  final VoidCallback onSelectFull;
  final ValueChanged<FlightReplaySegment?> onSelectSegment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SegmentChip(
          label: '전체 경로',
          selected: selectedLabel == null,
          onTap: onSelectFull,
        ),
        if (takeoffSegment != null)
          _SegmentChip(
            label: takeoffSegment!.label,
            selected: selectedLabel == takeoffSegment!.label,
            onTap: () => onSelectSegment(takeoffSegment),
          ),
        if (landingSegment != null)
          _SegmentChip(
            label: landingSegment!.label,
            selected: selectedLabel == landingSegment!.label,
            onTap: () => onSelectSegment(landingSegment),
          ),
        for (final segment in thermalSegments)
          _SegmentChip(
            label: segment.label,
            selected: selectedLabel == segment.label,
            onTap: () => onSelectSegment(segment),
          ),
      ],
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => onTap(),
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      checkmarkColor: Theme.of(context).colorScheme.primary,
      labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: selected ? Theme.of(context).colorScheme.primary : null,
          ),
      side: BorderSide(
        color: selected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.28)
            : Theme.of(context).dividerColor,
      ),
    );
  }
}

class _EmbeddedReplayHeader extends StatelessWidget {
  const _EmbeddedReplayHeader({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '리플레이 분석',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.08,
              ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.42,
                ),
          ),
        ),
      ],
    );
  }
}

class _EmbeddedReplaySummaryCard extends StatelessWidget {
  const _EmbeddedReplaySummaryCard({
    required this.label,
    required this.value,
    required this.hint,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final String hint;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        emphasized ? const Color(0xFF264653) : const Color(0xFFF4F7F8);
    final foregroundColor = emphasized ? Colors.white : const Color(0xFF14212B);
    final secondaryColor = emphasized
        ? Colors.white.withValues(alpha: 0.78)
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: emphasized
            ? null
            : Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.22),
              ),
        boxShadow: emphasized
            ? [
                BoxShadow(
                  color: const Color(0xFF264653).withValues(alpha: 0.16),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: secondaryColor,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: secondaryColor,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _ReplayPreviewModuleHeader extends StatelessWidget {
  const _ReplayPreviewModuleHeader({
    required this.title,
    required this.description,
    required this.trailing,
  });

  final String title;
  final String description;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;

        final textColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              textColumn,
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: trailing,
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: textColumn),
            const SizedBox(width: 10),
            trailing,
          ],
        );
      },
    );
  }
}

class _ReplayPreviewFooter extends StatelessWidget {
  const _ReplayPreviewFooter({
    required this.selectedMomentTitle,
    required this.keyMomentCount,
  });

  final String? selectedMomentTitle;
  final int keyMomentCount;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const _ReplayLegendPill(
          color: Color(0xFF2A9D8F),
          label: '출발',
        ),
        const _ReplayLegendPill(
          color: Color(0xFFE76F51),
          label: '종료',
        ),
        _ReplayLegendPill(
          color: const Color(0xFF264653),
          label: selectedMomentTitle == null
              ? '핵심 시점 $keyMomentCount곳'
              : '선택 시점 · $selectedMomentTitle',
          filled: false,
        ),
      ],
    );
  }
}

class _ReplayLegendPill extends StatelessWidget {
  const _ReplayLegendPill({
    required this.color,
    required this.label,
    this.filled = true,
  });

  final Color color;
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.10) : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: color.withValues(alpha: filled ? 0.24 : 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 148),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: filled
                        ? color
                        : Theme.of(context).colorScheme.onSurface,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentChip extends StatelessWidget {
  const _MomentChip({
    required this.moment,
    required this.isSelected,
    required this.onTap,
  });

  final FlightAnalysisMoment moment;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF264653) : const Color(0xFFF4F7F8),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              moment.title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: isSelected ? Colors.white : null,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              moment.subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.82)
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedMomentOverlay extends StatelessWidget {
  const _SelectedMomentOverlay({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                ),
          ),
        ],
      ),
    );
  }
}
