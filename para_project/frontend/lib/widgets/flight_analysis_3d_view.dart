import 'dart:convert';
import 'dart:math' as math;
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
  final bool isPlaying;
  final double height;

  @override
  State<FlightAnalysis3DView> createState() => _FlightAnalysis3DViewState();
}

class _FlightAnalysis3DViewState extends State<FlightAnalysis3DView> {
  static const double _followPitch = 64;
  static const double _cinematicPitch = 76;
  static const String _demSourceId = 'analysis-dem';
  static const String _routeSourceId = 'analysis-route';
  static const String _routeShadowLayerId = 'analysis-route-shadow';
  static const String _routeLayerId = 'analysis-route-line';
  static const String _routeProgressGlowLayerId = 'analysis-route-progress-glow';
  static const String _routeProgressLayerId = 'analysis-route-progress';
  static const String _hillshadeLayerId = 'analysis-hillshade';

  MapboxMap? _mapboxMap;
  bool _styleReady = false;
  int _projectionRequestId = 0;
  List<Offset?> _groundPoints = const [];
  Offset? _siteScreenPoint;
  double _cameraPitch = 0;
  double? _lastMotionBearing;

  @override
  void didUpdateWidget(covariant FlightAnalysis3DView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_mapboxMap == null) {
      return;
    }

    if (oldWidget.mapViewType != widget.mapViewType) {
      _styleReady = false;
      _mapboxMap!.loadStyleURI(_styleUri(widget.mapViewType));
      return;
    }

    final replayDataChanged =
        oldWidget.replayData.frames != widget.replayData.frames;
    if (replayDataChanged && _styleReady) {
      _lastMotionBearing = null;
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
    if (cameraModeChanged || autoDirectorChanged) {
      _lastMotionBearing = null;
    }
    final currentIndexChanged = oldWidget.currentIndex != widget.currentIndex;
    if ((currentIndexChanged || rangeChanged) && _styleReady) {
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
                widget.cameraMode == FlightReplayCameraMode.perspective))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncCamera(force: cameraModeChanged || autoDirectorChanged || rangeChanged);
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
        ? (_sitePoint ??
            Point(coordinates: Position(127.7669, 35.9078)))
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
                    : 52,
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
              child: _ReplayLegend(
                minAltitudeMeters: replayData.minAltitudeMeters,
                maxAltitudeMeters: replayData.maxAltitudeMeters,
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
        'exaggeration': 1.18,
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
        hillshadeExaggeration: 0.32,
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

    final geoJson = _routeGeoJson();
    GeoJsonSource? existingSource;
    try {
      final source = await style.getSource(_routeSourceId);
      if (source is GeoJsonSource) {
        existingSource = source;
      }
    } catch (_) {
      existingSource = null;
    }

    if (existingSource == null) {
      await style.addSource(
        GeoJsonSource(
          id: _routeSourceId,
          data: geoJson,
          lineMetrics: true,
          tolerance: 0.18,
        ),
      );
    } else {
      await existingSource.updateGeoJSON(geoJson);
    }

    await _syncRouteLayers();
  }

  Future<void> _syncRouteLayers() async {
    final replayData = widget.replayData;
    if (replayData.frames.length < 2) {
      return;
    }

    final progress = replayData.frames[_safeCurrentIndex].progress.clamp(0.0, 1.0);
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
            padding: MbxEdgeInsets(top: 80, left: 28, bottom: 220, right: 28),
          ),
          animation,
        );
      case FlightReplayCameraMode.overview:
        await _fitToRoute(
          pitch: 42,
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
              weight: 0.76,
            ),
            zoom: _zoomForFrame(currentFrame, cinematic: true),
            bearing: _motionBearing(
              replayData,
              leadIndex: leadIndex,
              currentFrame: currentFrame,
              smoothing: force ? 0.78 : 0.48,
            ),
            pitch: _cinematicPitch,
            padding: MbxEdgeInsets(top: 64, left: 20, bottom: 236, right: 20),
          ),
          MapAnimationOptions(duration: force ? 940 : 620),
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
          pitch: 60,
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
            center: _blendedFocusPoint(currentFrame, leadFrame, weight: 0.66),
            zoom: 15.25,
            bearing: bearing,
            pitch: 74,
            padding: MbxEdgeInsets(top: 72, left: 24, bottom: 230, right: 24),
          ),
          MapAnimationOptions(duration: force ? 920 : 620),
        );
      case _AutoReplayCameraStage.thermalFocus:
        await mapboxMap.easeTo(
          CameraOptions(
            center: _blendedFocusPoint(currentFrame, leadFrame, weight: 0.38),
            zoom: 15.05,
            bearing: _blendBearing(bearing, bearing + 18, 0.28),
            pitch: 69,
            padding: MbxEdgeInsets(top: 68, left: 20, bottom: 222, right: 20),
          ),
          MapAnimationOptions(duration: force ? 860 : 560),
        );
      case _AutoReplayCameraStage.cruiseFollow:
        await mapboxMap.easeTo(
          CameraOptions(
            center: _blendedFocusPoint(currentFrame, leadFrame, weight: 0.72),
            zoom: _zoomForFrame(currentFrame, cinematic: true),
            bearing: bearing,
            pitch: _cinematicPitch,
            padding: MbxEdgeInsets(top: 64, left: 20, bottom: 236, right: 20),
          ),
          MapAnimationOptions(duration: force ? 900 : 600),
        );
      case _AutoReplayCameraStage.landingFocus:
        await mapboxMap.easeTo(
          CameraOptions(
            center: _blendedFocusPoint(currentFrame, leadFrame, weight: 0.54),
            zoom: 15.0,
            bearing: _blendBearing(bearing, 0, 0.18),
            pitch: 58,
            padding: MbxEdgeInsets(top: 74, left: 26, bottom: 220, right: 26),
          ),
          MapAnimationOptions(duration: force ? 820 : 560),
        );
      case _AutoReplayCameraStage.summaryOverview:
        await _fitToRoute(
          pitch: 48,
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
    final targetFrames = replayData.frames
        .sublist(safeStart, safeEnd + 1);

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
    Offset? fallbackPoint;
    for (final pixel in pixels) {
      if (pixel == null) {
        projectedPoints.add(fallbackPoint);
        continue;
      }
      final offset = Offset(pixel.x, pixel.y);
      fallbackPoint = offset;
      projectedPoints.add(offset);
    }

    setState(() {
      _groundPoints = projectedPoints;
      _cameraPitch = cameraState.pitch;
      _siteScreenPoint =
          sitePixel == null ? null : Offset(sitePixel.x, sitePixel.y);
    });
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
}

class _FlightReplayAltitudeOverlay extends StatelessWidget {
  const _FlightReplayAltitudeOverlay({
    required this.replayData,
    required this.groundPoints,
    required this.currentIndex,
    required this.pitch,
    required this.sitePoint,
    required this.siteLabel,
  });

  final FlightReplayData replayData;
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
    required this.groundPoints,
    required this.currentIndex,
    required this.pitch,
    required this.sitePoint,
    required this.siteLabel,
  });

  final FlightReplayData replayData;
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

    final altitudeRange = math.max(
      1.0,
      replayData.maxAltitudeMeters - replayData.minAltitudeMeters,
    );
    final liftScale =
        math.min(size.height * 0.28, 128.0) * (0.46 + (pitch / 80.0));
    final elevatedPoints = <Offset?>[];

    for (var index = 0; index < groundPoints.length; index++) {
      final groundPoint = groundPoints[index];
      if (groundPoint == null) {
        elevatedPoints.add(null);
        continue;
      }

      final frame = replayData.frames[index];
      final normalized =
          (frame.displayAltitudeMeters - replayData.minAltitudeMeters) /
              altitudeRange;
      final lift = 10 + (normalized * liftScale);
      elevatedPoints.add(
        Offset(groundPoint.dx, groundPoint.dy - lift),
      );
    }

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

    _drawGroundRoute(canvas);
    _drawRemainingRoute(canvas, elevatedPoints);
    _drawThermalSegments(canvas, elevatedPoints);
    _drawCompletedRoute(
      canvas,
      elevatedPoints: elevatedPoints,
      currentSafeIndex: currentSafeIndex,
    );

    _drawStem(canvas, groundPoints.first, startPoint, const Color(0x802A9D8F));
    final takeoffPoint = elevatedPoints[replayData.takeoffFrameIndex];
    final landingPoint = elevatedPoints[replayData.landingFrameIndex];
    _drawStem(
      canvas,
      groundPoints[replayData.takeoffFrameIndex],
      takeoffPoint,
      const Color(0x80A8E063),
    );
    _drawStem(
      canvas,
      groundPoints[replayData.landingFrameIndex],
      landingPoint,
      const Color(0x80FFB74D),
    );
    _drawStem(
      canvas,
      groundPoints[replayData.highestFrameIndex],
      highestPoint,
      const Color(0x80F4A261),
    );
    _drawStem(canvas, groundPoints.last, endPoint, const Color(0x80E76F51));
    _drawStem(
      canvas,
      groundPoints[currentSafeIndex],
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

  void _drawGroundRoute(Canvas canvas) {
    Offset? previous;
    for (final point in groundPoints) {
      if (point == null) {
        previous = null;
        continue;
      }
      if (previous != null) {
        canvas.drawLine(
          previous,
          point,
          Paint()
            ..color = const Color(0x22000000)
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      }
      previous = point;
    }
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

  void _drawRemainingRoute(Canvas canvas, List<Offset?> elevatedPoints) {
    for (var index = 1; index < elevatedPoints.length; index++) {
      final previous = elevatedPoints[index - 1];
      final current = elevatedPoints[index];
      if (previous == null || current == null) {
        continue;
      }
      final altitudeAverage =
          (replayData.frames[index - 1].displayAltitudeMeters +
                  replayData.frames[index].displayAltitudeMeters) /
              2;
      final normalizedAltitude = (altitudeAverage -
              replayData.minAltitudeMeters) /
          math.max(
            1.0,
            replayData.maxAltitudeMeters - replayData.minAltitudeMeters,
          );
      canvas.drawLine(
        previous,
        current,
        Paint()
          ..color = _altitudeColor(normalizedAltitude).withValues(alpha: 0.74)
          ..strokeWidth = 4.2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _drawThermalSegments(Canvas canvas, List<Offset?> elevatedPoints) {
    for (final segment in replayData.thermalSegments) {
      for (var index = math.max(1, segment.startIndex + 1);
          index <= math.min(segment.endIndex, elevatedPoints.length - 1);
          index++) {
        final previous = elevatedPoints[index - 1];
        final current = elevatedPoints[index];
        if (previous == null || current == null) {
          continue;
        }
        canvas.drawLine(
          previous,
          current,
          Paint()
            ..color = const Color(0xCCFFD166)
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  void _drawCompletedRoute(
    Canvas canvas, {
    required List<Offset?> elevatedPoints,
    required int currentSafeIndex,
  }) {
    for (var index = 1; index <= currentSafeIndex; index++) {
      final previous = elevatedPoints[index - 1];
      final current = elevatedPoints[index];
      if (previous == null || current == null) {
        continue;
      }
      canvas.drawLine(
        previous,
        current,
        Paint()
          ..color = const Color(0x884CC9F0)
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawLine(
        previous,
        current,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.88)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  Color _altitudeColor(double normalizedAltitude) {
    final clamped = normalizedAltitude.clamp(0.0, 1.0);
    if (clamped < 0.5) {
      return Color.lerp(
            const Color(0xFF5BC0EB),
            const Color(0xFF4361EE),
            clamped / 0.5,
          ) ??
          const Color(0xFF4361EE);
    }
    return Color.lerp(
          const Color(0xFF4361EE),
          const Color(0xFFF4A261),
          (clamped - 0.5) / 0.5,
        ) ??
        const Color(0xFFF4A261);
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
        oldDelegate.groundPoints != groundPoints ||
        oldDelegate.sitePoint != sitePoint ||
        oldDelegate.siteLabel != siteLabel;
  }
}

class _ReplayLegend extends StatelessWidget {
  const _ReplayLegend({
    required this.minAltitudeMeters,
    required this.maxAltitudeMeters,
  });

  final double minAltitudeMeters;
  final double maxAltitudeMeters;

  @override
  Widget build(BuildContext context) {
    final altitudeSpan = (maxAltitudeMeters - minAltitudeMeters).abs();

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
