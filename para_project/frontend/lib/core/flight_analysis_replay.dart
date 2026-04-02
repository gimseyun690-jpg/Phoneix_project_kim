import 'dart:math';

import 'package:geolocator/geolocator.dart';

import '../models/app_models.dart';

enum FlightReplayCameraMode {
  overview,
  follow,
  topDown,
  perspective,
  sideView,
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
        FlightReplayCameraMode.perspective => '사선 3D 보기',
        FlightReplayCameraMode.sideView => '측면 3D 보기',
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

class FlightReplayTerrainFrame {
  const FlightReplayTerrainFrame({
    required this.terrainElevationMeters,
    required this.rawClearanceMeters,
    required this.correctedClearanceMeters,
    required this.visualClearanceMeters,
    required this.isInterpolated,
  });

  final double terrainElevationMeters;
  final double rawClearanceMeters;
  final double correctedClearanceMeters;
  final double visualClearanceMeters;
  final bool isInterpolated;
}

class FlightReplayTerrainAlignment {
  const FlightReplayTerrainAlignment({
    required this.frames,
    required this.altitudeBiasMeters,
    required this.sampledFrameCount,
    required this.referenceFrameCount,
    required this.minVisualClearanceMeters,
    required this.maxVisualClearanceMeters,
    required this.biasApplied,
  });

  static const empty = FlightReplayTerrainAlignment(
    frames: [],
    altitudeBiasMeters: 0,
    sampledFrameCount: 0,
    referenceFrameCount: 0,
    minVisualClearanceMeters: 0,
    maxVisualClearanceMeters: 0,
    biasApplied: false,
  );

  final List<FlightReplayTerrainFrame> frames;
  final double altitudeBiasMeters;
  final int sampledFrameCount;
  final int referenceFrameCount;
  final double minVisualClearanceMeters;
  final double maxVisualClearanceMeters;
  final bool biasApplied;

  bool get hasTerrainSamples => frames.isNotEmpty && sampledFrameCount > 0;
  bool get hasUsableSamples =>
      hasTerrainSamples &&
      sampledFrameCount >= min(18, max(4, (frames.length * 0.03).round()));

  FlightReplayTerrainFrame frameAt(int index) {
    if (frames.isEmpty) {
      throw StateError('지형 정렬 데이터가 없습니다.');
    }
    return frames[index.clamp(0, frames.length - 1)];
  }

  double visualClearanceAt(int index) => frameAt(index).visualClearanceMeters;

  double correctedClearanceAt(int index) =>
      frameAt(index).correctedClearanceMeters;

  factory FlightReplayTerrainAlignment.fromTerrainSamples(
    FlightReplayData replayData,
    List<double?> terrainElevationsMeters,
  ) {
    if (replayData.frames.isEmpty || terrainElevationsMeters.isEmpty) {
      return empty;
    }

    final source = List<double?>.filled(replayData.frames.length, null);
    final sampledFlags = List<bool>.filled(replayData.frames.length, false);

    for (var index = 0;
        index < min(replayData.frames.length, terrainElevationsMeters.length);
        index++) {
      final terrain = terrainElevationsMeters[index];
      if (terrain == null || !terrain.isFinite) {
        continue;
      }
      if (terrain < -500 || terrain > 12000) {
        continue;
      }
      source[index] = terrain;
      sampledFlags[index] = true;
    }

    final sampledFrameCount = sampledFlags.where((flag) => flag).length;
    if (sampledFrameCount == 0) {
      return empty;
    }

    final filledTerrain = _fillTerrainSeries(source);
    if (filledTerrain.every((value) => value == null)) {
      return empty;
    }

    final smoothedTerrain = _smoothSeries(
      filledTerrain.map((value) => value ?? 0).toList(growable: false),
    );
    final rawClearances = List<double>.generate(
      replayData.frames.length,
      (index) =>
          replayData.frames[index].displayAltitudeMeters -
          smoothedTerrain[index],
      growable: false,
    );

    final biasEstimate = _estimateAltitudeBias(replayData, rawClearances);
    final correctedClearances = rawClearances
        .map((value) => max(0.0, value - biasEstimate.biasMeters))
        .toList(growable: false);
    final smoothedClearances = _smoothSeries(correctedClearances);

    final frames = List<FlightReplayTerrainFrame>.generate(
      replayData.frames.length,
      (index) {
        final corrected = correctedClearances[index];
        final visual = max(1.4, smoothedClearances[index]);
        return FlightReplayTerrainFrame(
          terrainElevationMeters: smoothedTerrain[index],
          rawClearanceMeters: rawClearances[index],
          correctedClearanceMeters: corrected,
          visualClearanceMeters: visual,
          isInterpolated: !sampledFlags[index],
        );
      },
      growable: false,
    );

    var minClearance = frames.first.visualClearanceMeters;
    var maxClearance = frames.first.visualClearanceMeters;
    for (final frame in frames.skip(1)) {
      minClearance = min(minClearance, frame.visualClearanceMeters);
      maxClearance = max(maxClearance, frame.visualClearanceMeters);
    }

    return FlightReplayTerrainAlignment(
      frames: frames,
      altitudeBiasMeters: biasEstimate.biasMeters,
      sampledFrameCount: sampledFrameCount,
      referenceFrameCount: biasEstimate.referenceCount,
      minVisualClearanceMeters: minClearance,
      maxVisualClearanceMeters: maxClearance,
      biasApplied: biasEstimate.applied,
    );
  }

  static List<double?> _fillTerrainSeries(List<double?> values) {
    if (values.isEmpty) {
      return const [];
    }

    final knownIndices = <int>[];
    for (var index = 0; index < values.length; index++) {
      if (values[index] != null) {
        knownIndices.add(index);
      }
    }
    if (knownIndices.isEmpty) {
      return List<double?>.filled(values.length, null);
    }
    if (knownIndices.length == 1) {
      return List<double?>.filled(values.length, values[knownIndices.first]);
    }

    final result = List<double?>.filled(values.length, null);

    final firstKnown = knownIndices.first;
    for (var index = 0; index <= firstKnown; index++) {
      result[index] = values[firstKnown];
    }

    for (var cursor = 0; cursor < knownIndices.length - 1; cursor++) {
      final startIndex = knownIndices[cursor];
      final endIndex = knownIndices[cursor + 1];
      final startValue = values[startIndex]!;
      final endValue = values[endIndex]!;
      result[startIndex] = startValue;
      for (var index = startIndex + 1; index < endIndex; index++) {
        final t = (index - startIndex) / (endIndex - startIndex);
        result[index] = startValue + ((endValue - startValue) * t);
      }
      result[endIndex] = endValue;
    }

    final lastKnown = knownIndices.last;
    for (var index = lastKnown; index < result.length; index++) {
      result[index] = values[lastKnown];
    }

    return result;
  }

  static List<double> _smoothSeries(List<double> values) {
    if (values.length < 3) {
      return values;
    }

    return List<double>.generate(values.length, (index) {
      var weightedSum = 0.0;
      var weightSum = 0.0;
      for (var offset = -2; offset <= 2; offset++) {
        final neighborIndex = index + offset;
        if (neighborIndex < 0 || neighborIndex >= values.length) {
          continue;
        }
        final distance = offset.abs();
        final weight = switch (distance) {
          0 => 0.36,
          1 => 0.22,
          _ => 0.10,
        };
        weightedSum += values[neighborIndex] * weight;
        weightSum += weight;
      }
      if (weightSum == 0) {
        return values[index];
      }
      return weightedSum / weightSum;
    }, growable: false);
  }

  static _TerrainBiasEstimate _estimateAltitudeBias(
    FlightReplayData replayData,
    List<double> rawClearances,
  ) {
    if (rawClearances.isEmpty) {
      return const _TerrainBiasEstimate(
        biasMeters: 0,
        referenceCount: 0,
        applied: false,
      );
    }

    final candidates = <double>[];
    final windowRadius = max(3, (rawClearances.length * 0.05).round());

    void addWindowMin(int start, int end) {
      final safeStart = start.clamp(0, rawClearances.length - 1);
      final safeEnd = end.clamp(safeStart, rawClearances.length - 1);
      double? minimum;
      for (var index = safeStart; index <= safeEnd; index++) {
        final value = rawClearances[index];
        if (!value.isFinite) {
          continue;
        }
        minimum = minimum == null ? value : min(minimum, value);
      }
      if (minimum != null) {
        candidates.add(minimum);
      }
    }

    addWindowMin(0, max(replayData.takeoffFrameIndex + windowRadius, 0));
    addWindowMin(
      max(0, replayData.landingFrameIndex - windowRadius),
      rawClearances.length - 1,
    );

    final sorted = List<double>.from(rawClearances)..sort();
    final percentileIndex =
        ((sorted.length - 1) * 0.08).round().clamp(0, sorted.length - 1);
    candidates.add(sorted[percentileIndex]);

    final reliable = candidates
        .where((value) => value.isFinite && value.abs() <= 150)
        .toList(growable: false);
    if (reliable.isEmpty) {
      return const _TerrainBiasEstimate(
        biasMeters: 0,
        referenceCount: 0,
        applied: false,
      );
    }

    final median = _median(reliable);
    return _TerrainBiasEstimate(
      biasMeters: median,
      referenceCount: reliable.length,
      applied: median.abs() >= 2.0,
    );
  }

  static double _median(List<double> values) {
    if (values.isEmpty) {
      return 0;
    }
    final sorted = List<double>.from(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[middle];
    }
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }
}

class _TerrainBiasEstimate {
  const _TerrainBiasEstimate({
    required this.biasMeters,
    required this.referenceCount,
    required this.applied,
  });

  final double biasMeters;
  final int referenceCount;
  final bool applied;
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
    return frames[index.clamp(0, frames.length - 1)];
  }

  Duration durationForRange({
    int startIndex = 0,
    int? endIndex,
  }) {
    if (frames.isEmpty) {
      return Duration.zero;
    }

    final safeStart = startIndex.clamp(0, frames.length - 1);
    final safeEnd = (endIndex ?? frames.length - 1).clamp(
      safeStart,
      frames.length - 1,
    );
    return frameAt(safeEnd).elapsedDuration -
        frameAt(safeStart).elapsedDuration;
  }

  double progressForIndex(
    int index, {
    int startIndex = 0,
    int? endIndex,
  }) {
    if (frames.isEmpty) {
      return 0;
    }

    final safeStart = startIndex.clamp(0, frames.length - 1);
    final safeEnd = (endIndex ?? frames.length - 1).clamp(
      safeStart,
      frames.length - 1,
    );
    final safeIndex = index.clamp(safeStart, safeEnd);
    final rangeDuration = durationForRange(
      startIndex: safeStart,
      endIndex: safeEnd,
    );
    if (rangeDuration == Duration.zero) {
      return 0;
    }

    final elapsedFromStart =
        frameAt(safeIndex).elapsedDuration - frameAt(safeStart).elapsedDuration;
    return (elapsedFromStart.inMilliseconds / rangeDuration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  Duration elapsedForProgress(
    double progress, {
    int startIndex = 0,
    int? endIndex,
  }) {
    if (frames.isEmpty) {
      return Duration.zero;
    }

    final safeStart = startIndex.clamp(0, frames.length - 1);
    final safeEnd = (endIndex ?? frames.length - 1).clamp(
      safeStart,
      frames.length - 1,
    );
    final clampedProgress = progress.clamp(0.0, 1.0);
    final startElapsed = frameAt(safeStart).elapsedDuration;
    final rangeDuration = durationForRange(
      startIndex: safeStart,
      endIndex: safeEnd,
    );
    return startElapsed +
        Duration(
          milliseconds:
              (rangeDuration.inMilliseconds * clampedProgress).round(),
        );
  }

  int futureFrameIndex(
    int index, {
    int minimumLeadFrames = 5,
    int maximumLeadFrames = 18,
  }) {
    if (frames.isEmpty) {
      return 0;
    }

    final safeIndex = index.clamp(0, frames.length - 1);
    final current = frameAt(safeIndex);
    final speedFactor = (current.speedMps / 4.0).round().clamp(
          0,
          max(0, maximumLeadFrames - minimumLeadFrames),
        ) as int;
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
    return _nearestIndexForEpochMilliseconds(timestamp.millisecondsSinceEpoch);
  }

  int indexForElapsed(Duration elapsed) {
    if (frames.isEmpty) {
      return 0;
    }
    final clampedElapsed = Duration(
      milliseconds: elapsed.inMilliseconds.clamp(
        0,
        max(0, totalDuration.inMilliseconds),
      ),
    );
    final startTimestamp = frames.first.timestamp.millisecondsSinceEpoch;
    return _nearestIndexForEpochMilliseconds(
      startTimestamp + clampedElapsed.inMilliseconds,
    );
  }

  int indexForProgress(
    double progress, {
    int startIndex = 0,
    int? endIndex,
  }) {
    if (frames.isEmpty) {
      return 0;
    }

    final safeStart = startIndex.clamp(0, frames.length - 1);
    final safeEnd = (endIndex ?? frames.length - 1).clamp(
      safeStart,
      frames.length - 1,
    );
    final targetElapsed = elapsedForProgress(
      progress,
      startIndex: safeStart,
      endIndex: safeEnd,
    );
    return indexForElapsed(targetElapsed).clamp(safeStart, safeEnd);
  }

  FlightReplayFrame sampleFrameForProgress(
    double progress, {
    int startIndex = 0,
    int? endIndex,
  }) {
    if (frames.isEmpty) {
      throw StateError('리플레이 프레임이 없습니다.');
    }

    final safeStart = startIndex.clamp(0, frames.length - 1);
    final safeEnd = (endIndex ?? frames.length - 1).clamp(
      safeStart,
      frames.length - 1,
    );
    if (safeStart == safeEnd) {
      return frameAt(safeStart);
    }

    final targetElapsed = elapsedForProgress(
      progress,
      startIndex: safeStart,
      endIndex: safeEnd,
    );
    return sampleFrameForElapsed(
      targetElapsed,
      startIndex: safeStart,
      endIndex: safeEnd,
    );
  }

  FlightReplayFrame sampleFrameForElapsed(
    Duration elapsed, {
    int startIndex = 0,
    int? endIndex,
  }) {
    if (frames.isEmpty) {
      throw StateError('리플레이 프레임이 없습니다.');
    }

    final safeStart = startIndex.clamp(0, frames.length - 1);
    final safeEnd = (endIndex ?? frames.length - 1).clamp(
      safeStart,
      frames.length - 1,
    );
    if (safeStart == safeEnd) {
      return frameAt(safeStart);
    }

    final startElapsed = frameAt(safeStart).elapsedDuration;
    final endElapsed = frameAt(safeEnd).elapsedDuration;
    final clampedElapsed = Duration(
      milliseconds: elapsed.inMilliseconds.clamp(
        startElapsed.inMilliseconds,
        endElapsed.inMilliseconds,
      ),
    );
    final targetEpochMs = frames.first.timestamp.millisecondsSinceEpoch +
        clampedElapsed.inMilliseconds;

    final upperIndex = _firstIndexAtOrAfterEpochMilliseconds(targetEpochMs)
        .clamp(safeStart, safeEnd);
    if (upperIndex <= safeStart) {
      return frameAt(safeStart);
    }
    if (upperIndex >= safeEnd &&
        frameAt(safeEnd).timestamp.millisecondsSinceEpoch <= targetEpochMs) {
      return frameAt(safeEnd);
    }

    final lowerIndex = max(safeStart, upperIndex - 1);
    final lowerFrame = frameAt(lowerIndex);
    final upperFrame = frameAt(upperIndex);
    final lowerEpochMs = lowerFrame.timestamp.millisecondsSinceEpoch;
    final upperEpochMs = upperFrame.timestamp.millisecondsSinceEpoch;
    if (upperEpochMs <= lowerEpochMs) {
      return upperFrame;
    }

    final t =
        ((targetEpochMs - lowerEpochMs) / (upperEpochMs - lowerEpochMs)).clamp(
      0.0,
      1.0,
    );
    return _interpolateFrame(lowerFrame, upperFrame, t);
  }

  int _nearestIndexForEpochMilliseconds(int targetEpochMs) {
    var low = 0;
    var high = frames.length - 1;

    while (low < high) {
      final middle = (low + high) ~/ 2;
      final middleEpochMs = frames[middle].timestamp.millisecondsSinceEpoch;
      if (middleEpochMs < targetEpochMs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }

    final candidate = low;
    final previous = max(0, candidate - 1);
    final candidateDiff =
        (frames[candidate].timestamp.millisecondsSinceEpoch - targetEpochMs)
            .abs();
    final previousDiff =
        (frames[previous].timestamp.millisecondsSinceEpoch - targetEpochMs)
            .abs();
    return previousDiff <= candidateDiff ? previous : candidate;
  }

  int _firstIndexAtOrAfterEpochMilliseconds(int targetEpochMs) {
    var low = 0;
    var high = frames.length - 1;

    while (low < high) {
      final middle = (low + high) ~/ 2;
      final middleEpochMs = frames[middle].timestamp.millisecondsSinceEpoch;
      if (middleEpochMs < targetEpochMs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }

    return low;
  }

  FlightReplayFrame _interpolateFrame(
    FlightReplayFrame from,
    FlightReplayFrame to,
    double t,
  ) {
    if (t <= 0) {
      return from;
    }
    if (t >= 1) {
      return to;
    }

    final timestampDeltaMs = to.timestamp.millisecondsSinceEpoch -
        from.timestamp.millisecondsSinceEpoch;
    final elapsedDeltaMs =
        to.elapsedDuration.inMilliseconds - from.elapsedDuration.inMilliseconds;

    return FlightReplayFrame(
      sourceIndex: t < 0.5 ? from.sourceIndex : to.sourceIndex,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        from.timestamp.millisecondsSinceEpoch + (timestampDeltaMs * t).round(),
      ),
      elapsedDuration: Duration(
        milliseconds:
            from.elapsedDuration.inMilliseconds + (elapsedDeltaMs * t).round(),
      ),
      latitude: _lerpDouble(from.latitude, to.latitude, t),
      longitude: _lerpDouble(from.longitude, to.longitude, t),
      altitudeMeters: _lerpDouble(from.altitudeMeters, to.altitudeMeters, t),
      displayAltitudeMeters:
          _lerpDouble(from.displayAltitudeMeters, to.displayAltitudeMeters, t),
      altitudeFromStartMeters: _lerpDouble(
        from.altitudeFromStartMeters,
        to.altitudeFromStartMeters,
        t,
      ),
      speedMps: _lerpDouble(from.speedMps, to.speedMps, t),
      heading: _interpolateBearing(from.heading, to.heading, t),
      verticalSpeedMps:
          _lerpDouble(from.verticalSpeedMps, to.verticalSpeedMps, t),
      cumulativeDistanceMeters: _lerpDouble(
        from.cumulativeDistanceMeters,
        to.cumulativeDistanceMeters,
        t,
      ),
      progress: _lerpDouble(from.progress, to.progress, t).clamp(0.0, 1.0),
    );
  }

  double _interpolateBearing(double from, double to, double t) {
    final delta = ((to - from + 540) % 360) - 180;
    return _normalizeBearing(from + (delta * t));
  }

  double _lerpDouble(double from, double to, double t) {
    return from + ((to - from) * t);
  }

  factory FlightReplayData.fromPoints(
    List<FlightTrackPoint> points, {
    int maxFrames = 1400,
  }) {
    final normalizedPoints = _normalizePoints(points);
    if (normalizedPoints.isEmpty) {
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

    final cumulativeDistances = _buildCumulativeDistances(normalizedPoints);
    final selectedIndices = _buildSelectedIndices(
      points: normalizedPoints,
      maxFrames: maxFrames,
    );
    final totalDuration = normalizedPoints.last.timestamp
        .difference(normalizedPoints.first.timestamp);
    final totalDistanceMeters =
        cumulativeDistances.isEmpty ? 0.0 : cumulativeDistances.last;
    final displayAltitudes = selectedIndices
        .map((sourceIndex) => _smoothAltitude(normalizedPoints, sourceIndex))
        .toList(growable: false);
    final startDisplayAltitude = displayAltitudes.isEmpty
        ? normalizedPoints.first.altitude
        : displayAltitudes.first;

    final frames = <FlightReplayFrame>[];
    final safeDurationMs = max(1, totalDuration.inMilliseconds);
    for (var selectedIndex = 0;
        selectedIndex < selectedIndices.length;
        selectedIndex++) {
      final sourceIndex = selectedIndices[selectedIndex];
      final point = normalizedPoints[sourceIndex];
      final elapsedDuration =
          point.timestamp.difference(normalizedPoints.first.timestamp);
      final displayAltitude = displayAltitudes[selectedIndex];
      final verticalSpeed = selectedIndex == 0
          ? 0.0
          : _resolveVerticalSpeed(
              previousAltitude: displayAltitudes[selectedIndex - 1],
              currentAltitude: displayAltitude,
              previousTimestamp:
                  normalizedPoints[selectedIndices[selectedIndex - 1]]
                      .timestamp,
              currentTimestamp: point.timestamp,
            );

      frames.add(
        FlightReplayFrame(
          sourceIndex: sourceIndex,
          timestamp: point.timestamp,
          elapsedDuration: elapsedDuration,
          latitude: point.latitude,
          longitude: point.longitude,
          altitudeMeters: point.altitude,
          displayAltitudeMeters: displayAltitude,
          altitudeFromStartMeters: displayAltitude - startDisplayAltitude,
          speedMps: _resolveSpeed(normalizedPoints, sourceIndex),
          heading: _resolveHeading(normalizedPoints, sourceIndex),
          verticalSpeedMps: verticalSpeed,
          cumulativeDistanceMeters: cumulativeDistances[sourceIndex],
          progress: totalDuration == Duration.zero
              ? (selectedIndices.length == 1
                  ? 0.0
                  : selectedIndex / (selectedIndices.length - 1))
              : (elapsedDuration.inMilliseconds / safeDurationMs)
                  .clamp(0.0, 1.0),
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

  static List<FlightTrackPoint> _normalizePoints(
      List<FlightTrackPoint> points) {
    if (points.isEmpty) {
      return const [];
    }

    final ordered = List<FlightTrackPoint>.from(points)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final normalized = <FlightTrackPoint>[];
    for (final point in ordered) {
      if (normalized.isEmpty) {
        normalized.add(point);
        continue;
      }

      final previous = normalized.last;
      final sameTimestamp =
          point.timestamp.isAtSameMomentAs(previous.timestamp);
      final samePosition =
          (point.latitude - previous.latitude).abs() < 0.000001 &&
              (point.longitude - previous.longitude).abs() < 0.000001;
      final sameAltitude = (point.altitude - previous.altitude).abs() < 0.5;

      if (sameTimestamp && samePosition && sameAltitude) {
        normalized[normalized.length - 1] = point;
        continue;
      }

      if (sameTimestamp) {
        normalized[normalized.length - 1] = point;
        continue;
      }

      normalized.add(point);
    }
    return normalized;
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

    final totalDuration =
        points.last.timestamp.difference(points.first.timestamp);
    final totalMs = max(1, totalDuration.inMilliseconds);
    final selected = <int>{0, points.length - 1, _highestAltitudeIndex(points)};
    var cursor = 0;

    for (var sampleIndex = 0; sampleIndex < maxFrames; sampleIndex++) {
      final targetMs = (sampleIndex * totalMs / (maxFrames - 1)).round();
      while (cursor < points.length - 1) {
        final cursorMs = points[cursor]
            .timestamp
            .difference(points.first.timestamp)
            .inMilliseconds;
        if (cursorMs >= targetMs) {
          break;
        }
        cursor += 1;
      }

      final previousIndex = max(0, cursor - 1);
      final previousMs = points[previousIndex]
          .timestamp
          .difference(points.first.timestamp)
          .inMilliseconds;
      final currentMs = points[cursor]
          .timestamp
          .difference(points.first.timestamp)
          .inMilliseconds;
      final chosen =
          (targetMs - previousMs).abs() <= (currentMs - targetMs).abs()
              ? previousIndex
              : cursor;
      selected.add(chosen);
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
