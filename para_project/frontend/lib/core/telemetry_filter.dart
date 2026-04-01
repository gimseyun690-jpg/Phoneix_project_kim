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
  }) {
    if (speed < 2.5) {
      return previous.heading;
    }

    var heading = sensorHeading;
    heading ??= Geolocator.bearingBetween(
      previous.latitude,
      previous.longitude,
      latitude,
      longitude,
    );

    if (!heading.isFinite) {
      return previous.heading;
    }

    final normalized = _wrapHeading(heading);
    final previousHeading = previous.heading;
    if (previousHeading == null) {
      return normalized;
    }

    final delta = _headingDelta(previousHeading, normalized).abs();
    if (delta < 15) {
      return _wrapHeading((previousHeading * 0.45) + (normalized * 0.55));
    }
    if (delta > 110 && speed < 4.2) {
      return previousHeading;
    }
    return normalized;
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
