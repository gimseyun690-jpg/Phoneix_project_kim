import 'dart:convert';

import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

import '../models/app_models.dart';

class LiveWeatherSnapshot {
  const LiveWeatherSnapshot({
    required this.observedAt,
    required this.summary,
    required this.sourceLabel,
    this.temperatureCelsius,
    this.windSpeedMps,
    this.windDirection,
    this.weatherCode,
    this.isFallback = false,
  });

  final DateTime observedAt;
  final double? temperatureCelsius;
  final double? windSpeedMps;
  final int? windDirection;
  final int? weatherCode;
  final String summary;
  final String sourceLabel;
  final bool isFallback;
}

class LiveWeatherForecastItem {
  const LiveWeatherForecastItem({
    required this.time,
    this.temperatureCelsius,
    this.windSpeedMps,
    this.windDirection = 0,
    this.gustSpeedMps,
    this.precipitationMm,
    this.weatherCode,
    this.summaryText,
    this.isFallback = false,
  });

  final DateTime time;
  final double? temperatureCelsius;
  final double? windSpeedMps;
  final int windDirection;
  final double? gustSpeedMps;
  final double? precipitationMm;
  final int? weatherCode;
  final String? summaryText;
  final bool isFallback;
}

class LiveWeatherDailyForecastItem {
  const LiveWeatherDailyForecastItem({
    required this.date,
    this.minTemperatureCelsius,
    this.maxTemperatureCelsius,
    this.windSpeedMps,
    this.windDirection,
    this.gustSpeedMps,
    this.precipitationMm,
    this.precipitationProbability,
    this.weatherCode,
    this.summaryText,
    this.isFallback = false,
  });

  final DateTime date;
  final double? minTemperatureCelsius;
  final double? maxTemperatureCelsius;
  final double? windSpeedMps;
  final int? windDirection;
  final double? gustSpeedMps;
  final double? precipitationMm;
  final int? precipitationProbability;
  final int? weatherCode;
  final String? summaryText;
  final bool isFallback;
}

enum WeatherInterpretationSeverity { info, caution, warning }

class WeatherInterpretationAlert {
  const WeatherInterpretationAlert({
    required this.label,
    required this.description,
    required this.severity,
  });

  final String label;
  final String description;
  final WeatherInterpretationSeverity severity;
}

class LiveWeatherService {
  LiveWeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<LiveWeatherSnapshot> getCurrentWeather({
    required double latitude,
    required double longitude,
    SiteSummary? selectedSite,
  }) async {
    final fallbackWeather = selectedSite?.weather;
    final fallbackSummary = fallbackWeather?.summary.trim();

    try {
      final uri = Uri.https(
        'api.open-meteo.com',
        '/v1/forecast',
        {
          'latitude': latitude.toStringAsFixed(6),
          'longitude': longitude.toStringAsFixed(6),
          'current_weather': 'true',
          'timezone': 'Asia/Seoul',
          'wind_speed_unit': 'ms',
        },
      );
      final response = await _client.get(uri);
      if (response.statusCode < 400) {
        final json =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final currentWeather = json['current_weather'] as Map<String, dynamic>?;
        final temperature =
            (currentWeather?['temperature'] as num?)?.toDouble();
        final windSpeed = (currentWeather?['windspeed'] as num?)?.toDouble();
        final weatherCode = (currentWeather?['weathercode'] as num?)?.toInt();
        final observedAt = DateTime.tryParse(
              currentWeather?['time'] as String? ?? '',
            )?.toLocal() ??
            DateTime.now();

        return LiveWeatherSnapshot(
          observedAt: observedAt,
          temperatureCelsius: temperature,
          windSpeedMps: windSpeed ?? fallbackWeather?.averageWindSpeed,
          windDirection: (currentWeather?['winddirection'] as num?)?.toInt() ??
              fallbackWeather?.windDirection,
          weatherCode: weatherCode,
          summary: fallbackSummary?.isNotEmpty == true
              ? fallbackSummary!
              : _weatherCodeLabel(weatherCode),
          sourceLabel:
              selectedSite == null ? '좌표 기준 실황' : '좌표 기준 실황 + 등록 비행장 참고',
        );
      }
    } catch (_) {
      // 비행 중 화면에서는 조용한 fallback이 더 안전하다.
    }

    return LiveWeatherSnapshot(
      observedAt: fallbackWeather?.observedAt ?? DateTime.now(),
      temperatureCelsius: null,
      windSpeedMps: fallbackWeather?.averageWindSpeed,
      windDirection: fallbackWeather?.windDirection,
      weatherCode: null,
      summary: fallbackSummary?.isNotEmpty == true
          ? fallbackSummary!
          : '현재 좌표 기준 날씨 정보를 아직 불러오지 못했습니다.',
      sourceLabel: selectedSite == null ? '좌표 기준 실황 준비 중' : '등록 비행장 참고',
      isFallback: true,
    );
  }

  Future<List<LiveWeatherForecastItem>> getShortTermForecast({
    required double latitude,
    required double longitude,
    SiteSummary? selectedSite,
    int count = 6,
  }) async {
    try {
      final uri = Uri.https(
        'api.open-meteo.com',
        '/v1/forecast',
        {
          'latitude': latitude.toStringAsFixed(6),
          'longitude': longitude.toStringAsFixed(6),
          'hourly':
              'temperature_2m,wind_speed_10m,wind_direction_10m,wind_gusts_10m,precipitation,weathercode',
          'forecast_days': '2',
          'timezone': 'Asia/Seoul',
          'wind_speed_unit': 'ms',
        },
      );
      final response = await _client.get(uri);
      if (response.statusCode < 400) {
        final json =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final hourly = json['hourly'] as Map<String, dynamic>?;
        final times = (hourly?['time'] as List<dynamic>? ?? const [])
            .map((item) => DateTime.tryParse(item as String)?.toLocal())
            .toList();
        final temperatures =
            (hourly?['temperature_2m'] as List<dynamic>? ?? const [])
                .map((item) => (item as num?)?.toDouble())
                .toList();
        final windSpeeds =
            (hourly?['wind_speed_10m'] as List<dynamic>? ?? const [])
                .map((item) => (item as num?)?.toDouble())
                .toList();
        final windDirections =
            (hourly?['wind_direction_10m'] as List<dynamic>? ?? const [])
                .map((item) => (item as num?)?.toInt())
                .toList();
        final gustSpeeds =
            (hourly?['wind_gusts_10m'] as List<dynamic>? ?? const [])
                .map((item) => (item as num?)?.toDouble())
                .toList();
        final precipitations =
            (hourly?['precipitation'] as List<dynamic>? ?? const [])
                .map((item) => (item as num?)?.toDouble())
                .toList();
        final weatherCodes =
            (hourly?['weathercode'] as List<dynamic>? ?? const [])
                .map((item) => (item as num?)?.toInt())
                .toList();

        final now = DateTime.now();
        final result = <LiveWeatherForecastItem>[];
        for (var index = 0; index < times.length; index += 1) {
          final time = times[index];
          if (time == null ||
              time.isBefore(now.subtract(const Duration(hours: 1)))) {
            continue;
          }

          result.add(
            LiveWeatherForecastItem(
              time: time,
              temperatureCelsius:
                  index < temperatures.length ? temperatures[index] : null,
              windSpeedMps:
                  index < windSpeeds.length ? windSpeeds[index] : null,
              windDirection: index < windDirections.length
                  ? (windDirections[index] ?? 0)
                  : 0,
              gustSpeedMps:
                  index < gustSpeeds.length ? gustSpeeds[index] : null,
              precipitationMm:
                  index < precipitations.length ? precipitations[index] : null,
              weatherCode:
                  index < weatherCodes.length ? weatherCodes[index] : null,
              summaryText: _buildForecastSummary(
                windSpeedMps:
                    index < windSpeeds.length ? windSpeeds[index] : null,
                gustSpeedMps:
                    index < gustSpeeds.length ? gustSpeeds[index] : null,
                precipitationMm: index < precipitations.length
                    ? precipitations[index]
                    : null,
                weatherCode:
                    index < weatherCodes.length ? weatherCodes[index] : null,
              ),
            ),
          );

          if (result.length >= count) {
            break;
          }
        }

        if (result.isNotEmpty) {
          return result;
        }
      }
    } catch (_) {
      // 패널은 fallback 예보를 보여준다.
    }

    final fallbackItems = selectedSite?.weather.hourlyForecast ?? const [];
    return fallbackItems.take(count).map((item) {
      final parsedTime = DateTime.tryParse(
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')} ${item.timeLabel}:00');
      return LiveWeatherForecastItem(
        time: parsedTime ?? DateTime.now(),
        temperatureCelsius: null,
        windSpeedMps: item.averageWindSpeed,
        windDirection: item.windDirection,
        gustSpeedMps: item.gustSpeed,
        precipitationMm: item.precipitationMm,
        weatherCode: null,
        summaryText: _buildForecastSummary(
          windSpeedMps: item.averageWindSpeed,
          gustSpeedMps: item.gustSpeed,
          precipitationMm: item.precipitationMm,
          weatherCode: null,
        ),
        isFallback: true,
      );
    }).toList();
  }

  Future<List<LiveWeatherDailyForecastItem>> getExtendedForecast({
    required double latitude,
    required double longitude,
    SiteSummary? selectedSite,
    int days = 16,
  }) async {
    final forecastDays = days < 1 ? 1 : (days > 16 ? 16 : days);

    try {
      final uri = Uri.https(
        'api.open-meteo.com',
        '/v1/forecast',
        {
          'latitude': latitude.toStringAsFixed(6),
          'longitude': longitude.toStringAsFixed(6),
          'daily':
              'weather_code,temperature_2m_min,temperature_2m_max,wind_speed_10m_max,wind_gusts_10m_max,wind_direction_10m_dominant,precipitation_sum,precipitation_probability_max',
          'forecast_days': '$forecastDays',
          'timezone': 'Asia/Seoul',
          'wind_speed_unit': 'ms',
        },
      );
      final response = await _client.get(uri);
      if (response.statusCode < 400) {
        final json =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final daily = json['daily'] as Map<String, dynamic>?;
        final times = (daily?['time'] as List<dynamic>? ?? const [])
            .map((item) => DateTime.tryParse('${item as String}T00:00'))
            .toList();
        final minTemperatures =
            (daily?['temperature_2m_min'] as List<dynamic>? ?? const [])
                .map((item) => (item as num?)?.toDouble())
                .toList();
        final maxTemperatures =
            (daily?['temperature_2m_max'] as List<dynamic>? ?? const [])
                .map((item) => (item as num?)?.toDouble())
                .toList();
        final windSpeeds =
            (daily?['wind_speed_10m_max'] as List<dynamic>? ?? const [])
                .map((item) => (item as num?)?.toDouble())
                .toList();
        final gustSpeeds =
            (daily?['wind_gusts_10m_max'] as List<dynamic>? ?? const [])
                .map((item) => (item as num?)?.toDouble())
                .toList();
        final windDirections =
            (daily?['wind_direction_10m_dominant'] as List<dynamic>? ??
                    const [])
                .map((item) => (item as num?)?.toInt())
                .toList();
        final precipitations =
            (daily?['precipitation_sum'] as List<dynamic>? ?? const [])
                .map((item) => (item as num?)?.toDouble())
                .toList();
        final precipitationProbabilities =
            (daily?['precipitation_probability_max'] as List<dynamic>? ??
                    const [])
                .map((item) => (item as num?)?.toInt())
                .toList();
        final weatherCodes =
            (daily?['weather_code'] as List<dynamic>? ?? const [])
                .map((item) => (item as num?)?.toInt())
                .toList();

        final result = <LiveWeatherDailyForecastItem>[];
        for (var index = 0; index < times.length; index += 1) {
          final time = times[index];
          if (time == null) {
            continue;
          }

          result.add(
            LiveWeatherDailyForecastItem(
              date: time,
              minTemperatureCelsius: index < minTemperatures.length
                  ? minTemperatures[index]
                  : null,
              maxTemperatureCelsius: index < maxTemperatures.length
                  ? maxTemperatures[index]
                  : null,
              windSpeedMps:
                  index < windSpeeds.length ? windSpeeds[index] : null,
              windDirection:
                  index < windDirections.length ? windDirections[index] : null,
              gustSpeedMps:
                  index < gustSpeeds.length ? gustSpeeds[index] : null,
              precipitationMm:
                  index < precipitations.length ? precipitations[index] : null,
              precipitationProbability:
                  index < precipitationProbabilities.length
                      ? precipitationProbabilities[index]
                      : null,
              weatherCode:
                  index < weatherCodes.length ? weatherCodes[index] : null,
              summaryText: _buildDailyForecastSummary(
                windSpeedMps:
                    index < windSpeeds.length ? windSpeeds[index] : null,
                gustSpeedMps:
                    index < gustSpeeds.length ? gustSpeeds[index] : null,
                precipitationMm: index < precipitations.length
                    ? precipitations[index]
                    : null,
                precipitationProbability:
                    index < precipitationProbabilities.length
                        ? precipitationProbabilities[index]
                        : null,
                weatherCode:
                    index < weatherCodes.length ? weatherCodes[index] : null,
              ),
            ),
          );
        }

        if (result.isNotEmpty) {
          return result;
        }
      }
    } catch (_) {
      // 장기 예보도 연결이 실패하면 등록 비행장 기준 fallback을 사용한다.
    }

    return _buildFallbackDailyForecast(selectedSite, forecastDays);
  }

  String _buildForecastSummary({
    required double? windSpeedMps,
    required double? gustSpeedMps,
    required double? precipitationMm,
    required int? weatherCode,
  }) {
    if ((precipitationMm ?? 0) >= 1.0) {
      return '강수 가능성 높음';
    }
    if (weatherCode != null) {
      final label = _weatherCodeLabel(weatherCode);
      if (label != '날씨 정보 준비 중') {
        if ((gustSpeedMps ?? 0) >= 8.0) {
          return '$label · 돌풍 주의';
        }
        if ((windSpeedMps ?? 0) >= 6.0) {
          return '$label · 바람 강함';
        }
        return label;
      }
    }
    if ((gustSpeedMps ?? 0) >= 8.0) {
      return '돌풍 주의';
    }
    if ((windSpeedMps ?? 0) >= 6.0) {
      return '바람 강함';
    }
    if ((windSpeedMps ?? 0) <= 2.0) {
      return '바람 약함';
    }
    return '비행 참고 가능';
  }

  String _buildDailyForecastSummary({
    required double? windSpeedMps,
    required double? gustSpeedMps,
    required double? precipitationMm,
    required int? precipitationProbability,
    required int? weatherCode,
  }) {
    if ((precipitationProbability ?? 0) >= 70 || (precipitationMm ?? 0) >= 5) {
      return '강수 가능성 높음';
    }
    if ((gustSpeedMps ?? 0) >= 10) {
      return '돌풍 주의';
    }
    return _buildForecastSummary(
      windSpeedMps: windSpeedMps,
      gustSpeedMps: gustSpeedMps,
      precipitationMm: precipitationMm,
      weatherCode: weatherCode,
    );
  }

  List<LiveWeatherDailyForecastItem> _buildFallbackDailyForecast(
    SiteSummary? selectedSite,
    int days,
  ) {
    if (selectedSite == null) {
      return const [];
    }

    final observedAt = selectedSite.weather.observedAt;
    final hourlyItems = selectedSite.weather.hourlyForecast;
    if (hourlyItems.isEmpty) {
      return [
        LiveWeatherDailyForecastItem(
          date: DateTime(observedAt.year, observedAt.month, observedAt.day),
          windSpeedMps: selectedSite.weather.averageWindSpeed,
          windDirection: selectedSite.weather.windDirection,
          gustSpeedMps: selectedSite.weather.gustSpeed,
          precipitationMm: selectedSite.weather.precipitationMm,
          weatherCode: null,
          summaryText: selectedSite.weather.summary,
          isFallback: true,
        ),
      ];
    }

    final grouped = <DateTime, List<HourlyForecast>>{};
    var currentDate =
        DateTime(observedAt.year, observedAt.month, observedAt.day);
    int? previousHour;

    for (final item in hourlyItems) {
      final hour = _parseFallbackHour(item.timeLabel) ??
          (((previousHour ?? observedAt.hour) + 3) % 24);
      if (previousHour != null && hour < previousHour) {
        currentDate = currentDate.add(const Duration(days: 1));
      }
      previousHour = hour;
      final dayKey =
          DateTime(currentDate.year, currentDate.month, currentDate.day);
      grouped.putIfAbsent(dayKey, () => <HourlyForecast>[]).add(item);
    }

    return grouped.entries.take(days).map((entry) {
      final items = entry.value;
      final maxWind = items.fold<double>(
        0,
        (current, item) =>
            item.averageWindSpeed > current ? item.averageWindSpeed : current,
      );
      final maxGust = items.fold<double>(
        0,
        (current, item) => item.gustSpeed > current ? item.gustSpeed : current,
      );
      final precipitation = items.fold<double>(
        0,
        (current, item) => current + (item.precipitationMm ?? 0),
      );

      return LiveWeatherDailyForecastItem(
        date: entry.key,
        windSpeedMps: maxWind,
        windDirection: items.first.windDirection,
        gustSpeedMps: maxGust,
        precipitationMm: precipitation == 0 ? null : precipitation,
        weatherCode: null,
        summaryText: _buildDailyForecastSummary(
          windSpeedMps: maxWind,
          gustSpeedMps: maxGust,
          precipitationMm: precipitation == 0 ? null : precipitation,
          precipitationProbability: null,
          weatherCode: null,
        ),
        isFallback: true,
      );
    }).toList(growable: false);
  }

  List<WeatherInterpretationAlert> buildOperationalAlerts({
    required LiveWeatherSnapshot weather,
    required List<LiveWeatherForecastItem> forecast,
    LiveWeatherForecastItem? selectedForecast,
  }) {
    final alerts = <WeatherInterpretationAlert>[];
    final focus = selectedForecast ?? forecast.firstOrNull;
    final gust = focus?.gustSpeedMps ?? weather.windSpeedMps ?? 0;
    final precipitation = focus?.precipitationMm ?? 0;
    final shift = windDirectionShiftDegrees(forecast);

    if (gust >= 10) {
      alerts.add(
        const WeatherInterpretationAlert(
          label: '돌풍 주의',
          description: '순간 돌풍이 강할 수 있어 이륙 전 바람 편차를 한 번 더 확인하는 편이 좋습니다.',
          severity: WeatherInterpretationSeverity.warning,
        ),
      );
    } else if (gust >= 8) {
      alerts.add(
        const WeatherInterpretationAlert(
          label: '돌풍 가능성',
          description: '돌풍 편차가 다소 커질 수 있어 출동 전 현장 바람을 다시 보는 편이 좋습니다.',
          severity: WeatherInterpretationSeverity.caution,
        ),
      );
    }

    if (precipitation >= 1.0) {
      alerts.add(
        const WeatherInterpretationAlert(
          label: '강수 가능성 있음',
          description: '시간대별 강수 예보가 있어 실제 출동 전 최신 예보와 현장 상황을 함께 확인해 주세요.',
          severity: WeatherInterpretationSeverity.warning,
        ),
      );
    } else if (precipitation > 0) {
      alerts.add(
        const WeatherInterpretationAlert(
          label: '약한 강수 가능성',
          description: '강수량은 크지 않지만 시간대에 따라 변화가 있을 수 있습니다.',
          severity: WeatherInterpretationSeverity.caution,
        ),
      );
    }

    if (shift >= 110) {
      alerts.add(
        WeatherInterpretationAlert(
          label: '풍향 변화 큼',
          description:
              '앞 시간대 예보에서 풍향이 약 ${shift.round()}도 정도 크게 바뀌어 바람 방향 변화를 보수적으로 확인하는 편이 좋습니다.',
          severity: WeatherInterpretationSeverity.warning,
        ),
      );
    } else if (shift >= 70) {
      alerts.add(
        WeatherInterpretationAlert(
          label: '풍향 변화 주의',
          description:
              '짧은 시간 안에 풍향이 약 ${shift.round()}도 정도 바뀔 수 있어 시간대별 흐름을 함께 보시는 편이 좋습니다.',
          severity: WeatherInterpretationSeverity.caution,
        ),
      );
    }

    if (alerts.isEmpty) {
      alerts.add(
        const WeatherInterpretationAlert(
          label: '큰 경고 없음',
          description:
              '현재 수치상으로는 눈에 띄는 돌풍·강수 경고가 크지 않지만, 출동 전 현장 브리핑은 별도로 확인해 주세요.',
          severity: WeatherInterpretationSeverity.info,
        ),
      );
    }

    return alerts;
  }

  double windDirectionShiftDegrees(List<LiveWeatherForecastItem> forecast) {
    final directions = forecast
        .take(4)
        .map((item) => item.windDirection)
        .where((item) => item >= 0)
        .toList(growable: false);
    if (directions.length < 2) {
      return 0;
    }

    var maxShift = 0.0;
    for (var index = 1; index < directions.length; index += 1) {
      final shift = _directionGap(directions[index - 1], directions[index]);
      if (shift > maxShift) {
        maxShift = shift;
      }
    }
    return maxShift;
  }

  String shortTermConfidenceLabel(DateTime targetTime) {
    final hoursAhead = targetTime.difference(DateTime.now()).inHours;
    if (hoursAhead <= 6) {
      return '단기 예보 신뢰도 높음';
    }
    if (hoursAhead <= 18) {
      return '예보 신뢰도 보통';
    }
    return '시간대 예보 참고용';
  }

  String shortTermConfidenceDescription(DateTime targetTime) {
    final hoursAhead = targetTime.difference(DateTime.now()).inHours;
    if (hoursAhead <= 6) {
      return '가까운 시간대 예보라 변동 폭이 비교적 작지만, 현장 바람과 이륙장 상태는 따로 확인해 주세요.';
    }
    if (hoursAhead <= 18) {
      return '오늘 안쪽 예보는 흐름을 보기 좋지만 시간대에 따라 풍향과 돌풍이 바뀔 수 있습니다.';
    }
    return '먼 시간대 예보는 흐름 참고용으로 보고, 실제 출동 전에는 더 가까운 예보로 다시 판단하는 편이 좋습니다.';
  }

  int? _parseFallbackHour(String label) {
    final match = RegExp(r'(\d{1,2})').firstMatch(label);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1)!);
  }

  String _weatherCodeLabel(int? code) => switch (code) {
        0 => '맑음',
        1 || 2 => '대체로 맑음',
        3 => '흐림',
        45 || 48 => '안개',
        51 || 53 || 55 => '이슬비',
        56 || 57 => '어는 이슬비',
        61 || 63 || 65 => '비',
        66 || 67 => '어는 비',
        71 || 73 || 75 || 77 => '눈',
        80 || 81 || 82 => '소나기',
        85 || 86 => '눈 소나기',
        95 => '뇌우',
        96 || 99 => '강한 뇌우',
        _ => '날씨 정보 준비 중',
      };

  Future<String?> resolveAreaLabel({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      );
      if (placemarks.isEmpty) {
        return null;
      }

      final placemark = placemarks.first;
      final parts = <String>[];

      void addPart(String? value) {
        final trimmed = value?.trim() ?? '';
        if (trimmed.isEmpty || parts.contains(trimmed)) {
          return;
        }
        parts.add(trimmed);
      }

      addPart(placemark.administrativeArea);
      addPart(placemark.locality);
      addPart(placemark.subLocality);
      addPart(placemark.thoroughfare);

      if (parts.isEmpty) {
        return null;
      }

      return parts.take(3).join(' ');
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}

double _directionGap(int left, int right) {
  final raw = (left - right).abs().toDouble();
  return raw > 180 ? 360 - raw : raw;
}
