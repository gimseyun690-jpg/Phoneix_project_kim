import 'dart:math';

import 'package:geolocator/geolocator.dart';

import '../models/app_models.dart';

enum FlightReplayCameraMode {
  overview,
  follow,
  topDown,
  perspective,
}

enum FlightReplaySegmentType {
  takeoff,
  landing,
  thermal,
}

extension FlightReplayCameraModeLabel on FlightReplayCameraMode {
  String get label => switch (this) {
        FlightReplayCameraMode.overview => '전체 보기',
        FlightReplayCameraMode.follow => '따라가기',
        FlightReplayCameraMode.topDown => '상단 보기',
        FlightReplayCameraMode.perspective => '3D 시점',
      };
}

class FlightReplayFrame {
  const FlightReplayFrame({
    required this.sourceIndex,
    required this.timestamp,
    required this.elapsedDuration,
    required this.latitude,
    required this.longitude,
    required this.altitudeMeters,
    required this.displayAltitudeMeters,
    required this.altitudeFromStartMeters,
    required this.speedMps,
    required this.heading,
    required this.verticalSpeedMps,
    required this.cumulativeDistanceMeters,
    required this.progress,
  });

  final int sourceIndex;
  final DateTime timestamp;
  final Duration elapsedDuration;
  final double latitude;
  final double longitude;
  final double altitudeMeters;
  final double displayAltitudeMeters;
  final double altitudeFromStartMeters;
  final double speedMps;
  final double heading;
  final double verticalSpeedMps;
  final double cumulativeDistanceMeters;
  final double progress;
}

class FlightReplaySegment {
  const FlightReplaySegment({
    required this.type,
    required this.label,
    required this.startIndex,
    required this.endIndex,
    required this.duration,
    required this.altitudeGainMeters,
    required this.maxClimbRateMps,
  });

  final FlightReplaySegmentType type;
  final String label;
  final int startIndex;
  final int endIndex;
  final Duration duration;
  final double altitudeGainMeters;
  final double maxClimbRateMps;
}

class FlightReplayData {
  const FlightReplayData({
    required this.frames,
    required this.highestFrameIndex,
    required this.takeoffFrameIndex,
    required this.landingFrameIndex,
    required this.thermalSegments,
    required this.totalDuration,
    required this.totalDistanceMeters,
    required this.minAltitudeMeters,
    required this.maxAltitudeMeters,
  });

  final List<FlightReplayFrame> frames;
  final int highestFrameIndex;
  final int takeoffFrameIndex;
  final int landingFrameIndex;
  final List<FlightReplaySegment> thermalSegments;
  final Duration totalDuration;
  final double totalDistanceMeters;
  final double minAltitudeMeters;
  final double maxAltitudeMeters;

  bool get hasFrames => frames.isNotEmpty;
  FlightReplayFrame? get startFrame => hasFrames ? frames.first : null;
  FlightReplayFrame? get endFrame => hasFrames ? frames.last : null;
  FlightReplayFrame? get highestFrame =>
      hasFrames ? frames[highestFrameIndex] : null;

  FlightReplayFrame frameAt(int index) {
    if (frames.isEmpty) {
      throw StateError('리플레이 프레임이 없습니다.');
    }
    final clamped = index.clamp(0, frames.length - 1);
    return frames[clamped];
  }

  int futureFrameIndex(
    int index, {
    int minimumLeadFrames = 5,
    int maximumLeadFrames = 18,
  }) {
    if (frames.isEmpty) {
      return 0;
    }

    final safeIndex = index.clamp(0, frames.length - 1).toInt();
    final current = frameAt(safeIndex);
    final speedFactor = (current.speedMps / 4.0).round().clamp(
          0,
          max(0, maximumLeadFrames - minimumLeadFrames),
        ).toInt();
    return min(
      frames.length - 1,
      safeIndex + minimumLeadFrames + speedFactor,
    );
  }

  double bearingBetweenIndices(int startIndex, int endIndex) {
    if (frames.length < 2) {
      return 0;
    }

    final safeStartIndex = startIndex.clamp(0, frames.length - 1);
    final safeEndIndex = endIndex.clamp(0, frames.length - 1);
    if (safeStartIndex == safeEndIndex) {
      return frameAt(safeStartIndex).heading;
    }

    final start = frameAt(safeStartIndex);
    final end = frameAt(safeEndIndex);
    final bearing = Geolocator.bearingBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
    return _normalizeBearing(bearing);
  }

  int nearestFrameIndex(DateTime timestamp) {
    if (frames.isEmpty) {
      return 0;
    }

    var bestIndex = 0;
    var bestDelta =
        frames.first.timestamp.difference(timestamp).abs().inMilliseconds;
    for (var index = 1; index < frames.length; index++) {
      final delta =
          frames[index].timestamp.difference(timestamp).abs().inMilliseconds;
      if (delta < bestDelta) {
        bestDelta = delta;
        bestIndex = index;
      }
    }
    return bestIndex;
  }

  int indexForProgress(double progress) {
    if (frames.isEmpty) {
      return 0;
    }
    final clamped = progress.clamp(0.0, 1.0);
    return (clamped * (frames.length - 1)).round();
  }

  factory FlightReplayData.fromPoints(
    List<FlightTrackPoint> points, {
    int maxFrames = 220,
  }) {
    if (points.isEmpty) {
      return const FlightReplayData(
        frames: [],
        highestFrameIndex: 0,
        takeoffFrameIndex: 0,
        landingFrameIndex: 0,
        thermalSegments: [],
        totalDuration: Duration.zero,
        totalDistanceMeters: 0,
        minAltitudeMeters: 0,
        maxAltitudeMeters: 0,
      );
    }

    final cumulativeDistances = _buildCumulativeDistances(points);
    final selectedIndices = _buildSelectedIndices(
      points: points,
      maxFrames: maxFrames,
    );
    final totalDuration =
        points.last.timestamp.difference(points.first.timestamp);
    final totalDistanceMeters =
        cumulativeDistances.isEmpty ? 0.0 : cumulativeDistances.last;
    final displayAltitudes = selectedIndices
        .map((sourceIndex) => _smoothAltitude(points, sourceIndex))
        .toList(growable: false);
    final startDisplayAltitude = displayAltitudes.isEmpty
        ? points.first.altitude
        : displayAltitudes.first;

    final frames = <FlightReplayFrame>[];
    for (var selectedIndex = 0;
        selectedIndex < selectedIndices.length;
        selectedIndex++) {
      final sourceIndex = selectedIndices[selectedIndex];
      final point = points[sourceIndex];
      final safeDurationSeconds = max(1, totalDuration.inSeconds);
      final elapsedSeconds = max(
        0,
        point.timestamp.difference(points.first.timestamp).inSeconds,
      );
      final progress = totalDuration == Duration.zero
          ? (selectedIndices.length == 1
              ? 0.0
              : frames.length / (selectedIndices.length - 1))
          : elapsedSeconds / safeDurationSeconds;
      final displayAltitude = displayAltitudes[selectedIndex];
      final verticalSpeed = selectedIndex == 0
          ? 0.0
          : _resolveVerticalSpeed(
              previousAltitude: displayAltitudes[selectedIndex - 1],
              currentAltitude: displayAltitude,
              previousTimestamp:
                  points[selectedIndices[selectedIndex - 1]].timestamp,
              currentTimestamp: point.timestamp,
            );

      frames.add(
        FlightReplayFrame(
          sourceIndex: sourceIndex,
          timestamp: point.timestamp,
          elapsedDuration: point.timestamp.difference(points.first.timestamp),
          latitude: point.latitude,
          longitude: point.longitude,
          altitudeMeters: point.altitude,
          displayAltitudeMeters: displayAltitude,
          altitudeFromStartMeters: displayAltitude - startDisplayAltitude,
          speedMps: _resolveSpeed(points, sourceIndex),
          heading: _resolveHeading(points, sourceIndex),
          verticalSpeedMps: verticalSpeed,
          cumulativeDistanceMeters: cumulativeDistances[sourceIndex],
          progress: progress.clamp(0.0, 1.0),
        ),
      );
    }

    var minAltitude = frames.first.displayAltitudeMeters;
    var maxAltitude = frames.first.displayAltitudeMeters;
    var highestFrameIndex = 0;

    for (var index = 0; index < frames.length; index++) {
      final altitude = frames[index].displayAltitudeMeters;
      if (altitude < minAltitude) {
        minAltitude = altitude;
      }
      if (altitude >= maxAltitude) {
        maxAltitude = altitude;
        highestFrameIndex = index;
      }
    }

    final takeoffFrameIndex = _detectTakeoffFrameIndex(frames);
    final landingFrameIndex = _detectLandingFrameIndex(frames);
    final thermalSegments = _detectThermalSegments(
      frames,
      takeoffFrameIndex: takeoffFrameIndex,
      landingFrameIndex: landingFrameIndex,
    );

    return FlightReplayData(
      frames: frames,
      highestFrameIndex: highestFrameIndex,
      takeoffFrameIndex: takeoffFrameIndex,
      landingFrameIndex: landingFrameIndex,
      thermalSegments: thermalSegments,
      totalDuration: totalDuration,
      totalDistanceMeters: totalDistanceMeters,
      minAltitudeMeters: minAltitude,
      maxAltitudeMeters: maxAltitude,
    );
  }

  static List<double> _buildCumulativeDistances(List<FlightTrackPoint> points) {
    if (points.isEmpty) {
      return const [];
    }

    final result = List<double>.filled(points.length, 0);
    var distance = 0.0;
    for (var index = 1; index < points.length; index++) {
      distance += Geolocator.distanceBetween(
        points[index - 1].latitude,
        points[index - 1].longitude,
        points[index].latitude,
        points[index].longitude,
      );
      result[index] = distance;
    }
    return result;
  }

  static List<int> _buildSelectedIndices({
    required List<FlightTrackPoint> points,
    required int maxFrames,
  }) {
    if (points.length <= maxFrames) {
      return List<int>.generate(points.length, (index) => index);
    }

    final selected = <int>{0, points.length - 1, _highestAltitudeIndex(points)};
    final step = (points.length - 1) / (maxFrames - 1);
    for (var index = 0; index < maxFrames; index++) {
      selected.add((index * step).round());
    }

    final result = selected.toList()..sort();
    return result;
  }

  static int _highestAltitudeIndex(List<FlightTrackPoint> points) {
    var highestIndex = 0;
    for (var index = 1; index < points.length; index++) {
      if (points[index].altitude >= points[highestIndex].altitude) {
        highestIndex = index;
      }
    }
    return highestIndex;
  }

  static double _smoothAltitude(List<FlightTrackPoint> points, int index) {
    var weightedAltitude = 0.0;
    var weightSum = 0.0;
    for (var offset = -2; offset <= 2; offset++) {
      final neighborIndex = index + offset;
      if (neighborIndex < 0 || neighborIndex >= points.length) {
        continue;
      }

      final distanceFromCenter = offset.abs();
      final weight = switch (distanceFromCenter) {
        0 => 0.40,
        1 => 0.22,
        _ => 0.08,
      };
      weightedAltitude += points[neighborIndex].altitude * weight;
      weightSum += weight;
    }

    if (weightSum == 0) {
      return points[index].altitude;
    }
    return weightedAltitude / weightSum;
  }

  static double _resolveSpeed(List<FlightTrackPoint> points, int index) {
    final point = points[index];
    final directSpeed = point.speed;
    if (directSpeed != null && directSpeed.isFinite && directSpeed >= 0) {
      return directSpeed;
    }

    if (points.length < 2) {
      return 0;
    }

    final previousIndex = max(0, index - 1);
    final nextIndex = min(points.length - 1, index + 1);
    if (previousIndex == nextIndex) {
      return 0;
    }

    final previous = points[previousIndex];
    final next = points[nextIndex];
    final seconds = max(
      1,
      next.timestamp.difference(previous.timestamp).inSeconds,
    );
    final distance = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      next.latitude,
      next.longitude,
    );
    return distance / seconds;
  }

  static double _resolveHeading(List<FlightTrackPoint> points, int index) {
    final point = points[index];
    final directHeading = point.heading;
    if (directHeading != null && directHeading.isFinite) {
      return _normalizeBearing(directHeading);
    }

    if (points.length < 2) {
      return 0;
    }

    final previousIndex = max(0, index - 1);
    final nextIndex = min(points.length - 1, index + 1);
    if (previousIndex == nextIndex) {
      return 0;
    }

    final previous = points[previousIndex];
    final next = points[nextIndex];
    final bearing = Geolocator.bearingBetween(
      previous.latitude,
      previous.longitude,
      next.latitude,
      next.longitude,
    );
    return _normalizeBearing(bearing);
  }

  static double _normalizeBearing(double value) {
    return ((value % 360) + 360) % 360;
  }

  static int _detectTakeoffFrameIndex(List<FlightReplayFrame> frames) {
    if (frames.length < 2) {
      return 0;
    }

    for (var index = 1; index < frames.length; index++) {
      final frame = frames[index];
      final movedEnough = frame.cumulativeDistanceMeters >= 70;
      final climbedEnough = frame.altitudeFromStartMeters >= 18;
      final fastEnough = frame.speedMps >= 4.5;
      if (movedEnough || climbedEnough || fastEnough) {
        return index;
      }
    }

    return min(1, frames.length - 1);
  }

  static int _detectLandingFrameIndex(List<FlightReplayFrame> frames) {
    if (frames.length < 2) {
      return 0;
    }

    final endFrame = frames.last;
    final totalDistance = frames.last.cumulativeDistanceMeters;
    final minimumIndex = max(0, (frames.length * 0.65).floor());

    for (var index = frames.length - 2; index >= minimumIndex; index--) {
      final frame = frames[index];
      final remainingDistance = totalDistance - frame.cumulativeDistanceMeters;
      final altitudeGapToEnd =
          (frame.displayAltitudeMeters - endFrame.displayAltitudeMeters).abs();
      final slowEnough = frame.speedMps <= 4.5;
      final closeEnough = remainingDistance <= 180;
      final altitudeCloseEnough = altitudeGapToEnd <= 25;
      if (closeEnough && altitudeCloseEnough && slowEnough) {
        return index;
      }
    }

    return max(0, frames.length - max(2, (frames.length * 0.12).round()));
  }

  static List<FlightReplaySegment> _detectThermalSegments(
    List<FlightReplayFrame> frames, {
    required int takeoffFrameIndex,
    required int landingFrameIndex,
  }) {
    if (frames.length < 4) {
      return const [];
    }

    final segments = <FlightReplaySegment>[];
    int? startIndex;
    var maxClimb = 0.0;

    for (var index = max(1, takeoffFrameIndex);
        index <= min(frames.length - 1, landingFrameIndex);
        index++) {
      final frame = frames[index];
      final climbing = frame.verticalSpeedMps >= 0.8;
      final sustainClimb = frame.verticalSpeedMps >= 0.35;

      if (startIndex == null && climbing) {
        startIndex = index - 1;
        maxClimb = frame.verticalSpeedMps;
        continue;
      }

      if (startIndex != null) {
        if (sustainClimb) {
          maxClimb = max(maxClimb, frame.verticalSpeedMps);
          continue;
        }

        final segment = _buildThermalSegment(
          frames,
          startIndex: startIndex,
          endIndex: index - 1,
          order: segments.length + 1,
          maxClimbRateMps: maxClimb,
        );
        if (segment != null) {
          segments.add(segment);
        }
        startIndex = null;
        maxClimb = 0.0;
      }
    }

    if (startIndex != null) {
      final segment = _buildThermalSegment(
        frames,
        startIndex: startIndex,
        endIndex: min(landingFrameIndex, frames.length - 1),
        order: segments.length + 1,
        maxClimbRateMps: maxClimb,
      );
      if (segment != null) {
        segments.add(segment);
      }
    }

    return segments.take(4).toList(growable: false);
  }

  static FlightReplaySegment? _buildThermalSegment(
    List<FlightReplayFrame> frames, {
    required int startIndex,
    required int endIndex,
    required int order,
    required double maxClimbRateMps,
  }) {
    if (endIndex <= startIndex) {
      return null;
    }
    final startFrame = frames[startIndex];
    final endFrame = frames[endIndex];
    final duration = endFrame.timestamp.difference(startFrame.timestamp);
    final altitudeGain =
        endFrame.displayAltitudeMeters - startFrame.displayAltitudeMeters;

    if (duration.inSeconds < 20 || altitudeGain < 30) {
      return null;
    }

    return FlightReplaySegment(
      type: FlightReplaySegmentType.thermal,
      label: '써멀 $order',
      startIndex: startIndex,
      endIndex: endIndex,
      duration: duration,
      altitudeGainMeters: altitudeGain,
      maxClimbRateMps: maxClimbRateMps,
    );
  }

  static double _resolveVerticalSpeed({
    required double previousAltitude,
    required double currentAltitude,
    required DateTime previousTimestamp,
    required DateTime currentTimestamp,
  }) {
    final seconds = max(
      1,
      currentTimestamp.difference(previousTimestamp).inSeconds,
    );
    return (currentAltitude - previousAltitude) / seconds;
  }
}
