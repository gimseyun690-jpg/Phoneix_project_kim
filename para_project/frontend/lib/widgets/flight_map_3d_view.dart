import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre/maplibre.dart';

import '../core/map_view_type.dart';
import '../models/app_models.dart';
import 'animated_heading_icon.dart';
import 'flight_map_view.dart';

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
    this.onFollowDisabled,
  });

  final List<FlightTrackPoint> points;
  final double height;
  final bool followLocation;
  final ParaglidingMapViewType mapViewType;
  final double borderRadius;
  final double? siteLatitude;
  final double? siteLongitude;
  final String? siteLabel;
  final VoidCallback? onFollowDisabled;

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
  double? _lastAnimatedBearing;

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
    final targetBearing = _resolveAnimatedBearing(
      point: point,
      previousPoint: previousPoint,
      fallbackBearing: camera.bearing,
    );

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
      _lastAnimatedBearing = targetBearing;
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

    if (kIsWeb) {
      return FlightMapView(
        points: widget.points,
        height: widget.height,
        borderRadius: widget.borderRadius,
        currentHeadingDegrees: currentPoint?.heading,
        mapViewType: widget.mapViewType,
        siteLatitude: widget.siteLatitude,
        siteLongitude: widget.siteLongitude,
        siteLabel: widget.siteLabel,
        showSiteLabel: false,
      );
    }

    final initialCenter =
        currentPoint != null ? _toGeographicPoint(currentPoint) : sitePoint;
    final effectiveCenter =
        initialCenter ?? const Geographic(lon: 127.7669, lat: 35.9078);
    final initialBearing = _normalizeBearing(
      _lastAnimatedBearing ?? currentPoint?.heading ?? 0,
    );

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
                _lastAnimatedBearing = initialBearing;
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
                          heading: _lastAnimatedBearing ?? currentPoint.heading,
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

  double _resolveAnimatedBearing({
    required FlightTrackPoint point,
    required FlightTrackPoint? previousPoint,
    required double fallbackBearing,
  }) {
    final currentBearing =
        _normalizeBearing(_lastAnimatedBearing ?? fallbackBearing);
    final accuracy = point.accuracy ?? previousPoint?.accuracy ?? 12;
    final speed = (point.speed ?? 0).clamp(0, 35).toDouble();

    double? movedMeters;
    double? derivedBearing;
    if (previousPoint != null) {
      movedMeters = _distance.as(
        ll.LengthUnit.Meter,
        ll.LatLng(previousPoint.latitude, previousPoint.longitude),
        ll.LatLng(point.latitude, point.longitude),
      );
      if (movedMeters >= max(4.5, accuracy * 0.35)) {
        derivedBearing = _bearingBetween(previousPoint, point);
      }
    }

    if ((movedMeters ?? 0) < max(4.5, accuracy * 0.35) && speed < 3.0) {
      return currentBearing;
    }

    final candidate = _resolveBearingCandidate(
      sensorBearing: point.heading,
      derivedBearing: derivedBearing,
      accuracyMeters: accuracy,
      speedMps: speed,
    );
    if (candidate == null) {
      return currentBearing;
    }

    final delta = _bearingDelta(currentBearing, candidate);
    final absoluteDelta = delta.abs();
    if (absoluteDelta < 2.5) {
      return currentBearing;
    }
    if (absoluteDelta > 90 && speed < 5.5) {
      return currentBearing;
    }

    double smoothing = switch (speed) {
      >= 12 => 0.62,
      >= 8 => 0.48,
      >= 4.5 => 0.36,
      _ => 0.26,
    };
    if (accuracy > 18) {
      smoothing -= 0.08;
    }
    if (absoluteDelta > 70 && speed < 7) {
      smoothing = min(smoothing, 0.24);
    }

    return _normalizeBearing(
      currentBearing + (delta * smoothing.clamp(0.18, 0.62)),
    );
  }

  double? _resolveBearingCandidate({
    required double? sensorBearing,
    required double? derivedBearing,
    required double accuracyMeters,
    required double speedMps,
  }) {
    final normalizedSensor =
        sensorBearing == null ? null : _normalizeBearing(sensorBearing);
    final normalizedDerived =
        derivedBearing == null ? null : _normalizeBearing(derivedBearing);

    if (normalizedSensor != null && normalizedDerived != null) {
      final gap = _bearingDelta(normalizedDerived, normalizedSensor).abs();
      if (gap <= 16) {
        return _normalizeBearing(
          normalizedDerived +
              (_bearingDelta(normalizedDerived, normalizedSensor) * 0.45),
        );
      }
      if (gap <= 42 && speedMps >= 8 && accuracyMeters <= 18) {
        return _normalizeBearing(
          normalizedDerived +
              (_bearingDelta(normalizedDerived, normalizedSensor) * 0.28),
        );
      }
      return normalizedDerived;
    }

    return normalizedDerived ?? normalizedSensor;
  }

  double _bearingBetween(FlightTrackPoint from, FlightTrackPoint to) {
    final dx = to.longitude - from.longitude;
    final dy = to.latitude - from.latitude;
    final radians = atan2(dx, dy);
    final degrees = radians * 180 / pi;
    return _normalizeBearing(degrees);
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
            child: AnimatedHeadingIcon(
              headingDegrees: heading,
              icon: Icons.navigation_rounded,
              iconColor: Colors.white,
              iconSize: 18,
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
