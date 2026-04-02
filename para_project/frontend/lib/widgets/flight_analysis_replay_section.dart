import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

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
  });

  final FlightSessionDetail detail;
  final FlightAnalysisSummary summary;
  final KoreaFlightSiteMetadata? siteMetadata;
  final FlightAnalysisMoment? selectedMoment;
  final ValueChanged<FlightAnalysisMoment> onFocusMoment;
  final MapController mapController;
  final ParaglidingMapViewType mapViewType;
  final ValueChanged<ParaglidingMapViewType> onMapViewTypeChanged;

  @override
  State<FlightAnalysisReplaySection> createState() =>
      _FlightAnalysisReplaySectionState();
}

class _FlightAnalysisReplaySectionState
    extends State<FlightAnalysisReplaySection> {
  Timer? _playbackTimer;
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
  int _replayIndex = 0;
  double _playbackSpeed = 1.0;
  FlightReplaySegment? _selectedSegment;
  bool _autoCameraEnabled = true;

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

  double get _selectedSegmentProgress {
    final start = _selectedRangeStart;
    final end = _selectedRangeEnd;
    if (end <= start) {
      return 0;
    }
    return ((_safeReplayIndex - start) / (end - start)).clamp(0.0, 1.0);
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
    _refreshReplayData();
  }

  @override
  void didUpdateWidget(covariant FlightAnalysisReplaySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.session.id != widget.detail.session.id ||
        oldWidget.detail.points.length != widget.detail.points.length) {
      _refreshReplayData();
      return;
    }

    final oldSelectedTimestamp = oldWidget.selectedMoment?.point.timestamp;
    final newSelectedTimestamp = widget.selectedMoment?.point.timestamp;
    if (_viewMode == FlightAnalysisViewMode.threeD &&
        newSelectedTimestamp != null &&
        oldSelectedTimestamp != newSelectedTimestamp &&
        _replayData.hasFrames) {
      setState(() {
        _replayIndex = _replayData.nearestFrameIndex(newSelectedTimestamp);
      });
    }
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  void _refreshReplayData() {
    _playbackTimer?.cancel();
    _replayData = FlightReplayData.fromPoints(widget.detail.points);
    _replayIndex = 0;
    _cameraMode = FlightReplayCameraMode.overview;
    _playbackSpeed = 1.0;
    _selectedSegment = null;
    _autoCameraEnabled = true;
  }

  void _setViewMode(FlightAnalysisViewMode mode) {
    if (_viewMode == mode) {
      return;
    }
    setState(() {
      _viewMode = mode;
      if (mode == FlightAnalysisViewMode.threeD &&
          widget.selectedMoment != null &&
          _replayData.hasFrames) {
        _replayIndex = _replayData.nearestFrameIndex(
          widget.selectedMoment!.point.timestamp,
        );
      }
    });
  }

  void _togglePlayback() {
    if (!_hasThreeDEntryReady) {
      return;
    }

    if (_isPlaying) {
      _playbackTimer?.cancel();
      setState(() {});
      return;
    }

    final rangeStart = _selectedRangeStart;
    final rangeEnd = _selectedRangeEnd;
    if (_safeReplayIndex < rangeStart || _safeReplayIndex > rangeEnd) {
      _replayIndex = rangeStart;
    }

    _playbackTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted || _replayData.frames.isEmpty) {
        return;
      }

      final step = switch (_playbackSpeed) {
        >= 4 => 4,
        >= 2 => 2,
        _ => 1,
      };

      final nextIndex = min(rangeEnd, _replayIndex + step);
      if (nextIndex == _replayIndex) {
        _playbackTimer?.cancel();
      }

      setState(() {
        _replayIndex = nextIndex;
      });
    });
    setState(() {});
  }

  void _seekToIndex(int index, {bool stopPlayback = true}) {
    if (stopPlayback) {
      _playbackTimer?.cancel();
    }
    setState(() {
      _replayIndex = _clampReplayIndex(index);
    });
  }

  void _selectSegment(FlightReplaySegment? segment) {
    _playbackTimer?.cancel();
    setState(() {
      _selectedSegment = segment;
      _replayIndex = segment?.startIndex ?? 0;
    });
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
      return FlightReplayCameraMode.perspective;
    }
    if (onThermal) {
      return FlightReplayCameraMode.perspective;
    }
    if (_safeReplayIndex >= _replayData.landingFrameIndex ||
        rangeProgress >= 0.88) {
      return FlightReplayCameraMode.follow;
    }
    return FlightReplayCameraMode.follow;
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

  @override
  Widget build(BuildContext context) {
    final currentFrame = _replayData.frames.isEmpty
        ? null
        : _replayData.frames[_safeReplayIndex];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _viewMode == FlightAnalysisViewMode.threeD
                            ? '입체 비행 분석'
                            : '지도 기반 비행 리플레이',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _viewMode == FlightAnalysisViewMode.threeD
                            ? '지형과 고도 변화를 함께 보며 실제 비행 흐름을 입체적으로 복기합니다.'
                            : '핵심 시점과 경로를 지도에서 빠르게 훑어보며 비행 흐름을 정리합니다.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SegmentedButton<FlightAnalysisViewMode>(
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
                      icon: Icon(Icons.map_outlined, size: 16),
                    ),
                    ButtonSegment<FlightAnalysisViewMode>(
                      value: FlightAnalysisViewMode.threeD,
                      label: Text('3D 보기'),
                      icon: Icon(Icons.view_in_ar_rounded, size: 16),
                    ),
                  ],
                  selected: {_viewMode},
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) {
                      return;
                    }
                    _setViewMode(selection.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_viewMode == FlightAnalysisViewMode.twoD)
              _buildTwoDView(context)
            else
              _buildThreeDView(context, currentFrame),
          ],
        ),
      ),
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
              points: widget.detail.points,
              height: 340,
              mapController: widget.mapController,
              mapViewType: widget.mapViewType,
              showLegend: true,
              showCurrentMarker: false,
              emptyMessage: '경로 데이터가 아직 충분하지 않습니다.',
              siteLatitude: widget.siteMetadata?.latitude,
              siteLongitude: widget.siteMetadata?.longitude,
              siteLabel: widget.siteMetadata?.name,
              highlightLatitude: widget.selectedMoment?.point.latitude,
              highlightLongitude: widget.selectedMoment?.point.longitude,
              highlightLabel: widget.selectedMoment?.title,
            ),
            Positioned(
              top: 12,
              right: 12,
              child: MapViewToggle(
                value: widget.mapViewType,
                onChanged: widget.onMapViewTypeChanged,
                compact: true,
              ),
            ),
            if (widget.selectedMoment != null)
              Positioned(
                left: 12,
                right: 84,
                bottom: 12,
                child: _SelectedMomentOverlay(
                  title: widget.selectedMoment!.title,
                  subtitle: widget.selectedMoment!.subtitle,
                ),
              ),
          ],
        ),
      ],
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
              replayData: _replayData,
              currentIndex: _safeReplayIndex,
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
              right: 88,
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
            Positioned(
              top: 12,
              right: 12,
              child: MapViewToggle(
                value: widget.mapViewType,
                onChanged: widget.onMapViewTypeChanged,
                compact: true,
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
          onPlayPause: _togglePlayback,
          onReset: () {
            _seekToIndex(_selectedRangeStart);
            setState(() {
              _autoCameraEnabled = true;
              _cameraMode = FlightReplayCameraMode.overview;
            });
          },
          onProgressChanged: (value) {
            if (_selectedSegment == null) {
              _seekToIndex(_replayData.indexForProgress(value));
              return;
            }
            final localRange = max(
                1, _selectedSegment!.endIndex - _selectedSegment!.startIndex);
            final nextIndex = min(
              _selectedSegment!.endIndex,
              _selectedSegment!.startIndex + (value * localRange).round(),
            );
            _seekToIndex(nextIndex);
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF132230).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
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
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
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
  final VoidCallback onPlayPause;
  final ValueChanged<double> onProgressChanged;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F8),
        borderRadius: BorderRadius.circular(18),
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
                      selectedRangeLabel,
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
                  PopupMenuItem(value: 1.0, child: Text('1배속')),
                  PopupMenuItem(value: 2.0, child: Text('2배속')),
                  PopupMenuItem(value: 4.0, child: Text('4배속')),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
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
        color: const Color(0xFFF4F7F8),
        borderRadius: BorderRadius.circular(18),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
        color: const Color(0xFFF4F7F8),
        borderRadius: BorderRadius.circular(18),
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
