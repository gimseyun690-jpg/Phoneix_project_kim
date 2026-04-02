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

  FilteredTelemetrySample? filter({
    required String sessionId,
    required Position position,
    required List<FlightTrackPoint> existingPoints,
  }) {
    if (existingPoints.isEmpty) {
      final point = FlightTrackPoint(
        id: '${sessionId}_${position.timestamp.microsecondsSinceEpoch}',
        sessionId: sessionId,
        timestamp: position.timestamp,
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
        position.timestamp.difference(previous.timestamp).inMilliseconds / 1000;
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
      latitude: latitude,
      longitude: longitude,
      sensorHeading: position.heading >= 0 ? position.heading : null,
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
      id: '${sessionId}_${position.timestamp.microsecondsSinceEpoch}',
      sessionId: sessionId,
      timestamp: position.timestamp,
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
    required double latitude,
    required double longitude,
    required double? sensorHeading,
    required double speed,
    required double? accuracyMeters,
    required double movedMeters,
  }) {
    if (speed < 2.2) {
      return previous.heading;
    }

    final effectiveAccuracy = accuracyMeters ?? previous.accuracy ?? 12;
    final movementThreshold = max(4.5, effectiveAccuracy * 0.40);
    if (movedMeters < movementThreshold && speed < 3.4) {
      return previous.heading;
    }

    final derivedHeading = movedMeters >= movementThreshold
        ? Geolocator.bearingBetween(
            previous.latitude,
            previous.longitude,
            latitude,
            longitude,
          )
        : null;
    final candidate = _resolveHeadingCandidate(
      sensorHeading: sensorHeading,
      derivedHeading: derivedHeading,
      speed: speed,
      accuracyMeters: effectiveAccuracy,
    );
    if (candidate == null) {
      return previous.heading;
    }

    final previousHeading = previous.heading;
    if (previousHeading == null) {
      return candidate;
    }

    final delta = _headingDelta(previousHeading, candidate).abs();
    if (delta < 2.5) {
      return previousHeading;
    }
    if (delta < 12) {
      return _blendHeading(previousHeading, candidate, 0.30);
    }
    if (delta > 110 && speed < 4.8) {
      return previousHeading;
    }
    if (effectiveAccuracy > 28 && delta > 28 && speed < 8) {
      return previousHeading;
    }

    double smoothing = switch (speed) {
      >= 12 => 0.60,
      >= 8 => 0.46,
      >= 4.5 => 0.34,
      _ => 0.24,
    };
    if (effectiveAccuracy > 18) {
      smoothing -= 0.08;
    }
    if (delta > 70 && speed < 7) {
      smoothing = min(smoothing, 0.24);
    }

    return _blendHeading(
      previousHeading,
      candidate,
      smoothing.clamp(0.18, 0.60),
    );
  }

  double? _resolveHeadingCandidate({
    required double? sensorHeading,
    required double? derivedHeading,
    required double speed,
    required double accuracyMeters,
  }) {
    final normalizedSensor = sensorHeading == null || !sensorHeading.isFinite
        ? null
        : _wrapHeading(sensorHeading);
    final normalizedDerived = derivedHeading == null || !derivedHeading.isFinite
        ? null
        : _wrapHeading(derivedHeading);

    if (normalizedSensor != null && normalizedDerived != null) {
      final gap = _headingDelta(normalizedDerived, normalizedSensor).abs();
      if (gap <= 14) {
        return _blendHeading(normalizedDerived, normalizedSensor, 0.42);
      }
      if (gap <= 40 && speed >= 9 && accuracyMeters <= 18) {
        return _blendHeading(normalizedDerived, normalizedSensor, 0.26);
      }
      return normalizedDerived;
    }

    return normalizedDerived ?? normalizedSensor;
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

  double _wrapHeading(double heading) {
    final normalized = heading % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  double _headingDelta(double from, double to) {
    final difference = (to - from + 540) % 360 - 180;
    return difference;
  }
}
