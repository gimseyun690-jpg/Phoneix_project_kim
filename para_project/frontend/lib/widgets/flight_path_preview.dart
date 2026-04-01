import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'flight_map_view.dart';

class FlightPathPreview extends StatelessWidget {
  const FlightPathPreview({
    super.key,
    required this.points,
  });

  final List<FlightTrackPoint> points;

  @override
  Widget build(BuildContext context) {
    return FlightMapView(
      points: points,
      height: 220,
      emptyMessage: '경로 데이터가 아직 충분하지 않습니다.',
      showLegend: true,
      showCurrentMarker: false,
    );
  }
}
