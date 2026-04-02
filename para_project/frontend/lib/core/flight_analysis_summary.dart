import 'dart:math';

import 'package:geolocator/geolocator.dart';

import '../models/app_models.dart';
import 'utils.dart';

enum FlightAnalysisMomentType {
  start,
  highestAltitude,
  highestSpeed,
  end,
}

extension FlightAnalysisMomentTypeLabel on FlightAnalysisMomentType {
  String get label => switch (this) {
        FlightAnalysisMomentType.start => '시작',
        FlightAnalysisMomentType.highestAltitude => '최고 고도',
        FlightAnalysisMomentType.highestSpeed => '최고 속도',
        FlightAnalysisMomentType.end => '종료',
      };
}

class FlightAnalysisMoment {
  const FlightAnalysisMoment({
    required this.type,
    required this.point,
    required this.title,
    required this.subtitle,
  });

  final FlightAnalysisMomentType type;
  final FlightTrackPoint point;
  final String title;
  final String subtitle;
}

class FlightAnalysisSample {
  const FlightAnalysisSample({
    required this.time,
    required this.altitudeMeters,
    required this.speedMps,
    required this.progress,
  });

  final DateTime time;
  final double altitudeMeters;
  final double speedMps;
  final double progress;
}

class FlightAnalysisInsight {
  const FlightAnalysisInsight({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;
}

class FlightAnalysisSummary {
  const FlightAnalysisSummary({
    required this.averageAltitudeMeters,
    required this.averageAccuracyMeters,
    required this.maxClimbRateMps,
    required this.maxSinkRateMps,
    required this.totalAltitudeGainMeters,
    required this.totalAltitudeLossMeters,
    required this.longestSegmentMeters,
    required this.highestPoint,
    required this.fastestPoint,
    required this.startPoint,
    required this.endPoint,
    required this.timelineSamples,
    required this.keyMoments,
    required this.insights,
    required this.overview,
    required this.qualityNote,
  });

  final double averageAltitudeMeters;
  final double? averageAccuracyMeters;
  final double maxClimbRateMps;
  final double maxSinkRateMps;
  final double totalAltitudeGainMeters;
  final double totalAltitudeLossMeters;
  final double longestSegmentMeters;
  final FlightTrackPoint? highestPoint;
  final FlightTrackPoint? fastestPoint;
  final FlightTrackPoint? startPoint;
  final FlightTrackPoint? endPoint;
  final List<FlightAnalysisSample> timelineSamples;
  final List<FlightAnalysisMoment> keyMoments;
  final List<FlightAnalysisInsight> insights;
  final String overview;
  final String qualityNote;

  factory FlightAnalysisSummary.fromDetail(FlightSessionDetail detail) {
    final session = detail.session;
    final points = List<FlightTrackPoint>.from(detail.points)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final resolvedDuration = detail.resolvedDuration;
    if (points.isEmpty) {
      return FlightAnalysisSummary(
        averageAltitudeMeters: session.maxAltitudeMeters,
        averageAccuracyMeters: session.lastAccuracyMeters,
        maxClimbRateMps: 0,
        maxSinkRateMps: 0,
        totalAltitudeGainMeters: 0,
        totalAltitudeLossMeters: 0,
        longestSegmentMeters: 0,
        highestPoint: null,
        fastestPoint: null,
        startPoint: null,
        endPoint: null,
        timelineSamples: const [],
        keyMoments: const [],
        insights: const [
          FlightAnalysisInsight(
            title: '기록 샘플 부족',
            description: '분석에 필요한 위치 샘플이 충분하지 않아 요약만 표시합니다.',
          ),
        ],
        overview:
            '${formatDuration(resolvedDuration)} 동안 비행을 기록했습니다. 경로 샘플이 적어 상세 분석은 참고용으로만 표시됩니다.',
        qualityNote: '기록 샘플이 적어 고도와 속도 흐름 해석은 제한적입니다.',
      );
    }

    final startPoint = points.first;
    final endPoint = points.last;
    FlightTrackPoint highestPoint = startPoint;
    FlightTrackPoint fastestPoint = startPoint;
    double altitudeSum = 0;
    double accuracySum = 0;
    var accuracyCount = 0;
    var maxClimbRate = 0.0;
    var maxSinkRate = 0.0;
    var totalGain = 0.0;
    var totalLoss = 0.0;
    var longestSegment = 0.0;
    var fastestSpeed = _resolveSpeed(points, 0);

    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      altitudeSum += point.altitude;
      final accuracy = point.accuracy;
      if (accuracy != null && accuracy.isFinite && accuracy >= 0) {
        accuracySum += accuracy;
        accuracyCount += 1;
      }

      if (point.altitude > highestPoint.altitude) {
        highestPoint = point;
      }

      final speed = _resolveSpeed(points, index);
      if (speed >= fastestSpeed) {
        fastestSpeed = speed;
        fastestPoint = point;
      }

      if (index == 0) {
        continue;
      }

      final previous = points[index - 1];
      final seconds =
          max(1, point.timestamp.difference(previous.timestamp).inSeconds);
      final altitudeDelta = point.altitude - previous.altitude;
      final rate = altitudeDelta / seconds;
      if (rate > maxClimbRate) {
        maxClimbRate = rate;
      }
      if (rate < maxSinkRate) {
        maxSinkRate = rate;
      }

      if (altitudeDelta > 0) {
        totalGain += altitudeDelta;
      } else {
        totalLoss += altitudeDelta.abs();
      }

      final distance = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        point.latitude,
        point.longitude,
      );
      if (distance > longestSegment) {
        longestSegment = distance;
      }
    }

    final averageAltitude = altitudeSum / points.length;
    final averageAccuracy =
        accuracyCount == 0 ? null : accuracySum / accuracyCount;
    final samples = _buildTimelineSamples(points);
    final keyMoments = _buildKeyMoments(
      points: points,
      highestPoint: highestPoint,
      fastestPoint: fastestPoint,
      fastestSpeed: fastestSpeed,
    );
    final qualityNote = _buildQualityNote(
      averageAccuracyMeters: averageAccuracy,
      pointCount: points.length,
    );
    final overview = _buildOverview(
      session: session,
      resolvedDuration: resolvedDuration,
      highestPoint: highestPoint,
      totalAltitudeGainMeters: totalGain,
      maxClimbRateMps: maxClimbRate,
    );
    final insights = _buildInsights(
      session: session,
      highestPoint: highestPoint,
      fastestPoint: fastestPoint,
      fastestSpeed: fastestSpeed,
      maxClimbRateMps: maxClimbRate,
      maxSinkRateMps: maxSinkRate,
      qualityNote: qualityNote,
    );

    return FlightAnalysisSummary(
      averageAltitudeMeters: averageAltitude,
      averageAccuracyMeters: averageAccuracy,
      maxClimbRateMps: maxClimbRate,
      maxSinkRateMps: maxSinkRate,
      totalAltitudeGainMeters: totalGain,
      totalAltitudeLossMeters: totalLoss,
      longestSegmentMeters: longestSegment,
      highestPoint: highestPoint,
      fastestPoint: fastestPoint,
      startPoint: startPoint,
      endPoint: endPoint,
      timelineSamples: samples,
      keyMoments: keyMoments,
      insights: insights,
      overview: overview,
      qualityNote: qualityNote,
    );
  }

  static List<FlightAnalysisSample> _buildTimelineSamples(
    List<FlightTrackPoint> points,
  ) {
    if (points.length <= 18) {
      return [
        for (var index = 0; index < points.length; index++)
          FlightAnalysisSample(
            time: points[index].timestamp,
            altitudeMeters: points[index].altitude,
            speedMps: _resolveSpeed(points, index),
            progress: points.length == 1 ? 0 : index / (points.length - 1),
          ),
      ];
    }

    final result = <FlightAnalysisSample>[];
    const desiredCount = 18;
    for (var sampleIndex = 0; sampleIndex < desiredCount; sampleIndex++) {
      final rawIndex =
          (sampleIndex * (points.length - 1) / (desiredCount - 1)).round();
      final point = points[rawIndex];
      result.add(
        FlightAnalysisSample(
          time: point.timestamp,
          altitudeMeters: point.altitude,
          speedMps: _resolveSpeed(points, rawIndex),
          progress: sampleIndex / (desiredCount - 1),
        ),
      );
    }
    return result;
  }

  static List<FlightAnalysisMoment> _buildKeyMoments({
    required List<FlightTrackPoint> points,
    required FlightTrackPoint highestPoint,
    required FlightTrackPoint fastestPoint,
    required double fastestSpeed,
  }) {
    final moments = <FlightAnalysisMoment>[
      FlightAnalysisMoment(
        type: FlightAnalysisMomentType.start,
        point: points.first,
        title: '비행 시작',
        subtitle: formatTime(points.first.timestamp),
      ),
      FlightAnalysisMoment(
        type: FlightAnalysisMomentType.highestAltitude,
        point: highestPoint,
        title: '최고 고도',
        subtitle:
            '${formatAltitudeMeters(highestPoint.altitude)} · ${formatTime(highestPoint.timestamp)}',
      ),
      FlightAnalysisMoment(
        type: FlightAnalysisMomentType.highestSpeed,
        point: fastestPoint,
        title: '최고 속도',
        subtitle:
            '${formatSpeedKmh(fastestSpeed)} · ${formatTime(fastestPoint.timestamp)}',
      ),
    ];

    if (points.length > 1) {
      moments.add(
        FlightAnalysisMoment(
          type: FlightAnalysisMomentType.end,
          point: points.last,
          title: '비행 종료',
          subtitle: formatTime(points.last.timestamp),
        ),
      );
    }

    return moments;
  }

  static String _buildOverview({
    required FlightSession session,
    required Duration resolvedDuration,
    required FlightTrackPoint highestPoint,
    required double totalAltitudeGainMeters,
    required double maxClimbRateMps,
  }) {
    final buffer = StringBuffer(
      '${formatDuration(resolvedDuration)} 동안 ${formatDistanceMeters(session.totalDistanceMeters)} 이동했고 최고 ${formatAltitudeMeters(highestPoint.altitude)}까지 도달했습니다.',
    );

    if (totalAltitudeGainMeters >= 120) {
      buffer.write(
        ' 누적 상승 고도는 ${formatAltitudeMeters(totalAltitudeGainMeters)} 정도로 기록됐습니다.',
      );
    }

    if (maxClimbRateMps >= 1.5) {
      buffer.write(
        ' 가장 강한 상승은 ${formatTime(highestPoint.timestamp)} 전후에 나타났습니다.',
      );
    }

    return buffer.toString();
  }

  static String _buildQualityNote({
    required double? averageAccuracyMeters,
    required int pointCount,
  }) {
    if (pointCount < 6) {
      return '기록 샘플 수가 적어 이동 흐름 해석은 참고용으로 보는 편이 좋습니다.';
    }
    if (averageAccuracyMeters == null) {
      return 'GPS 정확도 정보가 부족해 일부 경로 해석은 제한적입니다.';
    }
    if (averageAccuracyMeters <= 10) {
      return 'GPS 정확도가 안정적인 편이라 경로 해석 신뢰도가 비교적 높습니다.';
    }
    if (averageAccuracyMeters <= 25) {
      return 'GPS 정확도는 보통 수준으로, 세밀한 회전 구간은 참고용으로 확인해 주세요.';
    }
    return 'GPS 흔들림 가능성이 있어 일부 경로와 속도 변화는 참고용으로 보는 편이 안전합니다.';
  }

  static List<FlightAnalysisInsight> _buildInsights({
    required FlightSession session,
    required FlightTrackPoint highestPoint,
    required FlightTrackPoint fastestPoint,
    required double fastestSpeed,
    required double maxClimbRateMps,
    required double maxSinkRateMps,
    required String qualityNote,
  }) {
    return [
      FlightAnalysisInsight(
        title: '최고 고도 시점',
        description:
            '${formatTime(highestPoint.timestamp)}에 ${formatAltitudeMeters(highestPoint.altitude)}까지 상승했습니다.',
      ),
      FlightAnalysisInsight(
        title: '가장 빠른 구간',
        description:
            '${formatTime(fastestPoint.timestamp)} 전후에 ${formatSpeedKmh(fastestSpeed)}로 가장 빠르게 이동했습니다.',
      ),
      FlightAnalysisInsight(
        title: '상승·하강 흐름',
        description:
            '최대 상승률은 ${formatVerticalSpeed(maxClimbRateMps)}, 최대 하강률은 ${formatVerticalSpeed(maxSinkRateMps)}로 기록됐습니다.',
      ),
      FlightAnalysisInsight(
        title: '기록 품질 참고',
        description: qualityNote,
      ),
      if (session.memo.trim().isNotEmpty)
        FlightAnalysisInsight(
          title: '파일럿 메모',
          description: session.memo.trim(),
        ),
    ];
  }

  static double _resolveSpeed(List<FlightTrackPoint> points, int index) {
    final point = points[index];
    final directSpeed = point.speed;
    if (directSpeed != null && directSpeed.isFinite && directSpeed >= 0) {
      return directSpeed;
    }
    if (index == 0) {
      return 0;
    }
    final previous = points[index - 1];
    final seconds =
        max(1, point.timestamp.difference(previous.timestamp).inSeconds);
    final distance = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      point.latitude,
      point.longitude,
    );
    return distance / seconds;
  }
}
