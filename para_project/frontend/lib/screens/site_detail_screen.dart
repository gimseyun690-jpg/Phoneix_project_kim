import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../app.dart';
import '../core/korea_flight_guide.dart';
import '../core/kmz_site_catalog.dart';
import '../core/live_weather_service.dart';
import '../core/map_view_type.dart';
import '../models/app_models.dart';
import '../repositories/app_repository.dart';
import '../widgets/map_view_toggle.dart';

class SiteDetailScreen extends StatefulWidget {
  const SiteDetailScreen({
    super.key,
    required this.repository,
    this.siteId,
    this.importedSite,
    required this.pilotLevel,
  }) : assert(siteId != null || importedSite != null);

  final AppRepository repository;
  final int? siteId;
  final ImportedParaglidingSite? importedSite;
  final PilotLevel pilotLevel;

  @override
  State<SiteDetailScreen> createState() => _SiteDetailScreenState();
}

class _SiteDetailScreenState extends State<SiteDetailScreen>
    with WidgetsBindingObserver {
  final KoreaFlightGuide _flightGuide = const KoreaFlightGuide();
  final LiveWeatherService _weatherService = LiveWeatherService();
  final MapViewPreferenceStore _mapViewPreferenceStore =
      MapViewPreferenceStore();
  final MapController _mapController = MapController();

  _SiteDetailViewState? _state;
  bool _loading = true;
  bool _refreshing = false;
  String? _errorMessage;
  int _selectedForecastIndex = 0;
  int _selectedDailyForecastIndex = 0;
  ParaglidingMapViewType _mapViewType = ParaglidingMapViewType.satellite;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadMapViewType());
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _weatherService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_load(refresh: true));
    }
  }

  Future<void> _loadMapViewType() async {
    final loaded = await _mapViewPreferenceStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _mapViewType = loaded;
    });
  }

  Future<void> _changeMapViewType(ParaglidingMapViewType type) async {
    if (_mapViewType == type) {
      return;
    }
    setState(() {
      _mapViewType = type;
    });
    await _mapViewPreferenceStore.save(type);
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _refreshing = true;
        _errorMessage = null;
      });
    } else if (_state == null) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final positionFuture = _loadCurrentPositionIfAvailable();

      late final SiteDetail detail;
      late final KoreaFlightSiteMetadata? metadata;
      late final LiveWeatherSnapshot weather;
      late final List<LiveWeatherForecastItem> forecast;
      late final List<LiveWeatherDailyForecastItem> extendedForecast;

      if (widget.importedSite != null) {
        final importedSite = widget.importedSite!;
        metadata = importedSite.toGuideMetadata();
        final results = await Future.wait<Object>([
          _weatherService.getCurrentWeather(
            latitude: importedSite.latitude,
            longitude: importedSite.longitude,
          ),
          _weatherService.getShortTermForecast(
            latitude: importedSite.latitude,
            longitude: importedSite.longitude,
            count: 10,
          ),
          _weatherService.getExtendedForecast(
            latitude: importedSite.latitude,
            longitude: importedSite.longitude,
            days: 16,
          ),
        ]);
        weather = results[0] as LiveWeatherSnapshot;
        forecast = results[1] as List<LiveWeatherForecastItem>;
        extendedForecast = results[2] as List<LiveWeatherDailyForecastItem>;
        detail = importedSite.toSiteDetail(
          weather: weather,
          forecast: forecast,
        );
      } else {
        detail = await widget.repository.getSiteDetail(
          siteId: widget.siteId!,
          pilotLevel: widget.pilotLevel,
        );
        metadata = _flightGuide.metadataForSite(
          siteId: detail.site.id,
          siteName: detail.site.name,
        );

        if (metadata != null) {
          final results = await Future.wait<Object>([
            _weatherService.getCurrentWeather(
              latitude: metadata.latitude,
              longitude: metadata.longitude,
              selectedSite: detail.site,
            ),
            _weatherService.getShortTermForecast(
              latitude: metadata.latitude,
              longitude: metadata.longitude,
              selectedSite: detail.site,
              count: 10,
            ),
            _weatherService.getExtendedForecast(
              latitude: metadata.latitude,
              longitude: metadata.longitude,
              selectedSite: detail.site,
              days: 16,
            ),
          ]);
          weather = results[0] as LiveWeatherSnapshot;
          forecast = results[1] as List<LiveWeatherForecastItem>;
          extendedForecast = results[2] as List<LiveWeatherDailyForecastItem>;
        } else {
          weather = _fallbackWeather(detail.site);
          forecast = _fallbackForecast(detail.site);
          extendedForecast = _fallbackExtendedForecast(detail.site);
        }
      }

      final currentPosition = await positionFuture;
      final distanceMeters = currentPosition != null && metadata != null
          ? Geolocator.distanceBetween(
              currentPosition.latitude,
              currentPosition.longitude,
              metadata.latitude,
              metadata.longitude,
            )
          : null;

      if (!mounted) {
        return;
      }

      setState(() {
        _state = _SiteDetailViewState(
          detail: detail,
          metadata: metadata,
          weather: weather,
          forecast: forecast,
          extendedForecast: extendedForecast,
          currentPosition: currentPosition,
          distanceMeters: distanceMeters,
        );
        _loading = false;
        _refreshing = false;
        _errorMessage = null;
        _selectedForecastIndex = 0;
        _selectedDailyForecastIndex = 0;
      });
      _centerOnSite();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _refreshing = false;
        _errorMessage =
            _state == null ? '사이트 상세 정보를 불러오지 못했습니다.' : '최신 정보를 불러오지 못했습니다.';
      });
    }
  }

  Future<Position?> _loadCurrentPositionIfAvailable() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return null;
      }
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final lastKnown = await Geolocator.getLastKnownPosition();
      return lastKnown ??
          Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 6),
            ),
          );
    } catch (_) {
      return null;
    }
  }

  Future<void> _requestLocationComparison() async {
    final state = _state;
    if (state == null || state.metadata == null) {
      return;
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('위치 서비스가 꺼져 있습니다. 기기 설정에서 위치를 켜 주세요.'),
        ),
      );
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('위치 권한을 허용하면 현재 위치와 사이트 거리를 보여드립니다.'),
        ),
      );
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      final distanceMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        state.metadata!.latitude,
        state.metadata!.longitude,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _state = state.copyWith(
          currentPosition: position,
          distanceMeters: distanceMeters,
        );
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('현재 위치를 가져오지 못했습니다. 잠시 후 다시 시도해 주세요.'),
        ),
      );
    }
  }

  void _centerOnSite() {
    final metadata = _state?.metadata;
    if (metadata == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      try {
        _mapController.move(
          LatLng(metadata.latitude, metadata.longitude),
          11.4,
        );
      } catch (_) {}
    });
  }

  void _moveToCurrentLocation() {
    final position = _state?.currentPosition;
    if (position == null) {
      unawaited(_requestLocationComparison());
      return;
    }
    try {
      _mapController.move(
        LatLng(position.latitude, position.longitude),
        12.2,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _state == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFEAF1F5),
        appBar: AppBar(title: const Text('사이트 상세')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('사이트 지도와 예보를 불러오고 있습니다.'),
            ],
          ),
        ),
      );
    }

    final state = _state;
    if (state == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFEAF1F5),
        appBar: AppBar(title: const Text('사이트 상세')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _errorMessage ?? '사이트 상세 정보를 준비하지 못했습니다.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('다시 불러오기'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final tone = _toneFor(state.detail.site.assessment.status);
    final statusColor = _toneColor(tone);
    final selectedForecast = state.forecast.isEmpty
        ? null
        : state.forecast[_selectedForecastIndex.clamp(
            0,
            state.forecast.length - 1,
          )];
    final selectedDailyForecast = state.extendedForecast.isEmpty
        ? null
        : state.extendedForecast[_selectedDailyForecastIndex.clamp(
            0,
            state.extendedForecast.length - 1,
          )];

    return Scaffold(
      backgroundColor: const Color(0xFFEAF1F5),
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 438,
              backgroundColor: const Color(0xFF173845),
              foregroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              title: Text(
                state.detail.site.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  onPressed: _refreshing ? null : () => _load(refresh: true),
                  tooltip: '새로고침',
                  icon: _refreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: _buildMapHero(context, state, tone, statusColor),
              ),
            ),
            SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -24),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Column(
                    children: [
                      _buildForecastSection(
                          context, state, tone, statusColor, selectedForecast),
                      const SizedBox(height: 16),
                      _buildExtendedForecastSection(
                        context,
                        state,
                        selectedDailyForecast,
                      ),
                      const SizedBox(height: 16),
                      _buildWeatherSection(context, state),
                      const SizedBox(height: 16),
                      _buildStatusSection(context, state, tone, statusColor),
                      const SizedBox(height: 16),
                      _buildCommunitySection(context, state),
                      const SizedBox(height: 16),
                      _buildSiteInfoSection(context, state),
                      const SizedBox(height: 16),
                      _buildLocationSection(context, state),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapHero(
    BuildContext context,
    _SiteDetailViewState state,
    _DetailStatusTone tone,
    Color statusColor,
  ) {
    final metadata = state.metadata;
    final center = metadata == null
        ? const LatLng(36.35, 127.85)
        : LatLng(metadata.latitude, metadata.longitude);
    final current = state.currentPosition;

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: metadata == null ? 6.8 : 11.2,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            buildParaglidingTileLayer(_mapViewType),
            if (metadata != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: center,
                    useRadiusInMeter: true,
                    radius: metadata.cautionRadiusMeters,
                    color: statusColor.withValues(alpha: 0.10),
                    borderColor: statusColor.withValues(alpha: 0.34),
                    borderStrokeWidth: 1.4,
                  ),
                  CircleMarker(
                    point: center,
                    useRadiusInMeter: true,
                    radius: metadata.flyableRadiusMeters,
                    color: statusColor.withValues(alpha: 0.18),
                    borderColor: statusColor.withValues(alpha: 0.62),
                    borderStrokeWidth: 1.6,
                  ),
                ],
              ),
            if (metadata != null && current != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [
                      center,
                      LatLng(current.latitude, current.longitude),
                    ],
                    color: Colors.white.withValues(alpha: 0.75),
                    strokeWidth: 3.2,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (metadata != null)
                  Marker(
                    width: 72,
                    height: 72,
                    point: center,
                    child: _SiteMarker(color: statusColor),
                  ),
                if (current != null)
                  Marker(
                    width: 26,
                    height: 26,
                    point: LatLng(current.latitude, current.longitude),
                    child: const _CurrentLocationMarker(),
                  ),
              ],
            ),
            RichAttributionWidget(
              attributions: [
                buildParaglidingAttribution(_mapViewType),
              ],
            ),
          ],
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF10232B).withValues(alpha: 0.20),
                const Color(0xFF10232B).withValues(alpha: 0.06),
                const Color(0xFF0D2028).withValues(alpha: 0.84),
              ],
              stops: const [0, 0.38, 1],
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 82,
          left: 16,
          right: 154,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _OverlayChip(
                  icon: Icons.place_outlined, text: state.detail.site.region),
              _OverlayChip(icon: Icons.air_rounded, text: _toneLabel(tone)),
              _OverlayChip(
                icon: Icons.cloud_outlined,
                text: state.weather.isFallback ? '등록 비행장 기준' : '좌표 기준 실황',
              ),
            ],
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 82,
          right: 16,
          child: MapViewToggle(
            value: _mapViewType,
            onChanged: _changeMapViewType,
          ),
        ),
        Positioned(
          right: 16,
          bottom: 148,
          child: Column(
            children: [
              _MapActionButton(
                icon: Icons.push_pin_outlined,
                tooltip: '사이트 중심으로 보기',
                onTap: _centerOnSite,
              ),
              const SizedBox(height: 10),
              _MapActionButton(
                icon: Icons.my_location_rounded,
                tooltip: current == null ? '내 위치 확인' : '내 위치로 이동',
                onTap: _moveToCurrentLocation,
              ),
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: _buildHeroSummary(context, state, tone, statusColor),
        ),
      ],
    );
  }

  Widget _buildHeroSummary(
    BuildContext context,
    _SiteDetailViewState state,
    _DetailStatusTone tone,
    Color statusColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0E2430).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.detail.site.name,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      state.detail.site.region,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.88),
                          ),
                    ),
                  ],
                ),
              ),
              _StatusPill(
                  label: _toneLabel(tone), color: statusColor, dark: true),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatTemperature(state.weather.temperatureCelsius),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _bestSummaryText(state),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                        height: 1.45,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _HeroMetric(
                  label: '풍속', value: _formatSpeed(state.weather.windSpeedMps)),
              const SizedBox(width: 10),
              _HeroMetric(
                  label: '풍향',
                  value: _formatHeading(state.weather.windDirection)),
              const SizedBox(width: 10),
              _HeroMetric(
                  label: '관측', value: _formatClock(state.weather.observedAt)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildForecastSection(
    BuildContext context,
    _SiteDetailViewState state,
    _DetailStatusTone tone,
    Color statusColor,
    LiveWeatherForecastItem? selectedForecast,
  ) {
    final alerts = _weatherService.buildOperationalAlerts(
      weather: state.weather,
      forecast: state.forecast,
      selectedForecast: selectedForecast,
    );
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '시간대별 예보',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '짧은 시간 흐름을 훑어보며 바람과 강수 변화를 확인해 보세요.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF4C6672),
                          ),
                    ),
                  ],
                ),
              ),
              _StatusPill(label: _toneLabel(tone), color: statusColor),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: alerts
                .take(3)
                .map((item) => _WeatherAlertChip(alert: item))
                .toList(growable: false),
          ),
          const SizedBox(height: 14),
          if (state.forecast.isEmpty)
            const _InlineMessage(
              title: '예보 데이터가 아직 준비되지 않았습니다.',
              description: '현재는 등록된 비행장 기준 요약 정보만 먼저 보여주고 있습니다.',
            )
          else ...[
            SizedBox(
              height: 236,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: state.forecast.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = state.forecast[index];
                  return _ForecastTile(
                    item: item,
                    selected: index == _selectedForecastIndex,
                    onTap: () {
                      setState(() {
                        _selectedForecastIndex = index;
                      });
                    },
                  );
                },
              ),
            ),
            if (selectedForecast != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6FBFD),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_relativeLabel(selectedForecast.time)} · ${_formatClock(selectedForecast.time)} 기준',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _InfoBubble(
                            label: '기온',
                            value: _formatTemperature(
                                selectedForecast.temperatureCelsius)),
                        _InfoBubble(
                            label: '풍속',
                            value: _formatSpeed(selectedForecast.windSpeedMps)),
                        _InfoBubble(
                            label: '풍향',
                            value:
                                _formatHeading(selectedForecast.windDirection)),
                        _InfoBubble(
                            label: '돌풍',
                            value: _formatSpeed(selectedForecast.gustSpeedMps)),
                        _InfoBubble(
                            label: '강수',
                            value: _formatPrecipitation(
                                selectedForecast.precipitationMm)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      selectedForecast.summaryText ?? '짧은 시간 예보를 기준으로 참고해 주세요.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF3A5B68),
                          ),
                    ),
                    const SizedBox(height: 10),
                    _InlineMessage(
                      title: _weatherService.shortTermConfidenceLabel(
                        selectedForecast.time,
                      ),
                      description:
                          _weatherService.shortTermConfidenceDescription(
                        selectedForecast.time,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _InlineMessage(
                      title: '예보 기준',
                      description: _weatherBasisText(state),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildExtendedForecastSection(
    BuildContext context,
    _SiteDetailViewState state,
    LiveWeatherDailyForecastItem? selectedDailyForecast,
  ) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '주간 / 장기 예보',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '오늘 이후 흐름까지 함께 보면서 출동 여부를 보수적으로 판단해 보세요.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF4C6672),
                ),
          ),
          const SizedBox(height: 16),
          if (state.extendedForecast.isEmpty)
            const _InlineMessage(
              title: '장기 예보를 아직 불러오지 못했습니다.',
              description: '현재는 시간대별 예보와 실황 위주로 먼저 보여드리고 있습니다.',
            )
          else ...[
            SizedBox(
              height: 280,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: state.extendedForecast.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = state.extendedForecast[index];
                  return _DailyForecastTile(
                    item: item,
                    tone: _dailyToneFor(item, state.detail),
                    selected: index == _selectedDailyForecastIndex,
                    onTap: () {
                      setState(() {
                        _selectedDailyForecastIndex = index;
                      });
                    },
                  );
                },
              ),
            ),
            if (selectedDailyForecast != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6FBFD),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_longRangeLabel(selectedDailyForecast.date)} · ${_formatForecastDate(selectedDailyForecast.date)}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        _StatusPill(
                          label: _toneLabel(_dailyToneFor(
                              selectedDailyForecast, state.detail)),
                          color: _toneColor(_dailyToneFor(
                              selectedDailyForecast, state.detail)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _InfoBubble(
                          label: '기온',
                          value: _formatDailyTemperatureRange(
                            selectedDailyForecast.minTemperatureCelsius,
                            selectedDailyForecast.maxTemperatureCelsius,
                          ),
                        ),
                        _InfoBubble(
                          label: '풍속',
                          value:
                              _formatSpeed(selectedDailyForecast.windSpeedMps),
                        ),
                        _InfoBubble(
                          label: '풍향',
                          value: _formatHeading(
                              selectedDailyForecast.windDirection),
                        ),
                        _InfoBubble(
                          label: '돌풍',
                          value:
                              _formatSpeed(selectedDailyForecast.gustSpeedMps),
                        ),
                        _InfoBubble(
                          label: '강수',
                          value: _formatPrecipitation(
                            selectedDailyForecast.precipitationMm,
                          ),
                        ),
                        _InfoBubble(
                          label: '강수 확률',
                          value: _formatProbability(
                            selectedDailyForecast.precipitationProbability,
                          ),
                        ),
                        _InfoBubble(
                          label: '날씨',
                          value: _dailySummaryText(selectedDailyForecast),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _dailySummaryText(selectedDailyForecast),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF3A5B68),
                          ),
                    ),
                    const SizedBox(height: 10),
                    _InlineMessage(
                      title: _dailyConfidenceLabel(selectedDailyForecast.date),
                      description: _dailyConfidenceDescription(
                        selectedDailyForecast.date,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildWeatherSection(
      BuildContext context, _SiteDetailViewState state) {
    final alerts = _weatherService.buildOperationalAlerts(
      weather: state.weather,
      forecast: state.forecast,
    );
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F1F5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _weatherIconData(state.weather.weatherCode),
                  color: const Color(0xFF2B566D),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '현재 날씨와 바람',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const _ReferenceChip(label: '사이트 기준'),
              _ReferenceChip(
                label: state.currentPosition == null
                    ? '현재 위치 비교 전'
                    : '현재 위치와 거리 비교 가능',
              ),
              if (state.weather.isFallback)
                const _ReferenceChip(label: '일부 참고 정보 사용'),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricTile(
                  label: '현재 온도',
                  value: _formatTemperature(state.weather.temperatureCelsius),
                  highlight: true),
              _MetricTile(
                  label: '풍속', value: _formatSpeed(state.weather.windSpeedMps)),
              _MetricTile(
                  label: '풍향',
                  value: _formatHeading(state.weather.windDirection)),
              _MetricTile(
                  label: '돌풍',
                  value: _formatSpeed(state.detail.site.weather.gustSpeed)),
              _MetricTile(
                  label: '강수',
                  value: _formatPrecipitation(
                      state.detail.site.weather.precipitationMm)),
              _MetricTile(
                  label: '관측 시각',
                  value: _formatDateTime(state.weather.observedAt)),
            ],
          ),
          const SizedBox(height: 16),
          _InlineMessage(title: '요약 상태', description: _bestSummaryText(state)),
          const SizedBox(height: 10),
          _InlineMessage(title: '예보 기준', description: _weatherBasisText(state)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: alerts
                .take(3)
                .map((item) => _WeatherAlertChip(alert: item))
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSection(
    BuildContext context,
    _SiteDetailViewState state,
    _DetailStatusTone tone,
    Color statusColor,
  ) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '비행 참고 상태',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _toneLabel(tone),
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _toneSummary(tone),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF3B5D69),
                            height: 1.45,
                          ),
                    ),
                  ],
                ),
              ),
              _StatusPill(label: '참고용 판단', color: statusColor),
            ],
          ),
          const SizedBox(height: 16),
          _InlineMessage(title: '풍향 비교', description: _windGuideText(state)),
          const SizedBox(height: 10),
          _InlineMessage(title: '주의 메모', description: _warningText(state)),
          const SizedBox(height: 10),
          const _InlineMessage(
            title: '안전 안내',
            description: '정확한 비행 가능 여부는 현장 브리핑과 공역 정보를 추가 확인해 주세요.',
          ),
        ],
      ),
    );
  }

  Widget _buildSiteInfoSection(
      BuildContext context, _SiteDetailViewState state) {
    final isImportedSite = state.detail.site.id < 0;
    final importedQuality = widget.importedSite?.dataQuality;
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '사이트 정보',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoBubble(label: '지역', value: state.detail.site.region),
              _InfoBubble(
                  label: '허용 풍향', value: state.detail.allowedDirectionRange),
              if (state.detail.takeoffAltitudeM > 0 ||
                  state.detail.landingAltitudeM > 0)
                _InfoBubble(
                  label: '이륙/착륙',
                  value:
                      '${state.detail.takeoffAltitudeM}m · ${state.detail.landingAltitudeM}m',
                ),
              _InfoBubble(
                label: '난이도',
                value: _difficultyLabel(state.detail.site.difficulty),
              ),
              if (importedQuality != null)
                _InfoBubble(label: '정보 상태', value: importedQuality.label),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            state.detail.description,
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 16),
          _InlineMessage(
            title: isImportedSite ? '참고 정보 상태' : '비행장 기준 정보',
            description: importedQuality?.summaryText ??
                '${state.detail.site.shortDescription}\n관측 시각: ${_formatDateTime(state.weather.observedAt)}',
          ),
          if (importedQuality != null &&
              importedQuality.missingFields.isNotEmpty) ...[
            const SizedBox(height: 10),
            _InlineMessage(
              title: '보완 필요',
              description: importedQuality.missingFields.join(' · '),
            ),
          ],
          const SizedBox(height: 10),
          _InlineMessage(
            title: '예보 기준',
            description: _weatherBasisText(state),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunitySection(
      BuildContext context, _SiteDetailViewState state) {
    final siteName = state.detail.site.name;
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '이륙장 커뮤니티',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '$siteName 비행일지와 피드백을 같은 이륙장 흐름에서 바로 확인할 수 있습니다.',
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.siteCommunity,
                      arguments: SiteCommunityArgs(
                        siteId: widget.siteId,
                        siteName: siteName,
                      ),
                    );
                  },
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text('이륙장 피드 보기'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _refreshing ? null : () => _load(refresh: true),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('날씨 새로고침'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection(
      BuildContext context, _SiteDetailViewState state) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '현재 위치와 사이트 관계',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          Text(
            _locationRelationText(state),
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          if (state.currentPosition == null && state.metadata != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _requestLocationComparison,
              icon: const Icon(Icons.my_location_rounded),
              label: const Text('내 위치와 비교하기'),
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            _InlineMessage(
              title: '일부 정보가 최신 상태가 아닐 수 있습니다.',
              description: _errorMessage!,
            ),
          ],
        ],
      ),
    );
  }

  LiveWeatherSnapshot _fallbackWeather(SiteSummary site) {
    return LiveWeatherSnapshot(
      observedAt: site.weather.observedAt,
      temperatureCelsius: null,
      windSpeedMps: site.weather.averageWindSpeed,
      windDirection: site.weather.windDirection,
      summary: site.weather.summary,
      sourceLabel: '등록 비행장 기준 참고 정보',
      isFallback: true,
    );
  }

  List<LiveWeatherForecastItem> _fallbackForecast(SiteSummary site) {
    final now = DateTime.now();
    return site.weather.hourlyForecast
        .take(8)
        .toList()
        .asMap()
        .entries
        .map((entry) {
      final item = entry.value;
      final time = _parseForecastTime(item.timeLabel, now, entry.key);
      return LiveWeatherForecastItem(
        time: time,
        temperatureCelsius: null,
        windSpeedMps: item.averageWindSpeed,
        windDirection: item.windDirection,
        gustSpeedMps: item.gustSpeed,
        precipitationMm: item.precipitationMm,
        summaryText: _forecastSummary(
            item.averageWindSpeed, item.gustSpeed, item.precipitationMm),
        isFallback: true,
      );
    }).toList(growable: false);
  }

  List<LiveWeatherDailyForecastItem> _fallbackExtendedForecast(
      SiteSummary site) {
    final grouped = <DateTime, List<LiveWeatherForecastItem>>{};
    for (final item in _fallbackForecast(site)) {
      final key = DateTime(item.time.year, item.time.month, item.time.day);
      grouped.putIfAbsent(key, () => <LiveWeatherForecastItem>[]).add(item);
    }

    if (grouped.isEmpty) {
      return [
        LiveWeatherDailyForecastItem(
          date: DateTime(
            site.weather.observedAt.year,
            site.weather.observedAt.month,
            site.weather.observedAt.day,
          ),
          windSpeedMps: site.weather.averageWindSpeed,
          windDirection: site.weather.windDirection,
          gustSpeedMps: site.weather.gustSpeed,
          precipitationMm: site.weather.precipitationMm,
          summaryText: site.weather.summary,
          isFallback: true,
        ),
      ];
    }

    return grouped.entries.map((entry) {
      final items = entry.value;
      final maxWind = items.fold<double>(
        0,
        (current, item) => (item.windSpeedMps ?? 0) > current
            ? (item.windSpeedMps ?? 0)
            : current,
      );
      final maxGust = items.fold<double>(
        0,
        (current, item) => (item.gustSpeedMps ?? 0) > current
            ? (item.gustSpeedMps ?? 0)
            : current,
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
        summaryText: items.first.summaryText ?? site.weather.summary,
        isFallback: true,
      );
    }).toList(growable: false);
  }

  DateTime _parseForecastTime(String label, DateTime baseTime, int index) {
    final match = RegExp(r'(\d{1,2})').firstMatch(label);
    if (match == null) {
      return baseTime.add(Duration(hours: index * 3));
    }
    final hour = int.tryParse(match.group(1)!) ?? baseTime.hour;
    var candidate = DateTime(baseTime.year, baseTime.month, baseTime.day, hour);
    if (candidate.isBefore(baseTime.subtract(const Duration(hours: 1)))) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  String _forecastSummary(
      double? windSpeed, double? gustSpeed, double? precipitation) {
    if ((precipitation ?? 0) >= 1.0) {
      return '강수 가능성 높음';
    }
    if ((gustSpeed ?? 0) >= 8.0) {
      return '돌풍 주의';
    }
    if ((windSpeed ?? 0) >= 6.0) {
      return '바람 강함';
    }
    return '짧은 점검 구간';
  }
}

class _SiteDetailViewState {
  const _SiteDetailViewState({
    required this.detail,
    required this.metadata,
    required this.weather,
    required this.forecast,
    required this.extendedForecast,
    required this.currentPosition,
    required this.distanceMeters,
  });

  final SiteDetail detail;
  final KoreaFlightSiteMetadata? metadata;
  final LiveWeatherSnapshot weather;
  final List<LiveWeatherForecastItem> forecast;
  final List<LiveWeatherDailyForecastItem> extendedForecast;
  final Position? currentPosition;
  final double? distanceMeters;

  _SiteDetailViewState copyWith({
    SiteDetail? detail,
    KoreaFlightSiteMetadata? metadata,
    LiveWeatherSnapshot? weather,
    List<LiveWeatherForecastItem>? forecast,
    List<LiveWeatherDailyForecastItem>? extendedForecast,
    Position? currentPosition,
    double? distanceMeters,
  }) {
    return _SiteDetailViewState(
      detail: detail ?? this.detail,
      metadata: metadata ?? this.metadata,
      weather: weather ?? this.weather,
      forecast: forecast ?? this.forecast,
      extendedForecast: extendedForecast ?? this.extendedForecast,
      currentPosition: currentPosition ?? this.currentPosition,
      distanceMeters: distanceMeters ?? this.distanceMeters,
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }
}

class _ReferenceChip extends StatelessWidget {
  const _ReferenceChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2F5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF2C566D),
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _WeatherAlertChip extends StatelessWidget {
  const _WeatherAlertChip({required this.alert});

  final WeatherInterpretationAlert alert;

  @override
  Widget build(BuildContext context) {
    final colors = switch (alert.severity) {
      WeatherInterpretationSeverity.info => (
          background: const Color(0xFFE7F4EE),
          foreground: const Color(0xFF217A4C),
        ),
      WeatherInterpretationSeverity.caution => (
          background: const Color(0xFFFFF2DB),
          foreground: const Color(0xFF8C5B00),
        ),
      WeatherInterpretationSeverity.warning => (
          background: const Color(0xFFFCE9E4),
          foreground: const Color(0xFF9A3412),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        alert.label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFE6F4F7) : const Color(0xFFF5F9FB),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF546973),
                ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF17313C),
                ),
          ),
        ],
      ),
    );
  }
}

class _ForecastTile extends StatelessWidget {
  const _ForecastTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final LiveWeatherForecastItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background =
        selected ? const Color(0xFF143746) : const Color(0xFFF5F9FB);
    final foreground = selected ? Colors.white : const Color(0xFF17313C);
    final muted = selected
        ? Colors.white.withValues(alpha: 0.78)
        : const Color(0xFF4F6671);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 132,
        padding: const EdgeInsets.fromLTRB(11, 10, 11, 9),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? const Color(0xFF58A4B0) : const Color(0xFFE0EAEE),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _relativeLabel(item.time),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              _formatClock(item.time),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Icon(
              _weatherIconData(item.weatherCode),
              size: 15,
              color: foreground,
            ),
            const SizedBox(height: 4),
            Text(
              _formatTemperature(item.temperatureCelsius),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatSpeed(item.windSpeedMps),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Transform.rotate(
                  angle: ((item.windDirection - 90) * math.pi) / 180,
                  child: Icon(Icons.navigation_rounded, size: 16, color: muted),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _shortHeading(item.windDirection),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  item.summaryText ?? '참고 예보',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: muted,
                        height: 1.2,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyForecastTile extends StatelessWidget {
  const _DailyForecastTile({
    required this.item,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  final LiveWeatherDailyForecastItem item;
  final _DetailStatusTone tone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background =
        selected ? const Color(0xFF143746) : const Color(0xFFF5F9FB);
    final foreground = selected ? Colors.white : const Color(0xFF17313C);
    final muted = selected
        ? Colors.white.withValues(alpha: 0.78)
        : const Color(0xFF4F6671);
    final badgeColor = _toneColor(tone);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 140,
        padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? const Color(0xFF58A4B0) : const Color(0xFFE0EAEE),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _longRangeLabel(item.date),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              _formatForecastDate(item.date),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Icon(
              _weatherIconData(item.weatherCode),
              size: 15,
              color: foreground,
            ),
            const SizedBox(height: 4),
            Text(
              _formatDailyTemperatureRange(
                item.minTemperatureCelsius,
                item.maxTemperatureCelsius,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatSpeed(item.windSpeedMps),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Transform.rotate(
                  angle: (((item.windDirection ?? 0) - 90) * math.pi) / 180,
                  child: Icon(Icons.navigation_rounded, size: 16, color: muted),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.windDirection == null
                        ? '풍향 준비 중'
                        : _shortHeading(item.windDirection!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  _dailySummaryText(item),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: muted,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: selected ? 0.26 : 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _toneLabel(tone),
                  style: TextStyle(
                    color: selected ? Colors.white : badgeColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    this.dark = false,
  });

  final String label;
  final Color color;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: dark
            ? color.withValues(alpha: 0.20)
            : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: dark ? Colors.white : color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _InfoBubble extends StatelessWidget {
  const _InfoBubble({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBFD),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDDE8EC)),
      ),
      child: Text('$label  $value'),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAFB),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF47616D),
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }
}

class _OverlayChip extends StatelessWidget {
  const _OverlayChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2430).withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFF0F2430).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _SiteMarker extends StatelessWidget {
  const _SiteMarker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.paragliding_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        Container(
          width: 6,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}

class _CurrentLocationMarker extends StatelessWidget {
  const _CurrentLocationMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1EA7FD).withValues(alpha: 0.22),
      ),
      padding: const EdgeInsets.all(5),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1EA7FD),
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _DetailStatusTone {
  flyable,
  caution,
  confirmationRequired,
  potentiallyRestricted
}

_DetailStatusTone _toneFor(FlightStatus status) => switch (status) {
      FlightStatus.good => _DetailStatusTone.flyable,
      FlightStatus.caution => _DetailStatusTone.caution,
      FlightStatus.bad => _DetailStatusTone.confirmationRequired,
    };

Color _toneColor(_DetailStatusTone tone) => switch (tone) {
      _DetailStatusTone.flyable => const Color(0xFF1E8C5B),
      _DetailStatusTone.caution => const Color(0xFFD27A00),
      _DetailStatusTone.confirmationRequired => const Color(0xFF2A7084),
      _DetailStatusTone.potentiallyRestricted => const Color(0xFFC4463A),
    };

String _toneLabel(_DetailStatusTone tone) => switch (tone) {
      _DetailStatusTone.flyable => '비행 가능',
      _DetailStatusTone.caution => '주의',
      _DetailStatusTone.confirmationRequired => '확인 필요',
      _DetailStatusTone.potentiallyRestricted => '제한 가능성 있음',
    };

String _toneSummary(_DetailStatusTone tone) => switch (tone) {
      _DetailStatusTone.flyable => '현재 조건은 비행 참고 상태로 비교적 안정적으로 보입니다.',
      _DetailStatusTone.caution => '현재 조건은 이륙 전 풍향과 돌풍을 한 번 더 확인하는 편이 좋습니다.',
      _DetailStatusTone.confirmationRequired =>
        '현재 조건은 보수적으로 다시 판단하는 편이 안전합니다.',
      _DetailStatusTone.potentiallyRestricted => '현재 정보만으로는 안전하게 판단하기 어렵습니다.',
    };

String _bestSummaryText(_SiteDetailViewState state) {
  final summary = state.weather.summary.trim();
  if (summary.isNotEmpty) {
    return summary;
  }
  return state.detail.site.assessment.summaryText;
}

String _warningText(_SiteDetailViewState state) {
  final note = state.detail.rule.notes.trim();
  if (note.isNotEmpty) {
    return note;
  }
  final description = state.detail.description.trim();
  if (description.isNotEmpty) {
    return description;
  }
  return '현장 브리핑과 공역 정보, 착륙장 상태를 추가로 확인해 주세요.';
}

String _windGuideText(_SiteDetailViewState state) {
  final windDirection = state.weather.windDirection;
  final detail = state.detail;
  if (detail.allowedDirectionRange.contains('현장 확인') ||
      detail.allowedDirectionRange.contains('대표 풍향 정보 없음')) {
    return '대표 풍향 메모가 아직 부족해 현재 풍향과 정확히 비교하지 못했습니다. 현장 바람과 브리핑을 함께 확인해 주세요.';
  }
  if (windDirection == null) {
    return '현재 풍향 정보가 없어 ${detail.allowedDirectionRange} 허용 범위와 비교하지 못했습니다.';
  }
  if (_isWindDirectionAllowed(windDirection, detail.rule)) {
    return '현재 풍향은 ${detail.allowedDirectionRange} 허용 범위 안에 있어 참고용으로 무리가 없습니다.';
  }
  final distance = _windDistanceToAllowedRange(windDirection, detail.rule);
  return '현재 풍향은 ${detail.allowedDirectionRange} 허용 범위에서 약 $distance도 벗어나 있어 추가 확인이 필요합니다.';
}

String _weatherBasisText(_SiteDetailViewState state) {
  final siteName = state.detail.site.name;
  if (state.currentPosition == null) {
    return '$siteName 사이트 좌표 기준 날씨와 예보를 보여주고 있습니다. 현재 위치를 켜면 사이트와의 거리도 함께 비교할 수 있습니다.';
  }

  final distance = state.distanceMeters;
  if (distance == null) {
    return '$siteName 사이트 기준 날씨를 보여주고 있습니다. 현재 위치와 차이가 있을 수 있으니 현장 바람은 추가로 확인해 주세요.';
  }

  if (distance < 500) {
    return '$siteName 사이트 기준 날씨를 보여주고 있으며 현재 위치도 사이트 반경 안에 있어 현장 판단에 바로 참고하기 좋습니다.';
  }

  return '$siteName 사이트 기준 날씨를 보여주고 있습니다. 현재 위치와 약 ${_formatDistance(distance)} 차이가 있어 이동 전 최신 현장 상황을 함께 확인해 주세요.';
}

bool _isWindDirectionAllowed(int direction, SiteRule rule) {
  final normalizedDirection = ((direction % 360) + 360) % 360;
  final start = ((rule.allowedDirectionStart % 360) + 360) % 360;
  final end = ((rule.allowedDirectionEnd % 360) + 360) % 360;
  if (start <= end) {
    return normalizedDirection >= start && normalizedDirection <= end;
  }
  return normalizedDirection >= start || normalizedDirection <= end;
}

int _windDistanceToAllowedRange(int direction, SiteRule rule) {
  final normalizedDirection = ((direction % 360) + 360) % 360;
  final start = ((rule.allowedDirectionStart % 360) + 360) % 360;
  final end = ((rule.allowedDirectionEnd % 360) + 360) % 360;
  if (_isWindDirectionAllowed(direction, rule)) {
    return 0;
  }

  int circularDistance(int from, int to) {
    final raw = (from - to).abs();
    return raw > 180 ? 360 - raw : raw;
  }

  final distanceToStart = circularDistance(normalizedDirection, start);
  final distanceToEnd = circularDistance(normalizedDirection, end);
  return distanceToStart < distanceToEnd ? distanceToStart : distanceToEnd;
}

String _locationRelationText(_SiteDetailViewState state) {
  if (state.metadata == null) {
    return '등록 좌표가 아직 연결되지 않아 현재 위치와의 거리를 계산할 수 없습니다. 사이트 기준 예보와 참고 정보만 먼저 보여드리고 있습니다.';
  }
  if (state.currentPosition == null) {
    return '위치 권한을 허용하면 현재 위치와 사이트 거리를 보여드리고, 지도에서도 내 위치와 사이트 관계를 함께 볼 수 있습니다.';
  }
  final distance = state.distanceMeters ?? 0;
  if (distance < 500) {
    return '현재 위치가 사이트 반경 안에 있어 현장 접근 상태를 빠르게 확인하기 좋습니다.';
  }
  return '현재 위치와 사이트는 약 ${_formatDistance(distance)} 떨어져 있습니다.';
}

_DetailStatusTone _dailyToneFor(
  LiveWeatherDailyForecastItem item,
  SiteDetail detail,
) {
  var score = 0;
  final precipitationProbability = item.precipitationProbability ?? 0;
  final precipitation = item.precipitationMm ?? 0;
  final windSpeed = item.windSpeedMps ?? 0;
  final gustSpeed = item.gustSpeedMps ?? 0;

  if (precipitationProbability >= 70 ||
      precipitation >= 5 ||
      gustSpeed >= 10.5) {
    score = 3;
  } else if (precipitationProbability >= 45 ||
      precipitation >= 2 ||
      windSpeed >= 7 ||
      gustSpeed >= 8.5) {
    score = 2;
  } else if (precipitationProbability >= 20 ||
      precipitation > 0 ||
      windSpeed >= 5.5 ||
      gustSpeed >= 7) {
    score = 1;
  }

  final direction = item.windDirection;
  if (direction != null && !_isWindDirectionAllowed(direction, detail.rule)) {
    score = math.max(score, 1);
  }

  return switch (score) {
    0 => _DetailStatusTone.flyable,
    1 => _DetailStatusTone.caution,
    2 => _DetailStatusTone.confirmationRequired,
    _ => _DetailStatusTone.potentiallyRestricted,
  };
}

String _dailyConfidenceLabel(DateTime date) {
  final daysAhead = _daysAhead(date);
  if (daysAhead <= 2) {
    return '단기 예보 기준';
  }
  if (daysAhead <= 6) {
    return '주간 예보 기준';
  }
  return '장기 예보 참고';
}

String _dailyConfidenceDescription(DateTime date) {
  final daysAhead = _daysAhead(date);
  if (daysAhead <= 2) {
    return '오늘부터 3일 안쪽 예보는 상대적으로 변동이 적지만, 현장 바람과 이륙장 상태는 별도로 확인해 주세요.';
  }
  if (daysAhead <= 6) {
    return '주간 예보는 흐름을 보는 용도로 적합합니다. 실제 출동 전에는 전날과 당일 예보를 다시 확인하는 편이 안전합니다.';
  }
  return '8일 이후 장기 예보는 추세 참고용입니다. 장거리 출동 판단은 가까운 날짜에 다시 확인하는 편이 좋습니다.';
}

int _daysAhead(DateTime date) {
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  return target.difference(startOfToday).inDays;
}

String _longRangeLabel(DateTime date) {
  final daysAhead = _daysAhead(date);
  if (daysAhead <= 0) {
    return '오늘';
  }
  if (daysAhead == 1) {
    return '내일';
  }
  if (daysAhead == 2) {
    return '모레';
  }
  if (daysAhead <= 6) {
    return '주간 예보';
  }
  return '장기 예보';
}

String _dailySummaryText(LiveWeatherDailyForecastItem item) {
  final summary = item.summaryText?.trim() ?? '';
  if (summary.isNotEmpty) {
    return summary;
  }
  return '장기 예보를 기준으로 참고해 주세요.';
}

IconData _weatherIconData(int? code) => switch (code) {
      0 || 1 => Icons.wb_sunny_rounded,
      2 || 3 => Icons.cloud_rounded,
      45 || 48 => Icons.blur_on_rounded,
      51 ||
      53 ||
      55 ||
      56 ||
      57 ||
      61 ||
      63 ||
      65 ||
      66 ||
      67 =>
        Icons.grain_rounded,
      71 || 73 || 75 || 77 || 85 || 86 => Icons.ac_unit_rounded,
      80 || 81 || 82 => Icons.umbrella_rounded,
      95 || 96 || 99 => Icons.thunderstorm_rounded,
      _ => Icons.cloud_queue_rounded,
    };

String _formatForecastDate(DateTime date) {
  return '${date.month}월 ${date.day}일';
}

String _formatDailyTemperatureRange(double? min, double? max) {
  if (min == null && max == null) {
    return '기온 정보 준비 중';
  }
  if (min == null) {
    return '최고 ${_formatTemperature(max)}';
  }
  if (max == null) {
    return '최저 ${_formatTemperature(min)}';
  }
  return '${_formatTemperature(min)} ~ ${_formatTemperature(max)}';
}

String _formatProbability(int? percent) {
  if (percent == null) {
    return '정보 준비 중';
  }
  return '$percent%';
}

String _difficultyLabel(String difficulty) => switch (difficulty) {
      'beginner' => '초급',
      'intermediate' => '중급',
      'advanced' => '상급',
      _ => difficulty,
    };

String _formatTemperature(double? celsius) {
  if (celsius == null) {
    return '정보 준비 중';
  }
  return '${celsius.toStringAsFixed(1)}°C';
}

String _formatSpeed(double? speedMps) {
  if (speedMps == null) {
    return '정보 준비 중';
  }
  return '${speedMps.toStringAsFixed(speedMps >= 10 ? 0 : 1)}m/s';
}

String _formatPrecipitation(double? precipitationMm) {
  if (precipitationMm == null) {
    return '정보 없음';
  }
  return '${precipitationMm.toStringAsFixed(1)}mm';
}

String _formatHeading(int? degrees) {
  if (degrees == null) {
    return '정보 준비 중';
  }
  final normalized = ((degrees % 360) + 360) % 360;
  return '${normalized.toStringAsFixed(0)}° ${_shortHeading(normalized)}';
}

String _shortHeading(num degrees) {
  final normalized = ((degrees % 360) + 360) % 360;
  if (normalized >= 337.5 || normalized < 22.5) return '북';
  if (normalized < 67.5) return '북동';
  if (normalized < 112.5) return '동';
  if (normalized < 157.5) return '남동';
  if (normalized < 202.5) return '남';
  if (normalized < 247.5) return '남서';
  if (normalized < 292.5) return '서';
  return '북서';
}

String _formatDateTime(DateTime time) {
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$month월 $day일 $hour:$minute';
}

String _formatClock(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _relativeLabel(DateTime time) {
  final now = DateTime.now();
  final diffHours = time.difference(now).inHours;
  if (diffHours <= 0) return '지금';
  if (diffHours < 24) return '$diffHours시간 뒤';
  return '${time.month}/${time.day}';
}

String _formatDistance(double meters) {
  if (meters >= 1000) {
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }
  return '${meters.toStringAsFixed(0)}m';
}
