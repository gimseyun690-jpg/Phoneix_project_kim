import '../models/app_models.dart';
import 'korea_flight_guide.dart';
import 'live_weather_service.dart';

class KoreaSiteMapSnapshot {
  const KoreaSiteMapSnapshot({
    required this.site,
    required this.metadata,
    required this.weather,
    required this.advisory,
  });

  final SiteSummary site;
  final KoreaFlightSiteMetadata metadata;
  final LiveWeatherSnapshot weather;
  final KoreaZoneAdvisory advisory;
}

class KoreaAreaWeatherSnapshot {
  const KoreaAreaWeatherSnapshot({
    required this.latitude,
    required this.longitude,
    required this.areaLabel,
    required this.weather,
    this.nearbySite,
  });

  final double latitude;
  final double longitude;
  final String areaLabel;
  final LiveWeatherSnapshot weather;
  final KoreaSiteMapSnapshot? nearbySite;
}

class KoreaWeatherMapService {
  KoreaWeatherMapService({LiveWeatherService? liveWeatherService})
      : _liveWeatherService = liveWeatherService ?? LiveWeatherService();

  final LiveWeatherService _liveWeatherService;
  final KoreaFlightGuide _flightGuide = const KoreaFlightGuide();
  final Map<String, _CachedSiteWeather> _siteWeatherCache = {};
  final Map<String, _CachedAreaWeather> _areaWeatherCache = {};
  final Map<String, _CachedForecast> _forecastCache = {};

  Future<List<KoreaSiteMapSnapshot>> loadSiteSnapshots(
    List<SiteSummary> sites, {
    bool forceRefresh = false,
  }) async {
    final futures = <Future<KoreaSiteMapSnapshot>>[];
    for (final site in sites) {
      final metadata = _flightGuide.metadataForSite(
        siteId: site.id,
        siteName: site.name,
      );
      if (metadata == null) {
        continue;
      }
      futures.add(
        _buildSiteSnapshot(site, metadata, forceRefresh: forceRefresh),
      );
    }
    return Future.wait(futures);
  }

  Future<KoreaAreaWeatherSnapshot> loadAreaWeather({
    required double latitude,
    required double longitude,
    required List<KoreaSiteMapSnapshot> siteSnapshots,
    bool forceRefresh = false,
  }) async {
    final cacheKey =
        '${latitude.toStringAsFixed(2)}:${longitude.toStringAsFixed(2)}';
    final cached = _areaWeatherCache[cacheKey];
    final now = DateTime.now();
    if (!forceRefresh &&
        cached != null &&
        now.difference(cached.cachedAt) < const Duration(minutes: 5)) {
      return cached.snapshot;
    }

    KoreaSiteMapSnapshot? nearbySite;
    double? nearestDistance;
    for (final snapshot in siteSnapshots) {
      final advisory = _flightGuide.assess(
        latitude: latitude,
        longitude: longitude,
        selectedSite: snapshot.site,
      );
      final distance = advisory.distanceMeters;
      if (distance == null) {
        continue;
      }
      if (nearestDistance == null || distance < nearestDistance) {
        nearestDistance = distance;
        nearbySite = snapshot;
      }
    }

    final weather = await _liveWeatherService.getCurrentWeather(
      latitude: latitude,
      longitude: longitude,
      selectedSite: nearbySite?.site,
    );
    final areaLabel = await _liveWeatherService.resolveAreaLabel(
          latitude: latitude,
          longitude: longitude,
        ) ??
        '지도 중심 지역';

    final snapshot = KoreaAreaWeatherSnapshot(
      latitude: latitude,
      longitude: longitude,
      areaLabel: areaLabel,
      weather: weather,
      nearbySite: nearbySite,
    );
    _areaWeatherCache[cacheKey] = _CachedAreaWeather(
      cachedAt: now,
      snapshot: snapshot,
    );
    return snapshot;
  }

  Future<List<LiveWeatherForecastItem>> loadShortTermForecast({
    required double latitude,
    required double longitude,
    SiteSummary? selectedSite,
    bool forceRefresh = false,
    int count = 6,
  }) async {
    final cacheKey =
        '${latitude.toStringAsFixed(3)}:${longitude.toStringAsFixed(3)}:${selectedSite?.id ?? 0}:$count';
    final cached = _forecastCache[cacheKey];
    final now = DateTime.now();
    if (!forceRefresh &&
        cached != null &&
        now.difference(cached.cachedAt) < const Duration(minutes: 10)) {
      return cached.items;
    }

    final items = await _liveWeatherService.getShortTermForecast(
      latitude: latitude,
      longitude: longitude,
      selectedSite: selectedSite,
      count: count,
    );
    _forecastCache[cacheKey] = _CachedForecast(
      cachedAt: now,
      items: items,
    );
    return items;
  }

  Future<KoreaSiteMapSnapshot> _buildSiteSnapshot(
    SiteSummary site,
    KoreaFlightSiteMetadata metadata, {
    bool forceRefresh = false,
  }) async {
    final cached = _siteWeatherCache[site.id.toString()];
    final now = DateTime.now();
    LiveWeatherSnapshot weather;
    if (!forceRefresh &&
        cached != null &&
        now.difference(cached.cachedAt) < const Duration(minutes: 10)) {
      weather = cached.weather;
    } else {
      weather = await _liveWeatherService.getCurrentWeather(
        latitude: metadata.latitude,
        longitude: metadata.longitude,
        selectedSite: site,
      );
      _siteWeatherCache[site.id.toString()] = _CachedSiteWeather(
        cachedAt: now,
        weather: weather,
      );
    }

    return KoreaSiteMapSnapshot(
      site: site,
      metadata: metadata,
      weather: weather,
      advisory: _buildSiteAdvisory(site, metadata),
    );
  }

  KoreaZoneAdvisory _buildSiteAdvisory(
    SiteSummary site,
    KoreaFlightSiteMetadata metadata,
  ) {
    final status = switch (site.assessment.status) {
      FlightStatus.good => KoreaZoneStatus.flyable,
      FlightStatus.caution => KoreaZoneStatus.caution,
      FlightStatus.bad => KoreaZoneStatus.confirmationRequired,
    };

    final summary = switch (status) {
      KoreaZoneStatus.flyable => '${site.name} 기준 현재 비행 가능한 참고 상태입니다.',
      KoreaZoneStatus.caution => '${site.name} 기준 현재 주의가 필요한 참고 상태입니다.',
      KoreaZoneStatus.confirmationRequired =>
        '${site.name} 기준 현재 추가 확인이 필요한 상태입니다.',
      KoreaZoneStatus.potentiallyRestricted =>
        '${site.name} 기준 현재 제한 가능성을 배제하기 어렵습니다.',
    };

    return KoreaZoneAdvisory(
      status: status,
      confidence: KoreaZoneConfidence.curated,
      title: '비행 참고 상태',
      summary: summary,
      detail:
          '${site.assessment.summaryText} ${metadata.safetyText} 정확한 공역 정보는 추가 확인이 필요합니다.',
      disclaimer: '등록 비행장 기준 참고 정보입니다.',
      nearbySite: metadata,
      distanceMeters: 0,
    );
  }

  void dispose() {
    _liveWeatherService.dispose();
  }

  void clearCache() {
    _siteWeatherCache.clear();
    _areaWeatherCache.clear();
    _forecastCache.clear();
  }
}

class _CachedSiteWeather {
  const _CachedSiteWeather({
    required this.cachedAt,
    required this.weather,
  });

  final DateTime cachedAt;
  final LiveWeatherSnapshot weather;
}

class _CachedAreaWeather {
  const _CachedAreaWeather({
    required this.cachedAt,
    required this.snapshot,
  });

  final DateTime cachedAt;
  final KoreaAreaWeatherSnapshot snapshot;
}

class _CachedForecast {
  const _CachedForecast({
    required this.cachedAt,
    required this.items,
  });

  final DateTime cachedAt;
  final List<LiveWeatherForecastItem> items;
}
