import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/app_models.dart';
import 'korea_flight_guide.dart';
import 'live_weather_service.dart';

enum ImportedParaglidingSiteType {
  takeoff,
  landing,
  practice,
  site,
}

extension ImportedParaglidingSiteTypeLabel on ImportedParaglidingSiteType {
  String get label => switch (this) {
        ImportedParaglidingSiteType.takeoff => '이륙장',
        ImportedParaglidingSiteType.landing => '착륙장',
        ImportedParaglidingSiteType.practice => '연습장',
        ImportedParaglidingSiteType.site => '활공장',
      };
}

enum ImportedSiteDataQualityLevel { rich, moderate, limited }

extension ImportedSiteDataQualityLevelLabel on ImportedSiteDataQualityLevel {
  String get label => switch (this) {
        ImportedSiteDataQualityLevel.rich => '정보 충분',
        ImportedSiteDataQualityLevel.moderate => '기본 정보 있음',
        ImportedSiteDataQualityLevel.limited => '정보 보완 필요',
      };
}

class ImportedSiteDataQuality {
  const ImportedSiteDataQuality({
    required this.score,
    required this.level,
    required this.missingFields,
  });

  final int score;
  final ImportedSiteDataQualityLevel level;
  final List<String> missingFields;

  String get label => level.label;

  String get summaryText {
    if (missingFields.isEmpty) {
      return '좌표, 대표 풍향, 설명, 주의 메모가 비교적 잘 정리된 사이트입니다.';
    }
    return '참고 정보가 부족한 항목: ${missingFields.join(' · ')}';
  }
}

class ImportedParaglidingSite {
  const ImportedParaglidingSite({
    required this.sourceId,
    required this.order,
    required this.name,
    required this.regionHint,
    required this.latitude,
    required this.longitude,
    required this.siteType,
    required this.summaryLine,
    required this.descriptionText,
    this.windNote,
    this.imageUrl,
    this.windguruUrl,
    this.windyUrl,
    this.kmaForecastUrl,
    this.awsObservationUrl,
    this.stationLabel,
    this.folderName,
    this.styleId,
  });

  final String sourceId;
  final int order;
  final String name;
  final String regionHint;
  final double latitude;
  final double longitude;
  final ImportedParaglidingSiteType siteType;
  final String summaryLine;
  final String descriptionText;
  final String? windNote;
  final String? imageUrl;
  final String? windguruUrl;
  final String? windyUrl;
  final String? kmaForecastUrl;
  final String? awsObservationUrl;
  final String? stationLabel;
  final String? folderName;
  final String? styleId;

  factory ImportedParaglidingSite.fromJson(Map<String, dynamic> json) {
    return ImportedParaglidingSite(
      sourceId: json['source_id'] as String,
      order: json['order'] as int,
      name: json['name'] as String,
      regionHint: json['region_hint'] as String? ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      siteType: _siteTypeFromString(json['site_type'] as String? ?? ''),
      summaryLine: json['summary_line'] as String? ?? '',
      descriptionText: json['description_text'] as String? ?? '',
      windNote: json['wind_note'] as String?,
      imageUrl: json['image_url'] as String?,
      windguruUrl: json['windguru_url'] as String?,
      windyUrl: json['windy_url'] as String?,
      kmaForecastUrl: json['kma_forecast_url'] as String?,
      awsObservationUrl: json['aws_observation_url'] as String?,
      stationLabel: json['station_label'] as String?,
      folderName: json['folder_name'] as String?,
      styleId: json['style_id'] as String?,
    );
  }

  String get regionLabel =>
      regionHint.trim().isEmpty ? '지역 정보 보강 예정' : regionHint.trim();

  String get siteTypeLabel => siteType.label;

  bool get hasCoordinate =>
      latitude.isFinite &&
      longitude.isFinite &&
      (latitude.abs() > 0.01 || longitude.abs() > 0.01);

  bool get hasPreferredWindInfo => (windNote?.trim().isNotEmpty ?? false);

  bool get hasAllowedWindInfo =>
      _parseDirectionRange(windNote?.trim() ?? '') != null;

  bool get hasDescriptionInfo => descriptionText.trim().isNotEmpty;

  bool get hasCautionNoteInfo => summaryLine.trim().isNotEmpty;

  ImportedSiteDataQuality get dataQuality {
    var score = 0;
    final missingFields = <String>[];

    if (hasCoordinate) {
      score += 30;
    } else {
      missingFields.add('좌표 미등록');
    }

    if (hasPreferredWindInfo) {
      score += 20;
    } else {
      missingFields.add('대표 풍향 정보 없음');
    }

    if (hasAllowedWindInfo) {
      score += 20;
    } else {
      missingFields.add('허용 풍향 정보 없음');
    }

    if (hasDescriptionInfo) {
      score += 15;
    } else {
      missingFields.add('설명 미등록');
    }

    if (hasCautionNoteInfo) {
      score += 15;
    } else {
      missingFields.add('주의 메모 미등록');
    }

    final level = score >= 80
        ? ImportedSiteDataQualityLevel.rich
        : score >= 55
            ? ImportedSiteDataQualityLevel.moderate
            : ImportedSiteDataQualityLevel.limited;

    return ImportedSiteDataQuality(
      score: score,
      level: level,
      missingFields: missingFields,
    );
  }

  String get preferredWindLabel {
    final note = windNote?.trim();
    if (note == null || note.isEmpty) {
      return '대표 풍향 정보 없음';
    }
    return note;
  }

  KoreaFlightSiteMetadata toGuideMetadata() {
    return KoreaFlightSiteMetadata(
      siteId: -(order + 1),
      name: name,
      region: regionLabel,
      latitude: latitude,
      longitude: longitude,
      flyableRadiusMeters: 3200,
      cautionRadiusMeters: 6800,
      note: summaryLine.isNotEmpty ? summaryLine : '$name 기준 참고 반경입니다.',
      safetyText:
          '대한패러글라이딩협회 참고 활공장 좌표 기준 정보입니다. 정확한 비행 가능 여부는 현장 브리핑과 공역 정보를 추가 확인해 주세요.',
    );
  }

  SiteDetail toSiteDetail({
    required LiveWeatherSnapshot weather,
    required List<LiveWeatherForecastItem> forecast,
  }) {
    final siteSummary = toSiteSummary(weather: weather, forecast: forecast);
    final allowedRange = preferredWindLabel;
    return SiteDetail(
      site: siteSummary,
      description: descriptionText.trim().isEmpty
          ? '$name 현장 설명이 아직 정리되지 않았습니다.'
          : descriptionText.trim(),
      takeoffAltitudeM: 0,
      landingAltitudeM: 0,
      allowedDirectionRange: allowedRange,
      rule: _buildSiteRule(allowedRange),
    );
  }

  SiteSummary toSiteSummary({
    required LiveWeatherSnapshot weather,
    required List<LiveWeatherForecastItem> forecast,
  }) {
    final weatherSnapshot =
        _buildWeatherSnapshot(weather: weather, forecast: forecast);
    final assessment = _buildAssessment(weather: weather, forecast: forecast);
    return SiteSummary(
      id: -(order + 1),
      name: name,
      region: regionLabel,
      difficulty: 'intermediate',
      shortDescription: summaryLine.trim().isEmpty
          ? '$regionLabel $siteTypeLabel'
          : summaryLine.trim(),
      beginnerAllowed: assessment.status != FlightStatus.bad,
      weather: weatherSnapshot,
      assessment: assessment,
    );
  }

  WeatherSnapshot _buildWeatherSnapshot({
    required LiveWeatherSnapshot weather,
    required List<LiveWeatherForecastItem> forecast,
  }) {
    final hourly = forecast.take(8).map((item) {
      return HourlyForecast(
        timeLabel: _formatHourLabel(item.time),
        averageWindSpeed: item.windSpeedMps ?? weather.windSpeedMps ?? 0,
        windDirection: item.windDirection,
        gustSpeed:
            item.gustSpeedMps ?? item.windSpeedMps ?? weather.windSpeedMps ?? 0,
        precipitationMm: item.precipitationMm,
      );
    }).toList(growable: false);

    final firstForecast = forecast.isEmpty ? null : forecast.first;
    return WeatherSnapshot(
      observedAt: weather.observedAt,
      averageWindSpeed:
          weather.windSpeedMps ?? firstForecast?.windSpeedMps ?? 0,
      windDirection: weather.windDirection ?? firstForecast?.windDirection ?? 0,
      gustSpeed: firstForecast?.gustSpeedMps ??
          firstForecast?.windSpeedMps ??
          weather.windSpeedMps ??
          0,
      precipitationMm: firstForecast?.precipitationMm,
      summary: weather.summary,
      hourlyForecast: hourly,
    );
  }

  Assessment _buildAssessment({
    required LiveWeatherSnapshot weather,
    required List<LiveWeatherForecastItem> forecast,
  }) {
    final currentWind =
        weather.windSpeedMps ?? forecast.firstOrNull?.windSpeedMps ?? 0;
    final currentGust = forecast.firstOrNull?.gustSpeedMps ?? currentWind;
    final currentPrecipitation = forecast.firstOrNull?.precipitationMm ?? 0;
    final directionInfo = _parseDirectionRange(preferredWindLabel);
    final directionOk = weather.windDirection == null || directionInfo == null
        ? null
        : _isDirectionInRange(
            weather.windDirection!, directionInfo.$1, directionInfo.$2);

    final reasons = <String>[];
    FlightStatus status;
    int score;

    if (currentPrecipitation >= 1.0 || currentGust >= 10.0) {
      status = FlightStatus.bad;
      score = 42;
      if (currentPrecipitation >= 1.0) {
        reasons.add('강수 가능성이 높습니다.');
      }
      if (currentGust >= 10.0) {
        reasons.add('돌풍이 강합니다.');
      }
    } else if (currentWind >= 6.5 ||
        currentGust >= 8.0 ||
        directionOk == false) {
      status = FlightStatus.caution;
      score = 64;
      if (currentWind >= 6.5) {
        reasons.add('바람이 강한 편입니다.');
      }
      if (currentGust >= 8.0) {
        reasons.add('돌풍 변화가 큽니다.');
      }
      if (directionOk == false) {
        reasons.add('현재 풍향이 대표 풍향과 다를 수 있습니다.');
      }
    } else {
      status = FlightStatus.good;
      score = 84;
      reasons.add('현재 풍속과 돌풍이 비교적 안정적으로 보입니다.');
      if (directionOk == true) {
        reasons.add('현재 풍향이 대표 풍향 범위와 가깝습니다.');
      }
    }

    if (directionInfo == null) {
      reasons.add('대표 풍향 정보는 참고용 메모를 기준으로 했습니다.');
    }

    return Assessment(
      score: score,
      status: status,
      reasons: reasons,
      summaryText: switch (status) {
        FlightStatus.good => '현재 조건은 참고상 비행 가능 범위에 가깝습니다.',
        FlightStatus.caution => '현재 조건은 한 번 더 보수적으로 확인하는 편이 좋습니다.',
        FlightStatus.bad => '현재 조건은 제한 가능성을 염두에 두고 추가 확인이 필요합니다.',
      },
    );
  }

  SiteRule _buildSiteRule(String allowedRange) {
    final directionInfo = _parseDirectionRange(allowedRange);
    final note = windNote?.trim();
    return SiteRule(
      notes: note == null || note.isEmpty
          ? '대표 풍향 정보가 부족해 현장 판단이 더 중요합니다.'
          : '대표 풍향 메모: $note',
      allowedDirectionStart: directionInfo?.$1 ?? 0,
      allowedDirectionEnd: directionInfo?.$2 ?? 359,
      beginnerAllowed: true,
      maxGust: 8,
      maxGustDifference: 3,
    );
  }
}

class ImportedParaglidingSiteCatalog {
  ImportedParaglidingSiteCatalog._();

  static List<ImportedParaglidingSite>? _cache;

  static Future<List<ImportedParaglidingSite>> load() async {
    final cached = _cache;
    if (cached != null) {
      return cached;
    }

    final raw =
        await rootBundle.loadString('assets/data/kmz_paragliding_sites.json');
    final jsonList = jsonDecode(raw) as List<dynamic>;
    final items = jsonList
        .map((item) =>
            ImportedParaglidingSite.fromJson(item as Map<String, dynamic>))
        .toList(growable: false)
      ..sort((left, right) => left.order.compareTo(right.order));
    _cache = items;
    return items;
  }

  static Future<ImportedParaglidingSite?> findBySourceId(
      String sourceId) async {
    final items = await load();
    for (final item in items) {
      if (item.sourceId == sourceId) {
        return item;
      }
    }
    return null;
  }

  static Future<List<ImportedParaglidingSite>> search(String query) async {
    final items = await load();
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return items;
    }
    return items.where((item) {
      return item.name.contains(normalized) ||
          item.regionHint.contains(normalized) ||
          (item.windNote?.contains(normalized) ?? false);
    }).toList(growable: false);
  }
}

ImportedParaglidingSiteType _siteTypeFromString(String value) =>
    switch (value) {
      'takeoff' => ImportedParaglidingSiteType.takeoff,
      'landing' => ImportedParaglidingSiteType.landing,
      'practice' => ImportedParaglidingSiteType.practice,
      _ => ImportedParaglidingSiteType.site,
    };

String _formatHourLabel(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:00';

(int, int)? _parseDirectionRange(String text) {
  final tokens = _extractDirectionTokens(text);
  if (tokens.isEmpty) {
    return null;
  }
  final degrees = tokens.map(_directionToDegree).toList(growable: false);
  if (degrees.length == 1) {
    final center = degrees.first;
    return (
      ((center - 35) % 360 + 360) % 360,
      ((center + 35) % 360 + 360) % 360
    );
  }

  var bestStart = degrees.first;
  var bestEnd = degrees.first;
  var bestWidth = 361;

  for (final pivot in degrees) {
    final rotated = degrees
        .map((degree) => ((degree - pivot) % 360 + 360) % 360)
        .toList(growable: false)
      ..sort();
    final width = rotated.last - rotated.first;
    if (width < bestWidth) {
      bestWidth = width;
      bestStart = (pivot + rotated.first) % 360;
      bestEnd = (pivot + rotated.last) % 360;
    }
  }

  return (bestStart, bestEnd);
}

List<String> _extractDirectionTokens(String text) {
  const orderedTokens = [
    '북북동',
    '동북동',
    '동남동',
    '남남동',
    '남남서',
    '서남서',
    '서북서',
    '북북서',
    '북동',
    '남동',
    '남서',
    '북서',
    '북풍',
    '동풍',
    '남풍',
    '서풍',
    '북',
    '동',
    '남',
    '서',
  ];

  final normalized = text.replaceAll('풍향', '').replaceAll(' ', '');
  final matches = <String>[];
  for (final token in orderedTokens) {
    if (normalized.contains(token) && !matches.contains(token)) {
      matches.add(token);
    }
  }
  return matches;
}

int _directionToDegree(String token) => switch (token) {
      '북' || '북풍' => 0,
      '북북동' => 22,
      '북동' => 45,
      '동북동' => 67,
      '동' || '동풍' => 90,
      '동남동' => 112,
      '남동' => 135,
      '남남동' => 157,
      '남' || '남풍' => 180,
      '남남서' => 202,
      '남서' => 225,
      '서남서' => 247,
      '서' || '서풍' => 270,
      '서북서' => 292,
      '북서' => 315,
      '북북서' => 337,
      _ => 0,
    };

bool _isDirectionInRange(int direction, int start, int end) {
  final normalized = ((direction % 360) + 360) % 360;
  final normalizedStart = ((start % 360) + 360) % 360;
  final normalizedEnd = ((end % 360) + 360) % 360;
  if (normalizedStart <= normalizedEnd) {
    return normalized >= normalizedStart && normalized <= normalizedEnd;
  }
  return normalized >= normalizedStart || normalized <= normalizedEnd;
}

extension _ListFirstOrNullExtension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
