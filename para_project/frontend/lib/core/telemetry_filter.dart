import 'dart:math';

import 'package:geolocator/geolocator.dart';

import '../models/app_models.dart';

class FilteredTelemetrySample {
  const FilteredTelemetrySample({
    required this.point,
    required this.distanceDeltaMeters,
  });

  final FlightTrackPoint point;
  final double distanceDeltaMeters;
}

class TelemetryFilter {
  const TelemetryFilter();

  DateTime _normalizeTimestamp(DateTime timestamp) =>
      timestamp.isUtc ? timestamp.toLocal() : timestamp;

  FilteredTelemetrySample? filter({
    required String sessionId,
    required Position position,
    required List<FlightTrackPoint> existingPoints,
  }) {
    final timestamp = _normalizeTimestamp(position.timestamp);
    if (existingPoints.isEmpty) {
      final point = FlightTrackPoint(
        id: '${sessionId}_${timestamp.microsecondsSinceEpoch}',
        sessionId: sessionId,
        timestamp: timestamp,
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        speed: 0,
        heading: null,
        accuracy: position.accuracy >= 0 ? position.accuracy : null,
      );
      return FilteredTelemetrySample(point: point, distanceDeltaMeters: 0);
    }

    final previous = existingPoints.last;
    final elapsedSeconds =
        timestamp.difference(previous.timestamp).inMilliseconds / 1000;
    if (elapsedSeconds <= 0) {
      return null;
    }

    final accuracy =
        position.accuracy >= 0 ? position.accuracy : previous.accuracy;
    if (accuracy != null && accuracy > 60) {
      return null;
    }

    final rawDistance = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      position.latitude,
      position.longitude,
    );
    final previousAccuracy = previous.accuracy ?? 12;
    final effectiveAccuracy = max(previousAccuracy, accuracy ?? 12);
    final minimumMovement = max(5.0, effectiveAccuracy * 0.55);
    final sensorSpeed = position.speed >= 0 ? position.speed : 0.0;
    final derivedSpeed = rawDistance / elapsedSeconds;
    final speedSpikeWithTinyMovement = rawDistance < minimumMovement * 0.7 &&
        sensorSpeed > 3.0 &&
        derivedSpeed < 1.2;
    final isStationary = rawDistance < minimumMovement &&
        ((sensorSpeed < 2.8 && derivedSpeed < 2.2) ||
            speedSpikeWithTinyMovement);

    if (isStationary &&
        elapsedSeconds < 8 &&
        (position.altitude - previous.altitude).abs() < 6) {
      return null;
    }

    final latitude = isStationary ? previous.latitude : position.latitude;
    final longitude = isStationary ? previous.longitude : position.longitude;
    final distanceDelta =
        isStationary || rawDistance < minimumMovement ? 0.0 : rawDistance;

    double filteredSpeed;
    if (distanceDelta == 0) {
      filteredSpeed = 0;
    } else {
      final preferredSpeed = sensorSpeed > 0 &&
              (sensorSpeed - derivedSpeed).abs() <= max(3.5, derivedSpeed * 0.8)
          ? (sensorSpeed * 0.35) + (derivedSpeed * 0.65)
          : derivedSpeed;
      filteredSpeed = min(25.0, preferredSpeed);
      final previousSpeed = previous.speed ?? 0;
      if (previousSpeed > 0) {
        filteredSpeed = (previousSpeed * 0.3) + (filteredSpeed * 0.7);
      }
      if (filteredSpeed < 1.0) {
        filteredSpeed = 0;
      }
    }

    final normalizedHeading = _normalizeHeading(
      previous: previous,
      existingPoints: existingPoints,
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp,
      sensorHeading: position.heading >= 0 ? position.heading : null,
      sensorHeadingAccuracyDegrees:
          position.headingAccuracy >= 0 ? position.headingAccuracy : null,
      speed: filteredSpeed,
      accuracyMeters: accuracy,
      movedMeters: rawDistance,
    );

    final altitude = _normalizeAltitude(
      previousAltitude: previous.altitude,
      rawAltitude: position.altitude,
      elapsedSeconds: elapsedSeconds,
      effectiveAccuracy: effectiveAccuracy,
      isStationary: isStationary,
    );

    if ((latitude - previous.latitude).abs() < 0.0000001 &&
        (longitude - previous.longitude).abs() < 0.0000001 &&
        (altitude - previous.altitude).abs() < 0.5 &&
        filteredSpeed == 0 &&
        elapsedSeconds < 12) {
      return null;
    }

    final point = FlightTrackPoint(
      id: '${sessionId}_${timestamp.microsecondsSinceEpoch}',
      sessionId: sessionId,
      timestamp: timestamp,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      speed: filteredSpeed,
      heading: normalizedHeading,
      accuracy: accuracy,
    );

    return FilteredTelemetrySample(
      point: point,
      distanceDeltaMeters: distanceDelta,
    );
  }

  double? _normalizeHeading({
    required FlightTrackPoint previous,
    required List<FlightTrackPoint> existingPoints,
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    required double? sensorHeading,
    required double? sensorHeadingAccuracyDegrees,
    required double speed,
    required double? accuracyMeters,
    required double movedMeters,
  }) {
    if (speed < 1.8) {
      return previous.heading;
    }

    final effectiveAccuracy = accuracyMeters ?? previous.accuracy ?? 12;
    final movementThreshold = max(4.0, effectiveAccuracy * 0.36);
    if (movedMeters < movementThreshold && speed < 3.4) {
      return previous.heading;
    }

    final derivedHeading = _estimateRouteHeading(
      existingPoints: existingPoints,
      currentLatitude: latitude,
      currentLongitude: longitude,
      currentTimestamp: timestamp,
      minimumMovementMeters: movementThreshold,
    );
    final candidate = _resolveHeadingCandidate(
      sensorHeading: sensorHeading,
      sensorHeadingAccuracyDegrees: sensorHeadingAccuracyDegrees,
      derivedHeading: derivedHeading,
      speed: speed,
      accuracyMeters: effectiveAccuracy,
      movedMeters: movedMeters,
    );
    if (candidate == null) {
      return previous.heading;
    }

    final previousHeading = previous.heading;
    if (previousHeading == null) {
      return candidate;
    }

    final delta = _headingDelta(previousHeading, candidate).abs();
    if (delta < 1.8) {
      return previousHeading;
    }
    if (delta < 8 && speed < 4.5) {
      return previousHeading;
    }
    if (delta < 16) {
      return _blendHeading(previousHeading, candidate, 0.42);
    }
    if (delta > 115 && speed < 6.5) {
      return previousHeading;
    }
    if (effectiveAccuracy > 28 && delta > 28 && speed < 8) {
      return previousHeading;
    }
    if (movedMeters < movementThreshold * 0.9 && speed < 4.8) {
      return previousHeading;
    }

    double smoothing = switch (speed) {
      >= 14 => 0.72,
      >= 10 => 0.58,
      >= 6 => 0.46,
      >= 3.2 => 0.34,
      _ => 0.26,
    };
    if (effectiveAccuracy > 18) {
      smoothing -= 0.08;
    }
    if (delta > 75 && speed < 8) {
      smoothing = min(smoothing, 0.28);
    }
    if (movedMeters > movementThreshold * 2.2 && speed >= 8) {
      smoothing += 0.04;
    }

    return _blendHeading(
      previousHeading,
      candidate,
      smoothing.clamp(0.20, 0.74),
    );
  }

  double? _resolveHeadingCandidate({
    required double? sensorHeading,
    required double? sensorHeadingAccuracyDegrees,
    required double? derivedHeading,
    required double speed,
    required double accuracyMeters,
    required double movedMeters,
  }) {
    final normalizedSensor = sensorHeading == null || !sensorHeading.isFinite
        ? null
        : _wrapHeading(sensorHeading);
    final normalizedDerived = derivedHeading == null || !derivedHeading.isFinite
        ? null
        : _wrapHeading(derivedHeading);
    final sensorTrust = _sensorHeadingTrust(
      speed: speed,
      accuracyMeters: accuracyMeters,
      movedMeters: movedMeters,
      headingAccuracyDegrees: sensorHeadingAccuracyDegrees,
    );

    if (normalizedSensor != null && normalizedDerived != null) {
      final gap = _headingDelta(normalizedDerived, normalizedSensor).abs();
      if (gap <= 10) {
        return _blendHeading(
          normalizedDerived,
          normalizedSensor,
          sensorTrust.clamp(0.20, 0.48),
        );
      }
      if (gap <= 24 && sensorTrust >= 0.34) {
        return _blendHeading(
          normalizedDerived,
          normalizedSensor,
          sensorTrust.clamp(0.18, 0.42),
        );
      }
      if (gap <= 42 && sensorTrust >= 0.58 && speed >= 10) {
        return normalizedSensor;
      }
      return normalizedDerived;
    }

    if (normalizedDerived != null) {
      return normalizedDerived;
    }
    if (normalizedSensor != null && sensorTrust >= 0.42) {
      return normalizedSensor;
    }

    return null;
  }

  double _blendHeading(double from, double to, double factor) {
    final delta = _headingDelta(from, to);
    return _wrapHeading(from + (delta * factor));
  }

  double _normalizeAltitude({
    required double previousAltitude,
    required double rawAltitude,
    required double elapsedSeconds,
    required double effectiveAccuracy,
    required bool isStationary,
  }) {
    final delta = rawAltitude - previousAltitude;
    if (isStationary && delta.abs() < max(4.0, effectiveAccuracy * 0.18)) {
      return previousAltitude;
    }

    if (delta.abs() > 70 && elapsedSeconds < 3) {
      return previousAltitude + (delta.isNegative ? -18 : 18);
    }

    return (previousAltitude * 0.35) + (rawAltitude * 0.65);
  }

  double? _estimateRouteHeading({
    required List<FlightTrackPoint> existingPoints,
    required double currentLatitude,
    required double currentLongitude,
    required DateTime currentTimestamp,
    required double minimumMovementMeters,
  }) {
    final window = existingPoints.length <= 6
        ? List<FlightTrackPoint>.from(existingPoints)
        : existingPoints.sublist(existingPoints.length - 6);
    if (window.isEmpty) {
      return null;
    }

    final currentPoint = FlightTrackPoint(
      id: 'derived-current',
      sessionId: window.last.sessionId,
      timestamp: currentTimestamp,
      latitude: currentLatitude,
      longitude: currentLongitude,
      altitude: window.last.altitude,
      speed: window.last.speed,
      heading: window.last.heading,
      accuracy: window.last.accuracy,
    );
    final samples = [...window, currentPoint];

    double sinSum = 0;
    double cosSum = 0;
    double weightSum = 0;
    FlightTrackPoint? earliestSignificantPoint;
    for (var index = 1; index < samples.length; index++) {
      final from = samples[index - 1];
      final to = samples[index];
      final movedMeters = Geolocator.distanceBetween(
        from.latitude,
        from.longitude,
        to.latitude,
        to.longitude,
      );
      if (movedMeters < max(3.2, minimumMovementMeters * 0.68)) {
        continue;
      }

      final seconds = max(
        1,
        to.timestamp.difference(from.timestamp).inMilliseconds,
      );
      final speedMps = movedMeters / (seconds / 1000);
      final bearing = Geolocator.bearingBetween(
        from.latitude,
        from.longitude,
        to.latitude,
        to.longitude,
      );
      final ageSeconds =
          max(0, currentTimestamp.difference(to.timestamp).inSeconds)
              .toDouble();
      final recencyWeight = 1 / (1 + (ageSeconds / 5.0));
      final distanceWeight = (movedMeters / 14.0).clamp(0.35, 1.7).toDouble();
      final speedWeight = (speedMps / 7.5).clamp(0.45, 1.30).toDouble();
      final weight = recencyWeight * distanceWeight * speedWeight;
      final radians = _wrapHeading(bearing) * (pi / 180);
      sinSum += sin(radians) * weight;
      cosSum += cos(radians) * weight;
      weightSum += weight;
      earliestSignificantPoint ??= from;
    }

    if (weightSum <= 0) {
      return null;
    }

    final average = atan2(sinSum / weightSum, cosSum / weightSum) * 180 / pi;
    final segmentBearing = _wrapHeading(average);
    if (earliestSignificantPoint == null) {
      return segmentBearing;
    }

    final netDistance = Geolocator.distanceBetween(
      earliestSignificantPoint.latitude,
      earliestSignificantPoint.longitude,
      currentLatitude,
      currentLongitude,
    );
    if (netDistance < minimumMovementMeters * 1.35) {
      return segmentBearing;
    }

    final netBearing = Geolocator.bearingBetween(
      earliestSignificantPoint.latitude,
      earliestSignificantPoint.longitude,
      currentLatitude,
      currentLongitude,
    );
    return _blendHeading(segmentBearing, _wrapHeading(netBearing), 0.32);
  }

  double _sensorHeadingTrust({
    required double speed,
    required double accuracyMeters,
    required double movedMeters,
    required double? headingAccuracyDegrees,
  }) {
    var trust = switch (speed) {
      >= 12 => 0.58,
      >= 8 => 0.44,
      >= 5 => 0.32,
      _ => 0.18,
    };

    trust += switch (headingAccuracyDegrees) {
      null => 0.04,
      <= 10 => 0.24,
      <= 20 => 0.14,
      <= 35 => 0.04,
      _ => -0.18,
    };

    if (accuracyMeters <= 12) {
      trust += 0.10;
    } else if (accuracyMeters > 24) {
      trust -= 0.10;
    }

    if (movedMeters < max(4.0, accuracyMeters * 0.32)) {
      trust -= 0.08;
    }

    return trust.clamp(0.0, 0.78).toDouble();
  }

  double _wrapHeading(double heading) {
    final normalized = heading % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  double _headingDelta(double from, double to) {
    final difference = (to - from + 540) % 360 - 180;
    return difference;
  }
}
