import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../core/flight_analysis_replay.dart';
import '../core/map_view_type.dart';

enum _AutoReplayCameraStage {
  introOverview,
  takeoffFocus,
  thermalFocus,
  cruiseFollow,
  landingFocus,
  summaryOverview,
}

class FlightAnalysis3DView extends StatefulWidget {
  const FlightAnalysis3DView({
    super.key,
    required this.replayData,
    required this.currentIndex,
    required this.cameraMode,
    required this.mapViewType,
    required this.autoDirectorEnabled,
    this.siteLatitude,
    this.siteLongitude,
    this.siteLabel,
    this.rangeStartIndex,
    this.rangeEndIndex,
    this.playbackProgress,
    this.isPlaying = false,
    this.height = 380,
  });

  final FlightReplayData replayData;
  final int currentIndex;
  final FlightReplayCameraMode cameraMode;
  final ParaglidingMapViewType mapViewType;
  final bool autoDirectorEnabled;
  final double? siteLatitude;
  final double? siteLongitude;
  final String? siteLabel;
  final int? rangeStartIndex;
  final int? rangeEndIndex;
  final double? playbackProgress;
  final bool isPlaying;
  final double height;

  @override
  State<FlightAnalysis3DView> createState() => FlightAnalysis3DViewState();
}

class FlightAnalysis3DViewState extends State<FlightAnalysis3DView> {
  static const double _followPitch = 68;
  static const double _cinematicPitch = 80;
  static const double _sidePitch = 84;
  static const double _terrainExaggeration = 1.38;
  static const String _demSourceId = 'analysis-dem';
  static const String _routeSourceId = 'analysis-route';
  static const String _routeShadowLayerId = 'analysis-route-shadow';
  static const String _routeLayerId = 'analysis-route-line';
  static const String _routeProgressGlowLayerId =
      'analysis-route-progress-glow';
  static const String _routeProgressLayerId = 'analysis-route-progress';
  static const String _elevatedRouteSourceId = 'analysis-route-elevated';
  static const String _elevatedRouteLayerId = 'analysis-route-elevated-line';
  static const String _elevatedRouteGlowLayerId =
      'analysis-route-elevated-glow';
  static const String _elevatedRouteProgressLayerId =
      'analysis-route-elevated-progress';
  static const String _elevatedRouteProgressGlowLayerId =
      'analysis-route-elevated-progress-glow';
  static const String _hillshadeLayerId = 'analysis-hillshade';

  MapboxMap? _mapboxMap;
  bool _styleReady = false;
  int _projectionRequestId = 0;
  List<Offset?> _groundPoints = const [];
  Offset? _siteScreenPoint;
  double _cameraPitch = 0;
  double? _lastMotionBearing;
  final Map<int, double> _terrainElevationCache = <int, double>{};
  FlightReplayTerrainAlignment _terrainAlignment =
      FlightReplayTerrainAlignment.empty;
  bool _terrainSamplingInProgress = false;
  bool _terrainSamplingQueued = false;
  DateTime? _lastTerrainSampleAt;

  Future<Uint8List?> captureSnapshot() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null || !_styleReady) {
      return null;
    }

    try {
      return await mapboxMap.snapshot();
    } catch (_) {
      return null;
    }
  }

  @override
  void didUpdateWidget(covariant FlightAnalysis3DView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_mapboxMap == null) {
      return;
    }

    if (oldWidget.mapViewType != widget.mapViewType) {
      _styleReady = false;
      _terrainElevationCache.clear();
      _terrainAlignment = FlightReplayTerrainAlignment.empty;
      _lastTerrainSampleAt = null;
      _mapboxMap!.loadStyleURI(_styleUri(widget.mapViewType));
      return;
    }

    final replayDataChanged =
        oldWidget.replayData.frames != widget.replayData.frames;
    if (replayDataChanged && _styleReady) {
      _lastMotionBearing = null;
      _terrainElevationCache.clear();
      _terrainAlignment = FlightReplayTerrainAlignment.empty;
      _lastTerrainSampleAt = null;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _updateRouteSource();
        await _syncCamera(force: true);
      });
      return;
    }

    final cameraModeChanged = oldWidget.cameraMode != widget.cameraMode;
    final autoDirectorChanged =
        oldWidget.autoDirectorEnabled != widget.autoDirectorEnabled;
    final rangeChanged = oldWidget.rangeStartIndex != widget.rangeStartIndex ||
        oldWidget.rangeEndIndex != widget.rangeEndIndex;
    final playbackProgressChanged =
        oldWidget.playbackProgress != widget.playbackProgress;
    if (cameraModeChanged || autoDirectorChanged) {
      _lastMotionBearing = null;
    }
    final currentIndexChanged = oldWidget.currentIndex != widget.currentIndex;
    if ((currentIndexChanged || rangeChanged || playbackProgressChanged) &&
        _styleReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncRouteLayers();
      });
    }

    if (cameraModeChanged ||
        autoDirectorChanged ||
        rangeChanged ||
        (currentIndexChanged &&
            (widget.autoDirectorEnabled ||
                widget.cameraMode == FlightReplayCameraMode.follow ||
                widget.cameraMode == FlightReplayCameraMode.perspective ||
                widget.cameraMode == FlightReplayCameraMode.sideView))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncCamera(
            force: cameraModeChanged || autoDirectorChanged || rangeChanged);
      });
    }
  }

  @override
  void dispose() {
    _projectionRequestId += 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final replayData = widget.replayData;
    final initialFrame =
        replayData.frames.isEmpty ? null : replayData.frames[_safeCurrentIndex];
    final initialCenter = initialFrame == null
        ? (_sitePoint ?? Point(coordinates: Position(127.7669, 35.9078)))
        : _pointFromFrame(initialFrame);

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MapWidget(
              key: ValueKey(
                'analysis-3d-${widget.mapViewType.name}',
              ),
              styleUri: _styleUri(widget.mapViewType),
              cameraOptions: CameraOptions(
                center: initialCenter,
                zoom: 14.6,
                pitch: widget.cameraMode == FlightReplayCameraMode.topDown
                    ? 0
                    : widget.cameraMode == FlightReplayCameraMode.sideView
                        ? 72
                        : 56,
                bearing: widget.cameraMode == FlightReplayCameraMode.follow
                    ? (initialFrame?.heading ?? 0)
                    : 0,
              ),
              onMapCreated: _onMapCreated,
              onStyleLoadedListener: _onStyleLoaded,
              onMapIdleListener: (_) => _refreshProjection(),
            ),
            IgnorePointer(
              child: _FlightReplayAltitudeOverlay(
                replayData: replayData,
                terrainAlignment: _terrainAlignment,
                groundPoints: _groundPoints,
                currentIndex: widget.currentIndex,
                pitch: _cameraPitch,
                sitePoint: _siteScreenPoint,
                siteLabel: widget.siteLabel,
              ),
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.06),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.18),
                    ],
                    stops: const [0.0, 0.35, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: _TerrainAwareReplayLegend(
                minAltitudeMeters: replayData.minAltitudeMeters,
                maxAltitudeMeters: replayData.maxAltitudeMeters,
                terrainAlignment: _terrainAlignment,
                currentIndex: _safeCurrentIndex,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    await _syncCamera(force: true);
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData _) async {
    _styleReady = true;
    await _configureStyle();
    await _syncCamera(force: true);
  }

  Future<void> _configureStyle() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) {
      return;
    }

    await _ensureDemSource();
    await _ensureTerrain();
    await _ensureHillshadeLayer();
    await _updateRouteSource();
  }

  Future<void> _ensureDemSource() async {
    final style = _mapboxMap?.style;
    if (style == null) {
      return;
    }

    try {
      final source = await style.getSource(_demSourceId);
      if (source != null) {
        return;
      }
    } catch (_) {
      // no-op
    }

    await style.addSource(
      RasterDemSource(
        id: _demSourceId,
        url: 'mapbox://mapbox.mapbox-terrain-dem-v1',
        tileSize: 512,
        maxzoom: 14,
        encoding: Encoding.MAPBOX,
      ),
    );
  }

  Future<void> _ensureTerrain() async {
    final style = _mapboxMap?.style;
    if (style == null) {
      return;
    }
    await style.setStyleTerrain(
      jsonEncode({
        'source': _demSourceId,
        'exaggeration': _terrainExaggeration,
      }),
    );
  }

  Future<void> _ensureHillshadeLayer() async {
    final style = _mapboxMap?.style;
    if (style == null) {
      return;
    }

    try {
      final existing = await style.getLayer(_hillshadeLayerId);
      if (existing != null) {
        return;
      }
    } catch (_) {
      // no-op
    }

    await style.addLayer(
      HillshadeLayer(
        id: _hillshadeLayerId,
        sourceId: _demSourceId,
        slot: LayerSlot.BOTTOM,
        hillshadeExaggeration: 0.46,
        hillshadeHighlightColor: const Color(0xFFEEF5FA).toARGB32(),
        hillshadeShadowColor: const Color(0xFF0C1722).toARGB32(),
        hillshadeAccentColor: const Color(0xFF4C7DA0).toARGB32(),
        hillshadeIlluminationAnchor: HillshadeIlluminationAnchor.MAP,
      ),
    );
  }

  Future<void> _updateRouteSource() async {
    final style = _mapboxMap?.style;
    if (style == null || widget.replayData.frames.length < 2) {
      return;
    }

    await _updateGeoJsonSource(
      id: _routeSourceId,
      data: _routeGeoJson(),
      lineMetrics: true,
      tolerance: 0.18,
    );

    if (_terrainAlignment.hasUsableSamples) {
      await _updateGeoJsonSource(
        id: _elevatedRouteSourceId,
        data: _elevatedRouteGeoJson(),
        lineMetrics: false,
        tolerance: 0.08,
      );
    } else {
      await _removeLayerIfExists(_elevatedRouteProgressGlowLayerId);
      await _removeLayerIfExists(_elevatedRouteProgressLayerId);
      await _removeLayerIfExists(_elevatedRouteGlowLayerId);
      await _removeLayerIfExists(_elevatedRouteLayerId);
      await _removeSourceIfExists(_elevatedRouteSourceId);
    }

    await _syncRouteLayers();
  }

  Future<void> _updateGeoJsonSource({
    required String id,
    required String data,
    required bool lineMetrics,
    required double tolerance,
  }) async {
    final style = _mapboxMap?.style;
    if (style == null) {
      return;
    }

    GeoJsonSource? existingSource;
    try {
      final source = await style.getSource(id);
      if (source is GeoJsonSource) {
        existingSource = source;
      }
    } catch (_) {
      existingSource = null;
    }

    if (existingSource == null) {
      await style.addSource(
        GeoJsonSource(
          id: id,
          data: data,
          lineMetrics: lineMetrics,
          tolerance: tolerance,
        ),
      );
      return;
    }

    await existingSource.updateGeoJSON(data);
  }

  Future<void> _syncRouteLayers() async {
    final replayData = widget.replayData;
    if (replayData.frames.length < 2) {
      return;
    }

    final progress = (widget.playbackProgress ??
            replayData.frames[_safeCurrentIndex].progress)
        .clamp(0.0, 1.0);
    final activeFilter = <Object>[
      '<=',
      ['get', 'segmentIndex'],
      _safeCurrentIndex.toDouble(),
    ];
    await _ensureRouteLayer(
      LineLayer(
        id: _routeShadowLayerId,
        sourceId: _routeSourceId,
        slot: LayerSlot.MIDDLE,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
        lineColor: const Color(0x3A142433).toARGB32(),
        lineWidth: 10.0,
        lineOpacity: 0.72,
        lineBlur: 1.8,
      ),
    );
    await _ensureRouteLayer(
      LineLayer(
        id: _routeLayerId,
        sourceId: _routeSourceId,
        slot: LayerSlot.MIDDLE,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
        lineWidth: 4.2,
        lineOpacity: 0.88,
        lineGradientExpression: _routeGradientExpression(),
      ),
    );
    await _ensureRouteLayer(
      LineLayer(
        id: _routeProgressGlowLayerId,
        sourceId: _routeSourceId,
        slot: LayerSlot.MIDDLE,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
        lineColor: const Color(0x80A7F3FF).toARGB32(),
        lineWidth: 11.0,
        lineOpacity: 0.82,
        lineBlur: 1.4,
        lineTrimOffset: [0.0, progress],
      ),
    );
    await _ensureRouteLayer(
      LineLayer(
        id: _routeProgressLayerId,
        sourceId: _routeSourceId,
        slot: LayerSlot.MIDDLE,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
        lineWidth: 5.2,
        lineOpacity: 0.96,
        lineGradientExpression: _progressGradientExpression(),
        lineTrimOffset: [0.0, progress],
      ),
    );

    if (_terrainAlignment.hasUsableSamples) {
      final zOffsetExpression = <Object>['get', 'zOffset'];
      await _ensureRouteLayer(
        LineLayer(
          id: _elevatedRouteGlowLayerId,
          sourceId: _elevatedRouteSourceId,
          slot: LayerSlot.MIDDLE,
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
          lineWidth: 7.6,
          lineOpacity: 0.38,
          lineBlur: 1.2,
          lineColor: const Color(0x70253E58).toARGB32(),
          lineOcclusionOpacity: 0.16,
          lineZOffsetExpression: zOffsetExpression,
        ),
      );
      await _ensureRouteLayer(
        LineLayer(
          id: _elevatedRouteLayerId,
          sourceId: _elevatedRouteSourceId,
          slot: LayerSlot.MIDDLE,
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
          lineWidth: 3.8,
          lineOpacity: 0.92,
          lineColorExpression: _elevatedRouteColorExpression(),
          lineOcclusionOpacity: 0.22,
          lineZOffsetExpression: zOffsetExpression,
        ),
      );
      await _ensureRouteLayer(
        LineLayer(
          id: _elevatedRouteProgressGlowLayerId,
          sourceId: _elevatedRouteSourceId,
          slot: LayerSlot.MIDDLE,
          filter: activeFilter,
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
          lineWidth: 10.8,
          lineOpacity: 0.72,
          lineBlur: 1.4,
          lineColor: const Color(0x66E0F6FF).toARGB32(),
          lineOcclusionOpacity: 0.22,
          lineZOffsetExpression: zOffsetExpression,
        ),
      );
      await _ensureRouteLayer(
        LineLayer(
          id: _elevatedRouteProgressLayerId,
          sourceId: _elevatedRouteSourceId,
          slot: LayerSlot.MIDDLE,
          filter: activeFilter,
          lineJoin: LineJoin.ROUND,
          lineCap: LineCap.ROUND,
          lineWidth: 5.0,
          lineOpacity: 1.0,
          lineColorExpression: _elevatedProgressColorExpression(),
          lineOcclusionOpacity: 0.28,
          lineZOffsetExpression: zOffsetExpression,
        ),
      );
    }
  }

  Future<void> _ensureRouteLayer(LineLayer layer) async {
    final style = _mapboxMap?.style;
    if (style == null) {
      return;
    }

    try {
      final existing = await style.getLayer(layer.id);
      if (existing == null) {
        await style.addLayer(layer);
        return;
      }
      await style.updateLayer(layer);
      return;
    } catch (_) {
      // no-op
    }

    await style.addLayer(layer);
  }

  Future<void> _syncCamera({bool force = false}) async {
    final mapboxMap = _mapboxMap;
    final replayData = widget.replayData;
    if (mapboxMap == null || !_styleReady || !replayData.hasFrames) {
      return;
    }

    if (widget.autoDirectorEnabled) {
      await _syncAutoDirectedCamera(force: force);
      return;
    }

    final currentFrame = replayData.frames[_safeCurrentIndex];
    final animation = MapAnimationOptions(
      duration: force ? 780 : 520,
    );

    switch (widget.cameraMode) {
      case FlightReplayCameraMode.follow:
        final leadIndex = replayData.futureFrameIndex(
          _safeCurrentIndex,
          minimumLeadFrames: 5,
          maximumLeadFrames: 16,
        );
        final leadFrame = replayData.frames[leadIndex];
        final focusPoint = _blendedFocusPoint(
          currentFrame,
          leadFrame,
          weight: 0.58,
        );
        await mapboxMap.easeTo(
          CameraOptions(
            center: focusPoint,
            zoom: _zoomForFrame(currentFrame, cinematic: false),
            bearing: _motionBearing(
              replayData,
              leadIndex: leadIndex,
              currentFrame: currentFrame,
              smoothing: force ? 0.72 : 0.42,
            ),
            pitch: _followPitch,
            padding: MbxEdgeInsets(top: 72, left: 24, bottom: 214, right: 24),
          ),
          animation,
        );
      case FlightReplayCameraMode.overview:
        await _fitToRoute(
          pitch: 50,
          bearing: 0,
          maxZoom: 15.7,
          duration: force ? 860 : 560,
        );
      case FlightReplayCameraMode.topDown:
        await _fitToRoute(
          pitch: 0,
          bearing: 0,
          maxZoom: 15.5,
          duration: force ? 820 : 520,
        );
      case FlightReplayCameraMode.perspective:
        final leadIndex = replayData.futureFrameIndex(
          _safeCurrentIndex,
          minimumLeadFrames: 8,
          maximumLeadFrames: 22,
        );
        final leadFrame = replayData.frames[leadIndex];
        await mapboxMap.easeTo(
          CameraOptions(
            center: _blendedFocusPoint(
              currentFrame,
              leadFrame,
              weight: 0.80,
            ),
            zoom: _zoomForFrame(currentFrame, cinematic: true),
            bearing: _motionBearing(
              replayData,
              leadIndex: leadIndex,
              currentFrame: currentFrame,
              smoothing: force ? 0.78 : 0.48,
            ),
            pitch: _cinematicPitch,
            padding: MbxEdgeInsets(top: 56, left: 18, bottom: 232, right: 18),
          ),
          MapAnimationOptions(duration: force ? 940 : 620),
        );
      case FlightReplayCameraMode.sideView:
        final leadIndex = replayData.futureFrameIndex(
          _safeCurrentIndex,
          minimumLeadFrames: 7,
          maximumLeadFrames: 24,
        );
        final leadFrame = replayData.frames[leadIndex];
        final travelBearing = _motionBearing(
          replayData,
          leadIndex: leadIndex,
          currentFrame: currentFrame,
          smoothing: force ? 0.84 : 0.50,
        );
        await mapboxMap.easeTo(
          CameraOptions(
            center: _blendedFocusPoint(
              currentFrame,
              leadFrame,
              weight: 0.74,
            ),
            zoom: _zoomForFrame(currentFrame, cinematic: true) - 0.35,
            bearing: _blendBearing(travelBearing, travelBearing + 34, 0.34),
            pitch: _sidePitch,
            padding: MbxEdgeInsets(top: 54, left: 16, bottom: 224, right: 16),
          ),
          MapAnimationOptions(duration: force ? 980 : 660),
        );
    }

    await _refreshProjection();
  }

  Future<void> _syncAutoDirectedCamera({bool force = false}) async {
    final mapboxMap = _mapboxMap;
    final replayData = widget.replayData;
    if (mapboxMap == null || !_styleReady || !replayData.hasFrames) {
      return;
    }

    final currentFrame = replayData.frames[_safeCurrentIndex];
    final stage = _autoStageForCurrentFrame(replayData, currentFrame);
    final leadIndex = switch (stage) {
      _AutoReplayCameraStage.thermalFocus => replayData.futureFrameIndex(
          _safeCurrentIndex,
          minimumLeadFrames: 3,
          maximumLeadFrames: 10,
        ),
      _AutoReplayCameraStage.takeoffFocus => replayData.futureFrameIndex(
          _safeCurrentIndex,
          minimumLeadFrames: 6,
          maximumLeadFrames: 14,
        ),
      _AutoReplayCameraStage.landingFocus => replayData.futureFrameIndex(
          _safeCurrentIndex,
          minimumLeadFrames: 2,
          maximumLeadFrames: 8,
        ),
      _AutoReplayCameraStage.introOverview => replayData.futureFrameIndex(
          _safeCurrentIndex,
          minimumLeadFrames: 10,
          maximumLeadFrames: 18,
        ),
      _AutoReplayCameraStage.summaryOverview => replayData.futureFrameIndex(
          _safeCurrentIndex,
          minimumLeadFrames: 6,
          maximumLeadFrames: 12,
        ),
      _AutoReplayCameraStage.cruiseFollow => replayData.futureFrameIndex(
          _safeCurrentIndex,
          minimumLeadFrames: 8,
          maximumLeadFrames: 22,
        ),
    };

    final leadFrame = replayData.frames[leadIndex];
    final bearing = _motionBearing(
      replayData,
      leadIndex: leadIndex,
      currentFrame: currentFrame,
      smoothing: force ? 0.82 : 0.44,
    );

    switch (stage) {
      case _AutoReplayCameraStage.introOverview:
        await _fitToRoute(
          pitch: 66,
          bearing: bearing,
          maxZoom: 15.4,
          duration: force ? 980 : 720,
          startIndex: _safeRangeStartIndex,
          endIndex: _safeRangeEndIndex,
          padding: MbxEdgeInsets(top: 58, left: 32, bottom: 112, right: 32),
        );
      case _AutoReplayCameraStage.takeoffFocus:
        await mapboxMap.easeTo(
          CameraOptions(
            center: _blendedFocusPoint(currentFrame, leadFrame, weight: 0.70),
            zoom: 15.1,
            bearing: _blendBearing(bearing, bearing + 26, 0.22),
            pitch: 80,
            padding: MbxEdgeInsets(top: 64, left: 18, bottom: 224, right: 18),
          ),
          MapAnimationOptions(duration: force ? 920 : 620),
        );
      case _AutoReplayCameraStage.thermalFocus:
        await mapboxMap.easeTo(
          CameraOptions(
            center: _blendedFocusPoint(currentFrame, leadFrame, weight: 0.42),
            zoom: 14.95,
            bearing: _blendBearing(bearing, bearing + 28, 0.36),
            pitch: 80,
            padding: MbxEdgeInsets(top: 62, left: 16, bottom: 220, right: 16),
          ),
          MapAnimationOptions(duration: force ? 860 : 560),
        );
      case _AutoReplayCameraStage.cruiseFollow:
        await mapboxMap.easeTo(
          CameraOptions(
            center: _blendedFocusPoint(currentFrame, leadFrame, weight: 0.78),
            zoom: _zoomForFrame(currentFrame, cinematic: true),
            bearing: _blendBearing(bearing, bearing + 10, 0.10),
            pitch: _cinematicPitch,
            padding: MbxEdgeInsets(top: 56, left: 16, bottom: 232, right: 16),
          ),
          MapAnimationOptions(duration: force ? 900 : 600),
        );
      case _AutoReplayCameraStage.landingFocus:
        await mapboxMap.easeTo(
          CameraOptions(
            center: _blendedFocusPoint(currentFrame, leadFrame, weight: 0.58),
            zoom: 14.9,
            bearing: _blendBearing(bearing, 0, 0.20),
            pitch: 64,
            padding: MbxEdgeInsets(top: 68, left: 20, bottom: 214, right: 20),
          ),
          MapAnimationOptions(duration: force ? 820 : 560),
        );
      case _AutoReplayCameraStage.summaryOverview:
        await _fitToRoute(
          pitch: 54,
          bearing: bearing,
          maxZoom: 15.6,
          duration: force ? 920 : 680,
          startIndex: _safeRangeStartIndex,
          endIndex: _safeRangeEndIndex,
          padding: MbxEdgeInsets(top: 54, left: 30, bottom: 108, right: 30),
        );
    }

    await _refreshProjection();
  }

  Future<void> _fitToRoute({
    required double pitch,
    required double bearing,
    required double maxZoom,
    required int duration,
    int? startIndex,
    int? endIndex,
    MbxEdgeInsets? padding,
  }) async {
    final mapboxMap = _mapboxMap;
    final replayData = widget.replayData;
    if (mapboxMap == null || !replayData.hasFrames) {
      return;
    }

    final safeStart = (startIndex ?? 0).clamp(0, replayData.frames.length - 1);
    final safeEnd = (endIndex ?? replayData.frames.length - 1)
        .clamp(safeStart, replayData.frames.length - 1);
    final targetFrames = replayData.frames.sublist(safeStart, safeEnd + 1);

    final points = targetFrames
        .map((frame) => _pointFromFrame(frame))
        .toList(growable: false);
    final camera = await mapboxMap.cameraForCoordinatesPadding(
      points,
      CameraOptions(
        pitch: pitch,
        bearing: bearing,
      ),
      padding ?? MbxEdgeInsets(top: 54, left: 40, bottom: 68, right: 40),
      maxZoom,
      null,
    );
    await mapboxMap.easeTo(
      CameraOptions(
        center: camera.center,
        zoom: camera.zoom,
        bearing: camera.bearing,
        pitch: camera.pitch,
      ),
      MapAnimationOptions(duration: duration),
    );
  }

  List<Object> _routeGradientExpression() {
    return const [
      'interpolate',
      ['linear'],
      ['line-progress'],
      0.0,
      ['rgba', 91, 192, 235, 0.82],
      0.42,
      ['rgba', 67, 97, 238, 0.88],
      0.78,
      ['rgba', 244, 162, 97, 0.92],
      1.0,
      ['rgba', 231, 111, 81, 0.94],
    ];
  }

  List<Object> _progressGradientExpression() {
    return const [
      'interpolate',
      ['linear'],
      ['line-progress'],
      0.0,
      ['rgba', 255, 255, 255, 0.92],
      0.42,
      ['rgba', 167, 243, 255, 0.96],
      0.82,
      ['rgba', 94, 203, 255, 1.0],
      1.0,
      ['rgba', 67, 97, 238, 1.0],
    ];
  }

  List<Object> _elevatedRouteColorExpression() {
    return const [
      'interpolate',
      ['linear'],
      [
        'coalesce',
        ['get', 'normalizedAltitude'],
        0.0
      ],
      0.0,
      ['rgba', 91, 192, 235, 0.82],
      0.42,
      ['rgba', 67, 97, 238, 0.88],
      0.78,
      ['rgba', 244, 162, 97, 0.92],
      1.0,
      ['rgba', 231, 111, 81, 0.94],
    ];
  }

  List<Object> _elevatedProgressColorExpression() {
    return const [
      'interpolate',
      ['linear'],
      [
        'coalesce',
        ['get', 'normalizedAltitude'],
        0.0
      ],
      0.0,
      ['rgba', 255, 255, 255, 0.94],
      0.42,
      ['rgba', 167, 243, 255, 0.98],
      0.82,
      ['rgba', 94, 203, 255, 1.0],
      1.0,
      ['rgba', 67, 97, 238, 1.0],
    ];
  }

  Point _blendedFocusPoint(
    FlightReplayFrame currentFrame,
    FlightReplayFrame leadFrame, {
    required double weight,
  }) {
    return Point(
      coordinates: Position(
        ui.lerpDouble(currentFrame.longitude, leadFrame.longitude, weight) ??
            currentFrame.longitude,
        ui.lerpDouble(currentFrame.latitude, leadFrame.latitude, weight) ??
            currentFrame.latitude,
      ),
    );
  }

  double _zoomForFrame(
    FlightReplayFrame frame, {
    required bool cinematic,
  }) {
    final speedRatio = (frame.speedMps / 15.0).clamp(0.0, 1.0);
    final start = cinematic ? 15.4 : 16.0;
    final end = cinematic ? 14.6 : 15.2;
    return ui.lerpDouble(start, end, speedRatio) ?? start;
  }

  double _motionBearing(
    FlightReplayData replayData, {
    required int leadIndex,
    required FlightReplayFrame currentFrame,
    required double smoothing,
  }) {
    final targetBearing = replayData.bearingBetweenIndices(
      _safeCurrentIndex,
      leadIndex,
    );
    final blendedTarget = _blendBearing(
      currentFrame.heading,
      targetBearing,
      0.72,
    );
    final previous = _lastMotionBearing ?? blendedTarget;
    final next = _blendBearing(previous, blendedTarget, smoothing);
    _lastMotionBearing = next;
    return next;
  }

  double _blendBearing(double from, double to, double t) {
    final delta = ((to - from + 540) % 360) - 180;
    return ((from + (delta * t)) % 360 + 360) % 360;
  }

  int get _safeRangeStartIndex {
    if (!widget.replayData.hasFrames) {
      return 0;
    }
    return (widget.rangeStartIndex ?? 0)
        .clamp(0, widget.replayData.frames.length - 1)
        .toInt();
  }

  int get _safeRangeEndIndex {
    if (!widget.replayData.hasFrames) {
      return 0;
    }
    return (widget.rangeEndIndex ?? widget.replayData.frames.length - 1)
        .clamp(_safeRangeStartIndex, widget.replayData.frames.length - 1)
        .toInt();
  }

  double get _rangeProgress {
    final span = math.max(1, _safeRangeEndIndex - _safeRangeStartIndex);
    return ((_safeCurrentIndex - _safeRangeStartIndex) / span).clamp(0.0, 1.0);
  }

  _AutoReplayCameraStage _autoStageForCurrentFrame(
    FlightReplayData replayData,
    FlightReplayFrame currentFrame,
  ) {
    final rangeProgress = _rangeProgress;
    final onThermal = replayData.thermalSegments.any(
      (segment) =>
          _safeCurrentIndex >= segment.startIndex &&
          _safeCurrentIndex <= segment.endIndex,
    );
    final nearHighestPoint =
        (_safeCurrentIndex - replayData.highestFrameIndex).abs() <= 2;

    if (!widget.isPlaying && rangeProgress >= 0.96) {
      return _AutoReplayCameraStage.summaryOverview;
    }
    if (rangeProgress <= 0.08) {
      return _AutoReplayCameraStage.introOverview;
    }
    if (_safeCurrentIndex <= replayData.takeoffFrameIndex + 3) {
      return _AutoReplayCameraStage.takeoffFocus;
    }
    if (onThermal || nearHighestPoint) {
      return _AutoReplayCameraStage.thermalFocus;
    }
    if (_safeCurrentIndex >= replayData.landingFrameIndex ||
        rangeProgress >= 0.88) {
      return _AutoReplayCameraStage.landingFocus;
    }
    return _AutoReplayCameraStage.cruiseFollow;
  }

  Future<void> _refreshProjection() async {
    final mapboxMap = _mapboxMap;
    final replayData = widget.replayData;
    if (mapboxMap == null || !_styleReady || replayData.frames.isEmpty) {
      return;
    }

    final requestId = ++_projectionRequestId;
    final coordinates = replayData.frames
        .map((frame) => _pointFromFrame(frame))
        .toList(growable: false);

    final pixels = await mapboxMap.pixelsForCoordinates(coordinates);
    final cameraState = await mapboxMap.getCameraState();
    ScreenCoordinate? sitePixel;
    if (_sitePoint != null) {
      sitePixel = await mapboxMap.pixelForCoordinate(_sitePoint!);
    }

    if (!mounted || requestId != _projectionRequestId) {
      return;
    }

    final projectedPoints = <Offset?>[];
    for (final pixel in pixels) {
      if (pixel == null) {
        projectedPoints.add(null);
        continue;
      }
      final offset = Offset(pixel.x, pixel.y);
      projectedPoints.add(offset);
    }

    setState(() {
      _groundPoints = projectedPoints;
      _cameraPitch = cameraState.pitch;
      _siteScreenPoint =
          sitePixel == null ? null : Offset(sitePixel.x, sitePixel.y);
    });
    _scheduleTerrainSampling();
  }

  Point? get _sitePoint {
    if (widget.siteLatitude == null || widget.siteLongitude == null) {
      return null;
    }
    return Point(
      coordinates: Position(widget.siteLongitude!, widget.siteLatitude!),
    );
  }

  Point _pointFromFrame(FlightReplayFrame frame) {
    return Point(
      coordinates: Position(frame.longitude, frame.latitude),
    );
  }

  int get _safeCurrentIndex {
    if (!widget.replayData.hasFrames) {
      return 0;
    }
    return math.min(
      math.max(0, widget.currentIndex),
      widget.replayData.frames.length - 1,
    );
  }

  String _styleUri(ParaglidingMapViewType type) {
    return type == ParaglidingMapViewType.standard
        ? MapboxStyles.OUTDOORS
        : MapboxStyles.STANDARD_SATELLITE;
  }

  String _routeGeoJson() {
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {
            'id': 'analysis-route',
          },
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final frame in widget.replayData.frames)
                [frame.longitude, frame.latitude],
            ],
          },
        },
      ],
    });
  }

  String _elevatedRouteGeoJson() {
    final replayData = widget.replayData;
    if (!_terrainAlignment.hasUsableSamples || replayData.frames.length < 2) {
      return jsonEncode({
        'type': 'FeatureCollection',
        'features': const <Object>[],
      });
    }

    final features = <Map<String, Object?>>[];
    for (var index = 1; index < replayData.frames.length; index++) {
      final previous = replayData.frames[index - 1];
      final current = replayData.frames[index];
      final startAlignment = _terrainAlignment.frameAt(index - 1);
      final endAlignment = _terrainAlignment.frameAt(index);
      final altitudeAverage =
          (previous.displayAltitudeMeters + current.displayAltitudeMeters) / 2;
      final normalizedAltitude =
          (altitudeAverage - replayData.minAltitudeMeters) /
              math.max(
                1.0,
                replayData.maxAltitudeMeters - replayData.minAltitudeMeters,
              );
      features.add({
        'type': 'Feature',
        'properties': {
          'segmentIndex': index.toDouble(),
          'zOffset': ((startAlignment.visualClearanceMeters +
                      endAlignment.visualClearanceMeters) /
                  2)
              .clamp(1.4, 20000.0),
          'normalizedAltitude': normalizedAltitude.clamp(0.0, 1.0),
          'isThermal': _segmentIsThermal(index) ? 1 : 0,
        },
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [previous.longitude, previous.latitude],
            [current.longitude, current.latitude],
          ],
        },
      });
    }

    return jsonEncode({
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  bool _segmentIsThermal(int index) {
    for (final segment in widget.replayData.thermalSegments) {
      if (index >= segment.startIndex && index <= segment.endIndex) {
        return true;
      }
    }
    return false;
  }

  Future<void> _removeLayerIfExists(String id) async {
    final style = _mapboxMap?.style;
    if (style == null) {
      return;
    }
    try {
      final layer = await style.getLayer(id);
      if (layer != null) {
        await style.removeStyleLayer(id);
      }
    } catch (_) {
      // no-op
    }
  }

  Future<void> _removeSourceIfExists(String id) async {
    final style = _mapboxMap?.style;
    if (style == null) {
      return;
    }
    try {
      final source = await style.getSource(id);
      if (source != null) {
        await style.removeStyleSource(id);
      }
    } catch (_) {
      // no-op
    }
  }

  void _scheduleTerrainSampling() {
    if (!mounted || !_styleReady || widget.replayData.frames.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final minimumGap = widget.isPlaying
        ? const Duration(milliseconds: 1400)
        : const Duration(milliseconds: 520);
    if (_lastTerrainSampleAt != null &&
        now.difference(_lastTerrainSampleAt!) < minimumGap) {
      return;
    }
    if (_terrainAlignment.hasUsableSamples &&
        _hasDenseTerrainCoverageAroundCurrent()) {
      return;
    }
    if (_terrainSamplingInProgress) {
      _terrainSamplingQueued = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sampleVisibleTerrainElevations();
    });
  }

  Future<void> _sampleVisibleTerrainElevations() async {
    final mapboxMap = _mapboxMap;
    if (!mounted ||
        !_styleReady ||
        mapboxMap == null ||
        widget.replayData.frames.isEmpty ||
        _terrainSamplingInProgress) {
      return;
    }

    final candidateIndices = _buildTerrainSamplingCandidates();

    if (candidateIndices.isEmpty) {
      return;
    }

    _terrainSamplingInProgress = true;
    _lastTerrainSampleAt = DateTime.now();
    try {
      var added = false;
      for (var order = 0; order < candidateIndices.length; order++) {
        final index = candidateIndices[order];
        final elevation = await mapboxMap.getElevation(
          _pointFromFrame(widget.replayData.frames[index]),
        );
        if (elevation == null || !elevation.isFinite) {
          continue;
        }
        _terrainElevationCache[index] = elevation / _terrainExaggeration;
        added = true;
        if (order % 6 == 5) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      if (!added || !mounted) {
        return;
      }

      final terrainSeries = List<double?>.filled(
        widget.replayData.frames.length,
        null,
      );
      for (final entry in _terrainElevationCache.entries) {
        if (entry.key >= 0 && entry.key < terrainSeries.length) {
          terrainSeries[entry.key] = entry.value;
        }
      }

      final alignment = FlightReplayTerrainAlignment.fromTerrainSamples(
        widget.replayData,
        terrainSeries,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _terrainAlignment = alignment;
      });
      await _updateRouteSource();
    } finally {
      _terrainSamplingInProgress = false;
      if (_terrainSamplingQueued) {
        _terrainSamplingQueued = false;
        _scheduleTerrainSampling();
      }
    }
  }

  bool _hasDenseTerrainCoverageAroundCurrent() {
    final frameCount = widget.replayData.frames.length;
    if (frameCount < 2) {
      return true;
    }
    final radius = widget.isPlaying ? 14 : 22;
    final start = math.max(0, _safeCurrentIndex - radius);
    final end = math.min(frameCount - 1, _safeCurrentIndex + radius);
    var covered = 0;
    var total = 0;
    for (var index = start; index <= end; index += 2) {
      total += 1;
      if (_terrainElevationCache.containsKey(index)) {
        covered += 1;
      }
    }
    if (total == 0) {
      return true;
    }
    return covered / total >= 0.82;
  }

  List<int> _buildTerrainSamplingCandidates() {
    final frameCount = widget.replayData.frames.length;
    if (frameCount < 2) {
      return const [];
    }

    final viewportWidth = MediaQuery.sizeOf(context).width;
    final viewportHeight = widget.height;
    final limit = widget.isPlaying ? 28 : 42;
    final result = <int>[];

    bool isVisible(int index) {
      if (index < 0 || index >= _groundPoints.length) {
        return false;
      }
      final point = _groundPoints[index];
      if (point == null) {
        return false;
      }
      return point.dx >= -32 &&
          point.dx <= viewportWidth + 32 &&
          point.dy >= -32 &&
          point.dy <= viewportHeight + 32;
    }

    void addIndex(int index) {
      if (result.length >= limit) {
        return;
      }
      if (index < 0 || index >= frameCount) {
        return;
      }
      if (_terrainElevationCache.containsKey(index) || !isVisible(index)) {
        return;
      }
      if (!result.contains(index)) {
        result.add(index);
      }
    }

    final localRadius = widget.isPlaying ? 18 : 28;
    addIndex(_safeCurrentIndex);
    for (var offset = 1; offset <= localRadius; offset++) {
      addIndex(_safeCurrentIndex + offset);
      addIndex(_safeCurrentIndex - offset);
      if (result.length >= limit) {
        return result;
      }
    }

    addIndex(0);
    addIndex(frameCount - 1);
    addIndex(widget.replayData.highestFrameIndex);
    addIndex(widget.replayData.takeoffFrameIndex);
    addIndex(widget.replayData.landingFrameIndex);
    for (final segment in widget.replayData.thermalSegments) {
      addIndex(segment.startIndex);
      addIndex(segment.endIndex);
      if (result.length >= limit) {
        return result;
      }
    }

    final visibleStep = frameCount > 1200
        ? 16
        : frameCount > 700
            ? 12
            : frameCount > 360
                ? 8
                : 5;
    for (var index = 0; index < frameCount; index += visibleStep) {
      addIndex(index);
      if (result.length >= limit) {
        break;
      }
    }

    return result;
  }
}

class _FlightReplayAltitudeOverlay extends StatelessWidget {
  const _FlightReplayAltitudeOverlay({
    required this.replayData,
    required this.terrainAlignment,
    required this.groundPoints,
    required this.currentIndex,
    required this.pitch,
    required this.sitePoint,
    required this.siteLabel,
  });

  final FlightReplayData replayData;
  final FlightReplayTerrainAlignment terrainAlignment;
  final List<Offset?> groundPoints;
  final int currentIndex;
  final double pitch;
  final Offset? sitePoint;
  final String? siteLabel;

  @override
  Widget build(BuildContext context) {
    if (groundPoints.length < 2 || replayData.frames.length < 2) {
      return const SizedBox.shrink();
    }

    return SizedBox.expand(
      child: CustomPaint(
        painter: _FlightReplayAltitudePainter(
          replayData: replayData,
          terrainAlignment: terrainAlignment,
          groundPoints: groundPoints,
          currentIndex: currentIndex,
          pitch: pitch,
          sitePoint: sitePoint,
          siteLabel: siteLabel,
        ),
      ),
    );
  }
}

class _FlightReplayAltitudePainter extends CustomPainter {
  const _FlightReplayAltitudePainter({
    required this.replayData,
    required this.terrainAlignment,
    required this.groundPoints,
    required this.currentIndex,
    required this.pitch,
    required this.sitePoint,
    required this.siteLabel,
  });

  final FlightReplayData replayData;
  final FlightReplayTerrainAlignment terrainAlignment;
  final List<Offset?> groundPoints;
  final int currentIndex;
  final double pitch;
  final Offset? sitePoint;
  final String? siteLabel;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    if (groundPoints.length < 2 || replayData.frames.length < 2) {
      return;
    }

    final visibleGroundPoints = _sanitizeGroundPoints(size);
    if (visibleGroundPoints.whereType<Offset>().length < 2) {
      return;
    }

    final useTerrainAlignedRendering = terrainAlignment.hasUsableSamples &&
        terrainAlignment.frames.length == replayData.frames.length;
    final elevatedPoints = _buildElevatedPoints(
      size,
      projectedPoints: visibleGroundPoints,
      useTerrainAlignedRendering: useTerrainAlignedRendering,
    );

    final currentSafeIndex = math.min(
      math.max(0, currentIndex),
      elevatedPoints.length - 1,
    );
    final currentPoint = elevatedPoints[currentSafeIndex];
    final highestPoint = elevatedPoints[replayData.highestFrameIndex];
    final startPoint = elevatedPoints.first;
    final endPoint = elevatedPoints.last;
    if (currentPoint == null ||
        highestPoint == null ||
        startPoint == null ||
        endPoint == null) {
      return;
    }

    _drawStem(
      canvas,
      visibleGroundPoints.first,
      startPoint,
      const Color(0x802A9D8F),
    );
    final takeoffPoint = elevatedPoints[replayData.takeoffFrameIndex];
    final landingPoint = elevatedPoints[replayData.landingFrameIndex];
    _drawStem(
      canvas,
      visibleGroundPoints[replayData.takeoffFrameIndex],
      takeoffPoint,
      const Color(0x80A8E063),
    );
    _drawStem(
      canvas,
      visibleGroundPoints[replayData.landingFrameIndex],
      landingPoint,
      const Color(0x80FFB74D),
    );
    _drawStem(
      canvas,
      visibleGroundPoints[replayData.highestFrameIndex],
      highestPoint,
      const Color(0x80F4A261),
    );
    _drawStem(
      canvas,
      visibleGroundPoints.last,
      endPoint,
      const Color(0x80E76F51),
    );
    _drawStem(
      canvas,
      visibleGroundPoints[currentSafeIndex],
      currentPoint,
      const Color(0x80FFFFFF),
    );

    _drawMarker(canvas, startPoint, const Color(0xFF2A9D8F), 6);
    _drawMarker(canvas, endPoint, const Color(0xFFE76F51), 6);
    if (takeoffPoint != null && (replayData.takeoffFrameIndex - 0).abs() > 1) {
      _drawMarker(canvas, takeoffPoint, const Color(0xFFA8E063), 5);
    }
    if (landingPoint != null &&
        (replayData.landingFrameIndex - (elevatedPoints.length - 1)).abs() >
            1) {
      _drawMarker(canvas, landingPoint, const Color(0xFFFFB74D), 5);
    }
    _drawDiamond(canvas, highestPoint, const Color(0xFFF4A261), 8);
    _drawCurrentMarker(canvas, currentPoint);

    _drawLabel(
      canvas,
      position: startPoint.translate(0, -18),
      text: '시작',
      background: const Color(0xFF1F4C45),
    );
    _drawLabel(
      canvas,
      position: endPoint.translate(0, -18),
      text: '종료',
      background: const Color(0xFF5D2417),
    );
    if (takeoffPoint != null && (replayData.takeoffFrameIndex - 0).abs() > 1) {
      _drawLabel(
        canvas,
        position: takeoffPoint.translate(0, -18),
        text: '이륙 추정',
        background: const Color(0xFF36521C),
      );
    }
    if (landingPoint != null &&
        (replayData.landingFrameIndex - (elevatedPoints.length - 1)).abs() >
            1) {
      _drawLabel(
        canvas,
        position: landingPoint.translate(0, -18),
        text: '착륙 추정',
        background: const Color(0xFF6C4A14),
      );
    }
    _drawLabel(
      canvas,
      position: highestPoint.translate(0, -18),
      text: '최고점',
      background: const Color(0xFF1E2D38),
    );

    if (sitePoint != null) {
      _drawSiteMarker(canvas, sitePoint!);
      if (siteLabel != null && siteLabel!.trim().isNotEmpty) {
        _drawLabel(
          canvas,
          position: sitePoint!.translate(0, -24),
          text: siteLabel!,
          background: const Color(0xFF18354A),
        );
      }
    }
  }

  List<Offset?> _buildElevatedPoints(
    ui.Size size, {
    required List<Offset?> projectedPoints,
    required bool useTerrainAlignedRendering,
  }) {
    if (useTerrainAlignedRendering) {
      final maxClearance = math.max(
        12.0,
        terrainAlignment.maxVisualClearanceMeters,
      );
      final liftScale =
          math.min(size.height * 0.22, 116.0) * (0.62 + (pitch / 84.0));
      return List<Offset?>.generate(projectedPoints.length, (index) {
        final groundPoint = projectedPoints[index];
        if (groundPoint == null) {
          return null;
        }
        final clearance = terrainAlignment.visualClearanceAt(index);
        final normalized = (clearance / maxClearance).clamp(0.0, 1.0);
        final lift = 8 + (normalized * liftScale);
        return Offset(groundPoint.dx, groundPoint.dy - lift);
      }, growable: false);
    }

    final altitudeRange = math.max(
      1.0,
      replayData.maxAltitudeMeters - replayData.minAltitudeMeters,
    );
    final liftScale =
        math.min(size.height * 0.36, 168.0) * (0.58 + (pitch / 78.0));
    return List<Offset?>.generate(projectedPoints.length, (index) {
      final groundPoint = projectedPoints[index];
      if (groundPoint == null) {
        return null;
      }
      final frame = replayData.frames[index];
      final normalized =
          (frame.displayAltitudeMeters - replayData.minAltitudeMeters) /
              altitudeRange;
      final lift = 10 + (normalized * liftScale);
      return Offset(groundPoint.dx, groundPoint.dy - lift);
    }, growable: false);
  }

  List<Offset?> _sanitizeGroundPoints(ui.Size size) {
    final horizontalMargin = size.width * 1.2;
    final verticalMargin = size.height * 1.2;
    return List<Offset?>.generate(groundPoints.length, (index) {
      final point = groundPoints[index];
      if (point == null || !point.dx.isFinite || !point.dy.isFinite) {
        return null;
      }
      if (point.dx < -horizontalMargin ||
          point.dx > size.width + horizontalMargin ||
          point.dy < -verticalMargin ||
          point.dy > size.height + verticalMargin) {
        return null;
      }
      return point;
    }, growable: false);
  }

  void _drawStem(Canvas canvas, Offset? from, Offset? to, Color color) {
    if (from == null || to == null) {
      return;
    }
    canvas.drawLine(
      from,
      to,
      Paint()
        ..color = color
        ..strokeWidth = 1.6,
    );
  }

  void _drawMarker(Canvas canvas, Offset center, Color color, double radius) {
    canvas.drawCircle(
      center,
      radius + 2,
      Paint()..color = Colors.white.withValues(alpha: 0.88),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = color,
    );
  }

  void _drawDiamond(Canvas canvas, Offset center, Color color, double radius) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..lineTo(center.dx + radius, center.dy)
      ..lineTo(center.dx, center.dy + radius)
      ..lineTo(center.dx - radius, center.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawCurrentMarker(Canvas canvas, Offset center) {
    canvas.drawCircle(
      center,
      13,
      Paint()..color = const Color(0x33FFFFFF),
    );
    canvas.drawCircle(
      center,
      8,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      center,
      5,
      Paint()..color = const Color(0xFF4361EE),
    );
  }

  void _drawSiteMarker(Canvas canvas, Offset center) {
    canvas.drawCircle(
      center,
      14,
      Paint()..color = Colors.white.withValues(alpha: 0.94),
    );
    canvas.drawCircle(
      center,
      10,
      Paint()..color = const Color(0xFF1D6FA5),
    );
    canvas.drawCircle(
      center,
      4,
      Paint()..color = Colors.white,
    );
  }

  void _drawLabel(
    Canvas canvas, {
    required Offset position,
    required String text,
    required Color background,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 140);

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        position.dx - (textPainter.width / 2) - 8,
        position.dy - 5,
        textPainter.width + 16,
        textPainter.height + 10,
      ),
      const Radius.circular(999),
    );

    canvas.drawRRect(
      rect,
      Paint()..color = background.withValues(alpha: 0.92),
    );
    textPainter.paint(
      canvas,
      Offset(
        position.dx - (textPainter.width / 2),
        position.dy,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _FlightReplayAltitudePainter oldDelegate) {
    return oldDelegate.currentIndex != currentIndex ||
        oldDelegate.pitch != pitch ||
        oldDelegate.replayData.frames != replayData.frames ||
        oldDelegate.terrainAlignment.frames != terrainAlignment.frames ||
        oldDelegate.groundPoints != groundPoints ||
        oldDelegate.sitePoint != sitePoint ||
        oldDelegate.siteLabel != siteLabel;
  }
}

// ignore: unused_element
class _TerrainAwareReplayLegend extends StatelessWidget {
  const _TerrainAwareReplayLegend({
    required this.minAltitudeMeters,
    required this.maxAltitudeMeters,
    required this.terrainAlignment,
    required this.currentIndex,
  });

  final double minAltitudeMeters;
  final double maxAltitudeMeters;
  final FlightReplayTerrainAlignment terrainAlignment;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final altitudeSpan = (maxAltitudeMeters - minAltitudeMeters).abs();
    final clearanceText = terrainAlignment.hasUsableSamples
        ? '지면 대비 ${terrainAlignment.visualClearanceAt(currentIndex).toStringAsFixed(0)}m'
        : '지형 정렬 보정 중';
    final biasText = terrainAlignment.biasApplied
        ? '보정 ${terrainAlignment.altitudeBiasMeters.toStringAsFixed(0)}m'
        : '보정 최소화';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF11202C).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '경로 해석',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 10,
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF5BC0EB),
                          Color(0xFF4361EE),
                          Color(0xFFF4A261),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const _LegendChip(
                  color: Color(0xCCFFD166),
                  label: '써멀 추정',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '낮은 고도',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(width: 12),
                Text(
                  '높은 고도',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _LegendChip(
                  color: Color(0xFFA8E063),
                  label: '이륙 추정',
                ),
                _LegendChip(
                  color: Color(0xFFFFB74D),
                  label: '착륙 추정',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '고도 폭 ${altitudeSpan.toStringAsFixed(0)}m',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.76),
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              clearanceText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              biasText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.60),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
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
    );
  }
}
