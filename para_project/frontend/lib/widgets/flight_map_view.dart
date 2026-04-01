import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/map_view_type.dart';
import '../models/app_models.dart';

class FlightMapView extends StatelessWidget {
  const FlightMapView({
    super.key,
    required this.points,
    this.height = 260,
    this.borderRadius = 18,
    this.emptyMessage = '지도 데이터를 준비하고 있습니다.',
    this.mapController,
    this.showLegend = false,
    this.showCurrentMarker = true,
    this.currentHeadingDegrees,
    this.siteLatitude,
    this.siteLongitude,
    this.siteLabel,
    this.showSiteLabel = true,
    this.mapViewType = ParaglidingMapViewType.satellite,
    this.highlightLatitude,
    this.highlightLongitude,
    this.highlightLabel,
    this.onPositionChanged,
  });

  final List<FlightTrackPoint> points;
  final double height;
  final double borderRadius;
  final String emptyMessage;
  final MapController? mapController;
  final bool showLegend;
  final bool showCurrentMarker;
  final double? currentHeadingDegrees;
  final double? siteLatitude;
  final double? siteLongitude;
  final String? siteLabel;
  final bool showSiteLabel;
  final ParaglidingMapViewType mapViewType;
  final double? highlightLatitude;
  final double? highlightLongitude;
  final String? highlightLabel;
  final void Function(MapCamera camera, bool hasGesture)? onPositionChanged;

  @override
  Widget build(BuildContext context) {
    final routePoints = points
        .map((item) => LatLng(item.latitude, item.longitude))
        .toList(growable: false);
    final sitePoint = siteLatitude == null || siteLongitude == null
        ? null
        : LatLng(siteLatitude!, siteLongitude!);
    final highlightPoint =
        highlightLatitude == null || highlightLongitude == null
            ? null
            : LatLng(highlightLatitude!, highlightLongitude!);

    if (routePoints.isEmpty && sitePoint == null && highlightPoint == null) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F7F8),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        alignment: Alignment.center,
        child: Text(emptyMessage),
      );
    }

    final allPoints = [
      ...routePoints,
      if (sitePoint != null) sitePoint,
      if (highlightPoint != null) highlightPoint,
    ];
    final center = _estimateCenter(allPoints);
    final zoom = _estimateZoom(allPoints);
    final lastPoint = routePoints.isEmpty ? null : routePoints.last;
    final firstPoint = routePoints.isEmpty ? null : routePoints.first;
    final markers = <Marker>[
      if (sitePoint != null && !_containsPoint(routePoints, sitePoint))
        Marker(
          width: showSiteLabel ? 110 : 36,
          height: showSiteLabel ? 54 : 36,
          point: sitePoint,
          child: _SiteMarker(label: siteLabel ?? '기준 비행장'),
        ),
      if (highlightPoint != null)
        Marker(
          width: 126,
          height: 70,
          point: highlightPoint,
          child: _HighlightMarker(label: highlightLabel ?? '선택 구간'),
        ),
      if (showLegend && firstPoint != null)
        Marker(
          width: 44,
          height: 44,
          point: firstPoint,
          child: const _CircleMarker(
            color: Color(0xFF2A9D8F),
            icon: Icons.flight_takeoff_rounded,
          ),
        ),
      if (showLegend &&
          lastPoint != null &&
          !_isSamePoint(firstPoint, lastPoint))
        Marker(
          width: 44,
          height: 44,
          point: lastPoint,
          child: const _CircleMarker(
            color: Color(0xFFE76F51),
            icon: Icons.flag_rounded,
          ),
        ),
      if (showCurrentMarker && lastPoint != null)
        Marker(
          width: 54,
          height: 54,
          point: lastPoint,
          child: _CurrentPositionMarker(heading: currentHeadingDegrees),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: zoom,
                onPositionChanged: onPositionChanged,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                buildParaglidingTileLayer(mapViewType),
                if (routePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: routePoints,
                        strokeWidth: 4,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                if (markers.isNotEmpty) MarkerLayer(markers: markers),
                RichAttributionWidget(
                  attributions: [
                    buildParaglidingAttribution(mapViewType),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (showLegend) ...[
          const SizedBox(height: 10),
          const Row(
            children: [
              _LegendDot(color: Color(0xFF2A9D8F), label: '출발'),
              SizedBox(width: 16),
              _LegendDot(color: Color(0xFFE76F51), label: '종료'),
            ],
          ),
        ],
      ],
    );
  }

  LatLng _estimateCenter(List<LatLng> points) {
    final lat = points.map((item) => item.latitude).reduce((a, b) => a + b) /
        points.length;
    final lng = points.map((item) => item.longitude).reduce((a, b) => a + b) /
        points.length;
    return LatLng(lat, lng);
  }

  double _estimateZoom(List<LatLng> points) {
    if (points.length < 2) {
      return 14.5;
    }

    final minLat =
        points.map((item) => item.latitude).reduce((a, b) => min(a, b));
    final maxLat =
        points.map((item) => item.latitude).reduce((a, b) => max(a, b));
    final minLng =
        points.map((item) => item.longitude).reduce((a, b) => min(a, b));
    final maxLng =
        points.map((item) => item.longitude).reduce((a, b) => max(a, b));

    final spread = max(maxLat - minLat, maxLng - minLng);
    if (spread < 0.01) {
      return 15;
    }
    if (spread < 0.03) {
      return 13.5;
    }
    if (spread < 0.08) {
      return 12.5;
    }
    if (spread < 0.2) {
      return 11;
    }
    return 9.5;
  }

  bool _containsPoint(List<LatLng> points, LatLng target) {
    for (final point in points) {
      if (_isSamePoint(point, target)) {
        return true;
      }
    }
    return false;
  }

  bool _isSamePoint(LatLng? a, LatLng? b) {
    if (a == null || b == null) {
      return false;
    }
    return (a.latitude - b.latitude).abs() < 0.0002 &&
        (a.longitude - b.longitude).abs() < 0.0002;
  }
}

class _CurrentPositionMarker extends StatelessWidget {
  const _CurrentPositionMarker({
    required this.heading,
  });

  final double? heading;

  @override
  Widget build(BuildContext context) {
    final angle = ((heading ?? 0) % 360) * degree2Radian;
    return Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0x33264653),
      ),
      padding: const EdgeInsets.all(6),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.primary,
          border: Border.all(color: Colors.white, width: 2),
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
    );
  }
}

class _CircleMarker extends StatelessWidget {
  const _CircleMarker({
    required this.color,
    required this.icon,
  });

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _SiteMarker extends StatelessWidget {
  const _SiteMarker({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.place_rounded, size: 14, color: Color(0xFFE9C46A)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightMarker extends StatelessWidget {
  const _HighlightMarker({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF264653),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x29000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insights_rounded, size: 15, color: Colors.white),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}
