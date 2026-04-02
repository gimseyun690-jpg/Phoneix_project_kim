import 'dart:math';

import 'package:geolocator/geolocator.dart';

import '../models/app_models.dart';

enum FlightPhase {
  standby,
  takeoffDetected,
  cruising,
  landingLikely,
}

extension FlightPhaseLabel on FlightPhase {
  String get label => switch (this) {
        FlightPhase.standby => '준비 중',
        FlightPhase.takeoffDetected => '이륙 감지',
        FlightPhase.cruising => '비행 중',
        FlightPhase.landingLikely => '착륙 추정',
      };
}

class FlightLiveMetrics {
  const FlightLiveMetrics({
    required this.startedAt,
    required this.currentTime,
    required this.elapsed,
    required this.currentAltitudeMeters,
    required this.currentSpeedMps,
    required this.totalDistanceMeters,
    required this.verticalSpeedMps,
    required this.headingDegrees,
    required this.accuracyMeters,
    required this.phase,
    required this.locationStatusLabel,
    required this.hasTakeoffSignal,
  });

  final DateTime startedAt;
  final DateTime currentTime;
  final Duration elapsed;
  final double currentAltitudeMeters;
  final double currentSpeedMps;
  final double totalDistanceMeters;
  final double verticalSpeedMps;
  final double? headingDegrees;
  final double? accuracyMeters;
  final FlightPhase phase;
  final String locationStatusLabel;
  final bool hasTakeoffSignal;

  factory FlightLiveMetrics.fromSession({
    required FlightSession session,
    required List<FlightTrackPoint> points,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    final lastPoint = points.isEmpty ? null : points.last;
    final firstPoint = points.isEmpty ? null : points.first;
    final elapsed = session.isRecording
        ? Duration(
            seconds: max(
              0,
              currentTime.difference(session.startedAt).inSeconds -
                  session.pausedDurationSeconds,
            ),
          )
        : session.duration;

    final currentAltitude =
        lastPoint?.altitude ?? max(session.maxAltitudeMeters, 0);
    final accuracy = lastPoint?.accuracy;
    final heading = _resolveHeading(points);
    final currentSpeed = _resolveCurrentSpeed(points);
    final verticalSpeed = _resolveVerticalSpeed(points);
    final hasTakeoffSignal = _resolveTakeoffSignal(
      firstPoint: firstPoint,
      lastPoint: lastPoint,
      currentSpeedMps: currentSpeed,
      elapsed: elapsed,
    );

    return FlightLiveMetrics(
      startedAt: session.startedAt,
      currentTime: currentTime,
      elapsed: elapsed,
      currentAltitudeMeters: currentAltitude,
      currentSpeedMps: currentSpeed,
      totalDistanceMeters: session.totalDistanceMeters,
      verticalSpeedMps: verticalSpeed,
      headingDegrees: heading,
      accuracyMeters: accuracy,
      phase: _resolvePhase(
        elapsed: elapsed,
        currentSpeedMps: currentSpeed,
        verticalSpeedMps: verticalSpeed,
        hasTakeoffSignal: hasTakeoffSignal,
      ),
      locationStatusLabel: _resolveLocationStatus(accuracy),
      hasTakeoffSignal: hasTakeoffSignal,
    );
  }

  static double _resolveCurrentSpeed(List<FlightTrackPoint> points) {
    if (points.isEmpty) {
      return 0;
    }
    final lastPoint = points.last;
    final lastSpeed = lastPoint.speed;
    if (lastSpeed != null && lastSpeed > 0 && lastSpeed.isFinite) {
      return lastSpeed;
    }
    if (points.length < 2) {
      return 0;
    }

    final previousPoint = points[points.length - 2];
    final seconds = max(
        1, lastPoint.timestamp.difference(previousPoint.timestamp).inSeconds);
    final distance = Geolocator.distanceBetween(
      previousPoint.latitude,
      previousPoint.longitude,
      lastPoint.latitude,
      lastPoint.longitude,
    );
    return max(0, distance / seconds);
  }

  static double _resolveVerticalSpeed(List<FlightTrackPoint> points) {
    if (points.length < 2) {
      return 0;
    }

    final lastPoint = points.last;
    final windowPoints = points.reversed
        .takeWhile((item) =>
            lastPoint.timestamp.difference(item.timestamp).inSeconds <= 45)
        .toList()
        .reversed
        .toList();

    if (windowPoints.length < 2) {
      final previousPoint = points[points.length - 2];
      final seconds = max(
          1, lastPoint.timestamp.difference(previousPoint.timestamp).inSeconds);
      return (lastPoint.altitude - previousPoint.altitude) / seconds;
    }

    final firstPoint = windowPoints.first;
    final seconds =
        max(1, lastPoint.timestamp.difference(firstPoint.timestamp).inSeconds);
    return (lastPoint.altitude - firstPoint.altitude) / seconds;
  }

  static double? _resolveHeading(List<FlightTrackPoint> points) {
    if (points.isEmpty) {
      return null;
    }

    final lastPoint = points.last;
    final recentPoints = points.reversed
        .takeWhile(
          (item) =>
              lastPoint.timestamp.difference(item.timestamp).inSeconds <= 18,
        )
        .toList()
        .reversed
        .toList();

    final smoothed = _resolveSmoothedHeading(recentPoints);
    if (smoothed != null) {
      return smoothed;
    }

    if (points.length < 2) {
      final heading = lastPoint.heading;
      if (heading != null && heading >= 0) {
        return heading;
      }
      return null;
    }

    final previousPoint = points[points.length - 2];
    final bearing = Geolocator.bearingBetween(
      previousPoint.latitude,
      previousPoint.longitude,
      lastPoint.latitude,
      lastPoint.longitude,
    );
    return ((bearing % 360) + 360) % 360;
  }

  static double? _resolveSmoothedHeading(List<FlightTrackPoint> points) {
    if (points.isEmpty) {
      return null;
    }

    final lastTimestamp = points.last.timestamp;
    double sinSum = 0;
    double cosSum = 0;
    double weightSum = 0;

    for (final point in points) {
      final heading = point.heading;
      if (heading == null || !heading.isFinite) {
        continue;
      }

      final speed = point.speed ?? 0;
      final accuracy = point.accuracy;
      if (speed < 1.6 && (accuracy == null || accuracy > 18)) {
        continue;
      }

      final ageSeconds =
          max(0, lastTimestamp.difference(point.timestamp).inSeconds)
              .toDouble();
      final recencyWeight = 1 / (1 + (ageSeconds / 4.0));
      final speedWeight = speed <= 0
          ? 0.55
          : (0.45 + (speed / 12.0).clamp(0.0, 0.65)).toDouble();
      final accuracyWeight = switch (accuracy) {
        null => 0.92,
        <= 10 => 1.12,
        <= 25 => 0.96,
        _ => 0.62,
      };
      final weight = recencyWeight * speedWeight * accuracyWeight;
      final radians = heading * (pi / 180);
      sinSum += sin(radians) * weight;
      cosSum += cos(radians) * weight;
      weightSum += weight;
    }

    if (weightSum <= 0) {
      return null;
    }

    final average = atan2(sinSum / weightSum, cosSum / weightSum) * 180 / pi;
    return ((average % 360) + 360) % 360;
  }

  static bool _resolveTakeoffSignal({
    required FlightTrackPoint? firstPoint,
    required FlightTrackPoint? lastPoint,
    required double currentSpeedMps,
    required Duration elapsed,
  }) {
    if (firstPoint == null || lastPoint == null) {
      return false;
    }
    final altitudeGain = lastPoint.altitude - firstPoint.altitude;
    return elapsed.inSeconds >= 30 &&
        (currentSpeedMps >= 5 || altitudeGain >= 20);
  }

  static FlightPhase _resolvePhase({
    required Duration elapsed,
    required double currentSpeedMps,
    required double verticalSpeedMps,
    required bool hasTakeoffSignal,
  }) {
    if (!hasTakeoffSignal && elapsed.inMinutes < 2) {
      return FlightPhase.standby;
    }
    if (hasTakeoffSignal && elapsed.inMinutes < 6) {
      return FlightPhase.takeoffDetected;
    }
    if (elapsed.inMinutes >= 6 &&
        currentSpeedMps < 3 &&
        verticalSpeedMps.abs() < 0.7) {
      return FlightPhase.landingLikely;
    }
    return FlightPhase.cruising;
  }

  static String _resolveLocationStatus(double? accuracyMeters) {
    if (accuracyMeters == null) {
      return '위치 상태 확인 중';
    }
    if (accuracyMeters <= 10) {
      return '위치 정확';
    }
    if (accuracyMeters <= 25) {
      return '위치 보통';
    }
    return '위치 주의';
  }
}
