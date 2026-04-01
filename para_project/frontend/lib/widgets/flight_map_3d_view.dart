import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre/maplibre.dart';

import '../core/map_view_type.dart';
import '../models/app_models.dart';

class FlightMap3DView extends StatefulWidget {
  const FlightMap3DView({
    super.key,
    required this.points,
    required this.height,
    required this.followLocation,
    required this.mapViewType,
    this.borderRadius = 18,
    this.siteLatitude,
    this.siteLongitude,
    this.siteLabel,
  });

  final List<FlightTrackPoint> points;
  final double height;
  final bool followLocation;
  final ParaglidingMapViewType mapViewType;
  final double borderRadius;
  final double? siteLatitude;
  final double? siteLongitude;
  final String? siteLabel;

  @override
  State<FlightMap3DView> createState() => FlightMap3DViewState();
}

class FlightMap3DViewState extends State<FlightMap3DView> {
  static const double _defaultZoom = 15.8;
  static const double _followPitch = 54;
  static const double _minFollowZoom = 15.4;

  final ll.Distance _distance = const ll.Distance();
  MapController? _controller;
  FlightTrackPoint? _lastAnimatedPoint;

  @override
  void didUpdateWidget(covariant FlightMap3DView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final controller = _controller;
    if (controller != null && widget.mapViewType != oldWidget.mapViewType) {
      controller.setStyle(_styleDocument(widget.mapViewType));
    }

    final currentPoint = widget.points.isEmpty ? null : widget.points.last;
    if (controller == null || currentPoint == null || !widget.followLocation) {
      return;
    }

    final shouldForce = !oldWidget.followLocation ||
        widget.points.length != oldWidget.points.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      recenter(force: shouldForce);
    });
  }

  void recenter({bool force = true}) {
    final point = widget.points.isEmpty ? null : widget.points.last;
    if (point == null) {
      return;
    }
    _animateToPoint(point, force: force);
  }

  Future<void> _animateToPoint(
    FlightTrackPoint point, {
    bool force = false,
  }) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    final previousPoint = _lastAnimatedPoint;
    if (!force && previousPoint != null) {
      final movedMeters = _distance.as(
        ll.LengthUnit.Meter,
        ll.LatLng(previousPoint.latitude, previousPoint.longitude),
        ll.LatLng(point.latitude, point.longitude),
      );
      final headingDelta = _bearingDelta(previousPoint.heading, point.heading);
      if (movedMeters < 8 && headingDelta < 6) {
        return;
      }
    }

    final camera = controller.camera ?? controller.getCamera();
    final targetBearing = _normalizeBearing(point.heading ?? camera.bearing);

    try {
      await controller.animateCamera(
        center: _toGeographicPoint(point),
        zoom: camera.zoom < _minFollowZoom ? _defaultZoom : camera.zoom,
        bearing: targetBearing,
        pitch: _followPitch,
        nativeDuration: const Duration(milliseconds: 550),
        webSpeed: 2.2,
        webMaxDuration: const Duration(milliseconds: 550),
      );
      _lastAnimatedPoint = point;
    } catch (_) {
      // 지도가 아직 완전히 준비되지 않았으면 다음 위치 갱신에서 다시 시도합니다.
    }
  }

  @override
  Widget build(BuildContext context) {
    final sitePoint = _toStaticPoint(widget.siteLatitude, widget.siteLongitude);
    final currentPoint = widget.points.isEmpty ? null : widget.points.last;
    final routePoints =
        widget.points.map(_toGeographicPoint).toList(growable: false);
    final initialCenter =
        currentPoint != null ? _toGeographicPoint(currentPoint) : sitePoint;
    final effectiveCenter =
        initialCenter ?? const Geographic(lon: 127.7669, lat: 35.9078);
    final initialBearing = _normalizeBearing(currentPoint?.heading ?? 0);

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MapLibreMap(
              onMapCreated: (controller) {
                _controller = controller;
                if (widget.followLocation && currentPoint != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    recenter(force: true);
                  });
                }
              },
              options: MapOptions(
                initStyle: _styleDocument(widget.mapViewType),
                initCenter: effectiveCenter,
                initZoom: currentPoint == null ? 13.8 : _defaultZoom,
                initBearing: initialBearing,
                initPitch: currentPoint == null ? 36 : _followPitch,
                minPitch: 0,
                maxPitch: 60,
                maxZoom: 18.5,
              ),
              layers: [
                if (routePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Feature<LineString>(
                        id: 'flight-route-shadow',
                        geometry: LineString.from(routePoints),
                      ),
                    ],
                    color: const Color(0x66264653),
                    width: 7,
                  ),
                if (routePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Feature<LineString>(
                        id: 'flight-route',
                        geometry: LineString.from(routePoints),
                      ),
                    ],
                    color: Theme.of(context).colorScheme.primary,
                    width: 4,
                  ),
              ],
              children: [
                WidgetLayer(
                  markers: [
                    if (sitePoint != null)
                      Marker(
                        point: sitePoint,
                        size: const Size(34, 34),
                        child: _SitePointBadge(label: widget.siteLabel),
                      ),
                    if (currentPoint != null)
                      Marker(
                        point: _toGeographicPoint(currentPoint),
                        size: const Size(60, 60),
                        rotate: true,
                        child: _CurrentPointBadge(
                          heading: currentPoint.heading,
                        ),
                      ),
                  ],
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
                      Colors.black.withValues(alpha: 0.10),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.12),
                    ],
                    stops: const [0, 0.45, 1],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Geographic _toGeographicPoint(FlightTrackPoint point) {
    return Geographic(
      lon: point.longitude,
      lat: point.latitude,
      elev: point.altitude,
    );
  }

  Geographic? _toStaticPoint(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) {
      return null;
    }
    return Geographic(lon: longitude, lat: latitude);
  }

  double _normalizeBearing(double value) {
    return ((value % 360) + 360) % 360;
  }

  double _bearingDelta(double? previous, double? current) {
    if (previous == null || current == null) {
      return 180;
    }
    final delta =
        (_normalizeBearing(current) - _normalizeBearing(previous)).abs();
    return delta > 180 ? 360 - delta : delta;
  }

  String _styleDocument(ParaglidingMapViewType type) {
    if (type == ParaglidingMapViewType.standard) {
      return 'https://demotiles.maplibre.org/style.json';
    }

    return jsonEncode({
      'version': 8,
      'name': 'Paragliding Satellite',
      'sources': {
        'satellite': {
          'type': 'raster',
          'tiles': [
            'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          ],
          'tileSize': 256,
          'attribution': 'Esri, Maxar, Earthstar Geographics',
        },
      },
      'layers': [
        {
          'id': 'background',
          'type': 'background',
          'paint': {
            'background-color': '#0D1620',
          },
        },
        {
          'id': 'satellite-raster',
          'type': 'raster',
          'source': 'satellite',
        },
      ],
    });
  }
}

class _CurrentPointBadge extends StatelessWidget {
  const _CurrentPointBadge({
    required this.heading,
  });

  final double? heading;

  @override
  Widget build(BuildContext context) {
    final angle = ((heading ?? 0) % 360) * degree2Radian;
    return Center(
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0x33264653),
          border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
        ),
        child: Center(
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Transform.rotate(
              angle: angle,
              child: const Icon(
                Icons.navigation_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SitePointBadge extends StatelessWidget {
  const _SitePointBadge({
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
            color: Colors.white.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
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
