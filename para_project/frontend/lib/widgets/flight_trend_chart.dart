import 'dart:math';

import 'package:flutter/material.dart';

import '../core/flight_analysis_summary.dart';
import '../core/utils.dart';

class FlightTrendChart extends StatelessWidget {
  const FlightTrendChart({
    super.key,
    required this.title,
    required this.samples,
    required this.color,
    required this.unitLabel,
    required this.valueBuilder,
    required this.labelBuilder,
  });

  final String title;
  final List<FlightAnalysisSample> samples;
  final Color color;
  final String unitLabel;
  final double Function(FlightAnalysisSample sample) valueBuilder;
  final String Function(double value) labelBuilder;

  @override
  Widget build(BuildContext context) {
    final values = samples.map(valueBuilder).toList(growable: false);
    final hasEnoughData = values.length >= 2;
    final minValue = values.isEmpty ? 0.0 : values.reduce(min);
    final maxValue = values.isEmpty ? 0.0 : values.reduce(max);
    final startTime = samples.isEmpty ? null : samples.first.time;
    final endTime = samples.isEmpty ? null : samples.last.time;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Text(
                unitLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!hasEnoughData)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('차트를 그릴 기록 포인트가 아직 충분하지 않습니다.'),
              ),
            )
          else
            SizedBox(
              height: 170,
              child: CustomPaint(
                painter: _FlightTrendChartPainter(
                  values: values,
                  color: color,
                  minValue: minValue,
                  maxValue: maxValue,
                ),
                child: Container(),
              ),
            ),
          if (hasEnoughData) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _ChartMeta(
                  label: '최저',
                  value: labelBuilder(minValue),
                ),
                const SizedBox(width: 10),
                _ChartMeta(
                  label: '최고',
                  value: labelBuilder(maxValue),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    startTime == null ? '-' : formatTime(startTime),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      samples.length < 3
                          ? '-'
                          : formatTime(samples[samples.length ~/ 2].time),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    endTime == null ? '-' : formatTime(endTime),
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartMeta extends StatelessWidget {
  const _ChartMeta({
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
        color: const Color(0xFFF4F7F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$label  $value',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _FlightTrendChartPainter extends CustomPainter {
  const _FlightTrendChartPainter({
    required this.values,
    required this.color,
    required this.minValue,
    required this.maxValue,
  });

  final List<double> values;
  final Color color;
  final double minValue;
  final double maxValue;

  @override
  void paint(Canvas canvas, Size size) {
    const topPadding = 10.0;
    const bottomPadding = 14.0;
    final chartHeight = size.height - topPadding - bottomPadding;
    final chartWidth = size.width;
    final range = max(1.0, maxValue - minValue);

    final gridPaint = Paint()
      ..color = const Color(0x14000000)
      ..strokeWidth = 1;
    for (var index = 0; index < 4; index++) {
      final dy = topPadding + (chartHeight / 3) * index;
      canvas.drawLine(
        Offset(0, dy),
        Offset(chartWidth, dy),
        gridPaint,
      );
    }

    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final x =
          values.length == 1 ? 0.0 : chartWidth * index / (values.length - 1);
      final normalized = (values[index] - minValue) / range;
      final y = topPadding + chartHeight - (normalized * chartHeight);
      points.add(Offset(x, y));
    }

    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final point in points) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath
      ..lineTo(points.last.dx, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.30),
          color.withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      linePath.lineTo(points[index].dx, points[index].dy);
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    final dotPaint = Paint()..color = color;
    canvas.drawCircle(points.first, 4.5, dotPaint);
    canvas.drawCircle(points.last, 4.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _FlightTrendChartPainter oldDelegate) {
    if (oldDelegate.values.length != values.length ||
        oldDelegate.minValue != minValue ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.color != color) {
      return true;
    }

    for (var index = 0; index < values.length; index++) {
      if (oldDelegate.values[index] != values[index]) {
        return true;
      }
    }
    return false;
  }
}
