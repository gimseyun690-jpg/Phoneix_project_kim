import 'package:flutter/material.dart';

import '../models/app_models.dart';

class FlightPathPreview extends StatelessWidget {
  const FlightPathPreview({
    super.key,
    required this.points,
  });

  final List<FlightTrackPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F7F8),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: const Text('경로 데이터가 아직 충분하지 않습니다.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 220,
          width: double.infinity,
          child: CustomPaint(
            painter: _FlightPathPainter(
              points: points,
              lineColor: Theme.of(context).colorScheme.primary,
              startColor: const Color(0xFF2A9D8F),
              endColor: const Color(0xFFE76F51),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          children: [
            _LegendDot(color: Color(0xFF2A9D8F), label: '출발'),
            SizedBox(width: 16),
            _LegendDot(color: Color(0xFFE76F51), label: '종료'),
          ],
        ),
      ],
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

class _FlightPathPainter extends CustomPainter {
  const _FlightPathPainter({
    required this.points,
    required this.lineColor,
    required this.startColor,
    required this.endColor,
  });

  final List<FlightTrackPoint> points;
  final Color lineColor;
  final Color startColor;
  final Color endColor;

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 16.0;
    final bounds = Rect.fromLTWH(
      padding,
      padding,
      size.width - (padding * 2),
      size.height - (padding * 2),
    );

    final background = Paint()
      ..color = const Color(0xFFF4F7F8)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(16),
      ),
      background,
    );

    final gridPaint = Paint()
      ..color = const Color(0xFFDCE4E6)
      ..strokeWidth = 1;
    for (var index = 1; index < 4; index += 1) {
      final dx = bounds.left + (bounds.width * index / 4);
      final dy = bounds.top + (bounds.height * index / 4);
      canvas.drawLine(
          Offset(dx, bounds.top), Offset(dx, bounds.bottom), gridPaint);
      canvas.drawLine(
          Offset(bounds.left, dy), Offset(bounds.right, dy), gridPaint);
    }

    final minLat =
        points.map((item) => item.latitude).reduce((a, b) => a < b ? a : b);
    final maxLat =
        points.map((item) => item.latitude).reduce((a, b) => a > b ? a : b);
    final minLng =
        points.map((item) => item.longitude).reduce((a, b) => a < b ? a : b);
    final maxLng =
        points.map((item) => item.longitude).reduce((a, b) => a > b ? a : b);

    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;

    Offset toOffset(FlightTrackPoint point) {
      final normalizedX =
          lngRange == 0 ? 0.5 : (point.longitude - minLng) / lngRange;
      final normalizedY =
          latRange == 0 ? 0.5 : (point.latitude - minLat) / latRange;
      return Offset(
        bounds.left + (bounds.width * normalizedX),
        bounds.bottom - (bounds.height * normalizedY),
      );
    }

    final path = Path();
    final offsets = points.map(toOffset).toList();
    path.moveTo(offsets.first.dx, offsets.first.dy);
    for (final offset in offsets.skip(1)) {
      path.lineTo(offset.dx, offset.dy);
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);

    final startPaint = Paint()..color = startColor;
    final endPaint = Paint()..color = endColor;
    canvas.drawCircle(offsets.first, 6, startPaint);
    canvas.drawCircle(offsets.last, 6, endPaint);
  }

  @override
  bool shouldRepaint(covariant _FlightPathPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.startColor != startColor ||
        oldDelegate.endColor != endColor;
  }
}
