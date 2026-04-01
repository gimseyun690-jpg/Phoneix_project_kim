import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../core/flight_analysis_replay.dart';
import '../core/map_view_type.dart';

class FlightAnalysis3DView extends StatefulWidget {
  const FlightAnalysis3DView({
    super.key,
    required this.replayData,
    required this.currentIndex,
    required this.cameraMode,
    required this.mapViewType,
    this.siteLatitude,
    this.siteLongitude,
    this.siteLabel,
    this.height = 380,
  });

  final FlightReplayData replayData;
  final int currentIndex;
  final FlightReplayCameraMode cameraMode;
  final ParaglidingMapViewType mapViewType;
  final double? siteLatitude;
  final double? siteLongitude;
  final String? siteLabel;
  final double height;

  @override
  State<FlightAnalysis3DView> createState() => _FlightAnalysis3DViewState();
}

class _FlightAnalysis3DViewState extends State<FlightAnalysis3DView> {
  static const double _followPitch = 58;

  MapController? _controller;

  @override
  void didUpdateWidget(covariant FlightAnalysis3DView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final controller = _controller;
    if (controller == null || !widget.replayData.hasFrames) {
      return;
    }

    if (oldWidget.mapViewType != widget.mapViewType) {
      controller.setStyle(_styleDocument(widget.mapViewType));
    }

    final cameraModeChanged = oldWidget.cameraMode != widget.cameraMode;
    final currentIndexChanged = oldWidget.currentIndex != widget.currentIndex;
    if (cameraModeChanged ||
        (currentIndexChanged &&
            widget.cameraMode == FlightReplayCameraMode.follow)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncCamera(force: cameraModeChanged);
      });
    }
  }

  Future<void> _syncCamera({bool force = false}) async {
    final controller = _controller;
    final replayData = widget.replayData;
    if (controller == null || !replayData.hasFrames) {
      return;
    }

    final currentFrame = replayData.frames[_safeCurrentIndex];
    final currentCamera = controller.camera ?? controller.getCamera();

    switch (widget.cameraMode) {
      case FlightReplayCameraMode.follow:
        await controller.animateCamera(
          center: _toGeographic(currentFrame),
          zoom: currentCamera.zoom < 15.4 ? 15.8 : currentCamera.zoom,
          bearing: currentFrame.heading,
          pitch: _followPitch,
          nativeDuration: const Duration(milliseconds: 520),
          webSpeed: 2.0,
          webMaxDuration: const Duration(milliseconds: 520),
        );
      case FlightReplayCameraMode.overview:
        await _fitToRoute(
          pitch: 42,
          bearing: 0,
          force: force,
        );
      case FlightReplayCameraMode.topDown:
        await _fitToRoute(
          pitch: 0,
          bearing: 0,
          force: force,
        );
      case FlightReplayCameraMode.perspective:
        await _fitToRoute(
          pitch: 56,
          bearing: _overallBearing(replayData),
          force: force,
        );
    }
  }

  Future<void> _fitToRoute({
    required double pitch,
    required double bearing,
    required bool force,
  }) async {
    final controller = _controller;
    final replayData = widget.replayData;
    if (controller == null || !replayData.hasFrames) {
      return;
    }

    final bounds = LngLatBounds.fromPoints(
      replayData.frames.map(_toGeographic).toList(growable: false),
    );

    await controller.fitBounds(
      bounds: bounds,
      pitch: pitch,
      bearing: bearing,
      nativeDuration: force
          ? const Duration(milliseconds: 620)
          : const Duration(milliseconds: 460),
      webSpeed: 1.9,
      webMaxDuration: force
          ? const Duration(milliseconds: 620)
          : const Duration(milliseconds: 460),
      padding: const EdgeInsets.fromLTRB(42, 48, 42, 60),
    );
  }

  @override
  Widget build(BuildContext context) {
    final replayData = widget.replayData;
    final initialFrame =
        replayData.frames.isEmpty ? null : replayData.frames[_safeCurrentIndex];
    final sitePoint =
        widget.siteLatitude == null || widget.siteLongitude == null
            ? null
            : Geographic(lon: widget.siteLongitude!, lat: widget.siteLatitude!);

    final initialCenter = initialFrame == null
        ? (sitePoint ?? const Geographic(lon: 127.7669, lat: 35.9078))
        : _toGeographic(initialFrame);

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MapLibreMap(
              onMapCreated: (controller) {
                _controller = controller;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _syncCamera(force: true);
                });
              },
              options: MapOptions(
                initStyle: _styleDocument(widget.mapViewType),
                initCenter: initialCenter,
                initZoom: 14.4,
                initPitch: widget.cameraMode == FlightReplayCameraMode.topDown
                    ? 0
                    : 46,
                initBearing: widget.cameraMode == FlightReplayCameraMode.follow
                    ? (initialFrame?.heading ?? 0)
                    : 0,
                minPitch: 0,
                maxPitch: 60,
                maxZoom: 18.5,
              ),
              layers: [
                if (replayData.frames.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Feature<LineString>(
                        id: 'analysis-ground-route',
                        geometry: LineString.from(
                          replayData.frames
                              .map(_toGeographic)
                              .toList(growable: false),
                        ),
                      ),
                    ],
                    color: const Color(0x334A6A7B),
                    width: 3,
                  ),
              ],
              children: [
                if (sitePoint != null)
                  WidgetLayer(
                    markers: [
                      Marker(
                        point: sitePoint,
                        size: const Size(30, 30),
                        child: _SiteBadge(label: widget.siteLabel),
                      ),
                    ],
                  ),
                IgnorePointer(
                  child: _FlightReplayAltitudeOverlay(
                    replayData: replayData,
                    currentIndex: widget.currentIndex,
                  ),
                ),
              ],
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.08),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.14),
                    ],
                    stops: const [0.0, 0.38, 1.0],
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

  Geographic _toGeographic(FlightReplayFrame frame) {
    return Geographic(
      lon: frame.longitude,
      lat: frame.latitude,
      elev: frame.displayAltitudeMeters,
    );
  }

  int get _safeCurrentIndex {
    if (!widget.replayData.hasFrames) {
      return 0;
    }
    return min(
      max(0, widget.currentIndex),
      widget.replayData.frames.length - 1,
    );
  }

  double _overallBearing(FlightReplayData replayData) {
    if (replayData.frames.length < 2) {
      return 0;
    }
    return replayData.endFrame?.heading ?? replayData.frames.last.heading;
  }

  String _styleDocument(ParaglidingMapViewType type) {
    final baseSource = type == ParaglidingMapViewType.standard
        ? {
            'id': 'standard-raster',
            'tiles': ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
            'attribution': 'OpenStreetMap contributors',
          }
        : {
            'id': 'satellite-raster',
            'tiles': [
              'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
            ],
            'attribution': 'Esri, Maxar, Earthstar Geographics',
          };

    return jsonEncode({
      'version': 8,
      'name': type == ParaglidingMapViewType.standard
          ? 'Paragliding Analysis Standard'
          : 'Paragliding Analysis Satellite',
      'sources': {
        'base-raster': {
          'type': 'raster',
          'tiles': baseSource['tiles'],
          'tileSize': 256,
          'attribution': baseSource['attribution'],
        },
        'terrain-dem': {
          'type': 'raster-dem',
          'tiles': [
            'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png',
          ],
          'tileSize': 256,
          'maxzoom': 15,
          'encoding': 'terrarium',
          'attribution': 'Mapzen terrain tiles via AWS',
        },
      },
      'terrain': {
        'source': 'terrain-dem',
        'exaggeration': 1.18,
      },
      'layers': [
        {
          'id': 'background',
          'type': 'background',
          'paint': {
            'background-color': '#0C1520',
          },
        },
        {
          'id': baseSource['id'],
          'type': 'raster',
          'source': 'base-raster',
          'paint': {
            'raster-saturation':
                type == ParaglidingMapViewType.standard ? -0.10 : 0,
            'raster-contrast':
                type == ParaglidingMapViewType.standard ? 0.08 : 0.10,
            'raster-brightness-max':
                type == ParaglidingMapViewType.standard ? 0.94 : 0.88,
          },
        },
        {
          'id': 'terrain-hillshade',
          'type': 'hillshade',
          'source': 'terrain-dem',
          'paint': {
            'hillshade-shadow-color': '#0B1620',
            'hillshade-highlight-color': '#E8F1F7',
            'hillshade-accent-color': '#6FA7C4',
            'hillshade-exaggeration':
                type == ParaglidingMapViewType.standard ? 0.35 : 0.28,
          },
        },
      ],
    });
  }
}

class _FlightReplayAltitudeOverlay extends StatelessWidget {
  const _FlightReplayAltitudeOverlay({
    required this.replayData,
    required this.currentIndex,
  });

  final FlightReplayData replayData;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final controller = MapController.maybeOf(context);
    final camera = MapCamera.maybeOf(context);
    if (controller == null || camera == null || replayData.frames.length < 2) {
      return const SizedBox.shrink();
    }

    final groundPoints = controller.toScreenLocations(
      replayData.frames
          .map(
            (frame) => Geographic(lon: frame.longitude, lat: frame.latitude),
          )
          .toList(growable: false),
    );

    return SizedBox.expand(
      child: CustomPaint(
        painter: _FlightReplayAltitudePainter(
          replayData: replayData,
          groundPoints: groundPoints,
          currentIndex: currentIndex,
          pitch: camera.pitch,
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
  });

  final FlightReplayData replayData;
  final List<Offset> groundPoints;
  final int currentIndex;
  final double pitch;

  @override
  void paint(Canvas canvas, Size size) {
    if (groundPoints.length < 2 || replayData.frames.length < 2) {
      return;
    }

    final altitudeRange = max(
      1.0,
      replayData.maxAltitudeMeters - replayData.minAltitudeMeters,
    );
    final liftScale = min(size.height * 0.26, 118.0) * (0.42 + (pitch / 75.0));
    final elevatedPoints = <Offset>[];

    for (var index = 0; index < groundPoints.length; index++) {
      final frame = replayData.frames[index];
      final normalized =
          (frame.displayAltitudeMeters - replayData.minAltitudeMeters) /
              altitudeRange;
      final lift = 8 + (normalized * liftScale);
      elevatedPoints
          .add(Offset(groundPoints[index].dx, groundPoints[index].dy - lift));
    }

    final currentSafeIndex = min(
      max(0, currentIndex),
      elevatedPoints.length - 1,
    );
    final currentPoint = elevatedPoints[currentSafeIndex];
    final highestPoint = elevatedPoints[replayData.highestFrameIndex];
    final startPoint = elevatedPoints.first;
    final endPoint = elevatedPoints.last;

    final groundPath = Path()
      ..moveTo(groundPoints.first.dx, groundPoints.first.dy);
    for (var index = 1; index < groundPoints.length; index++) {
      groundPath.lineTo(groundPoints[index].dx, groundPoints[index].dy);
    }
    canvas.drawPath(
      groundPath,
      Paint()
        ..color = const Color(0x22000000)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

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
    if ((replayData.takeoffFrameIndex - 0).abs() > 1) {
      _drawMarker(canvas, takeoffPoint, const Color(0xFFA8E063), 5);
    }
    if ((replayData.landingFrameIndex - (elevatedPoints.length - 1)).abs() >
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
    if ((replayData.takeoffFrameIndex - 0).abs() > 1) {
      _drawLabel(
        canvas,
        position: takeoffPoint.translate(0, -18),
        text: '이륙 추정',
        background: const Color(0xFF36521C),
      );
    }
    if ((replayData.landingFrameIndex - (elevatedPoints.length - 1)).abs() >
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
      text: '최고',
      background: const Color(0xFF1E2D38),
    );
  }

  void _drawStem(Canvas canvas, Offset from, Offset to, Color color) {
    canvas.drawLine(
      from,
      to,
      Paint()
        ..color = color
        ..strokeWidth = 1.6,
    );
  }

  void _drawRemainingRoute(Canvas canvas, List<Offset> elevatedPoints) {
    for (var index = 1; index < elevatedPoints.length; index++) {
      final altitudeAverage =
          (replayData.frames[index - 1].displayAltitudeMeters +
                  replayData.frames[index].displayAltitudeMeters) /
              2;
      final normalizedAltitude = (altitudeAverage -
              replayData.minAltitudeMeters) /
          max(1.0, replayData.maxAltitudeMeters - replayData.minAltitudeMeters);
      canvas.drawLine(
        elevatedPoints[index - 1],
        elevatedPoints[index],
        Paint()
          ..color = _altitudeColor(normalizedAltitude).withValues(alpha: 0.72)
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _drawThermalSegments(Canvas canvas, List<Offset> elevatedPoints) {
    for (final segment in replayData.thermalSegments) {
      for (var index = max(1, segment.startIndex + 1);
          index <= min(segment.endIndex, elevatedPoints.length - 1);
          index++) {
        canvas.drawLine(
          elevatedPoints[index - 1],
          elevatedPoints[index],
          Paint()
            ..color = const Color(0xCCFFD166)
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  void _drawCompletedRoute(
    Canvas canvas, {
    required List<Offset> elevatedPoints,
    required int currentSafeIndex,
  }) {
    for (var index = 1; index <= currentSafeIndex; index++) {
      canvas.drawLine(
        elevatedPoints[index - 1],
        elevatedPoints[index],
        Paint()
          ..color = const Color(0x884CC9F0)
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawLine(
        elevatedPoints[index - 1],
        elevatedPoints[index],
        Paint()
          ..color = Colors.white.withValues(alpha: 0.86)
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
    canvas.drawPath(
      path.shift(const Offset(0, 0)),
      Paint()..color = color,
    );
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
    )..layout();

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
        oldDelegate.groundPoints != groundPoints;
  }
}

class _SiteBadge extends StatelessWidget {
  const _SiteBadge({
    this.label,
  });

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label ?? '등록 비행장',
      child: Center(
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
          child: Icon(
            Icons.place_rounded,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
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
