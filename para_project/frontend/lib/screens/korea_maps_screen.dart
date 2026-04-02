import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../app.dart';
import '../core/kmz_site_catalog.dart';
import '../core/korea_flight_guide.dart';
import '../core/korea_weather_map_service.dart';
import '../core/live_weather_service.dart';
import '../core/map_view_type.dart';
import '../core/utils.dart';
import '../models/app_models.dart';
import '../repositories/app_repository.dart';
import '../widgets/map_view_toggle.dart';
import 'site_list_screen.dart';

class KoreaMapsScreen extends StatefulWidget {
  const KoreaMapsScreen({
    super.key,
    required this.repository,
    required this.user,
  });

  final AppRepository repository;
  final AppUser user;

  @override
  State<KoreaMapsScreen> createState() => _KoreaMapsScreenState();
}

class _KoreaMapsScreenState extends State<KoreaMapsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final KoreaWeatherMapService _mapService;
  final MapViewPreferenceStore _mapViewPreferenceStore =
      MapViewPreferenceStore();
  late Future<_KoreaMapsData> _future;
  MapSiteSelection? _selectedSite;
  ParaglidingMapViewType _mapViewType = ParaglidingMapViewType.satellite;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _mapService = KoreaWeatherMapService();
    _future = _loadData();
    unawaited(_loadMapViewType());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _mapService.dispose();
    super.dispose();
  }

  Future<_KoreaMapsData> _loadData({bool forceRefresh = false}) async {
    if (forceRefresh) {
      _mapService.clearCache();
    }

    final sites = await widget.repository.getSites(
      pilotLevel: widget.user.pilotLevel,
    );
    final importedSites = await ImportedParaglidingSiteCatalog.load();
    final siteSnapshots = await _mapService.loadSiteSnapshots(
      sites,
      forceRefresh: forceRefresh,
    );

    return _KoreaMapsData(
      siteSnapshots: siteSnapshots,
      importedSites: importedSites,
    );
  }

  void _refreshAll() {
    setState(() {
      _future = _loadData(forceRefresh: true);
    });
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

  void _handleSelectionChanged(MapSiteSelection? selection) {
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedSite = selection;
    });
  }

  void _openOnMap(MapSiteSelection selection) {
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedSite = selection;
    });
    _tabController.animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_KoreaMapsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 40),
                  const SizedBox(height: 12),
                  const Text('지도 데이터를 불러오지 못했습니다.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _refreshAll,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('다시 불러오기'),
                  ),
                ],
              ),
            ),
          );
        }

        final data = snapshot.data!;
        final selectedSite = _selectedSite ??
            (data.siteSnapshots.isNotEmpty
                ? MapSiteSelection.registered(data.siteSnapshots.first.site.id)
                : null);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F6F8),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  labelColor: const Color(0xFF17324D),
                  unselectedLabelColor: const Color(0xFF607080),
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: '날씨 지도'),
                    Tab(text: '비행 가능'),
                    Tab(text: '사이트 목록'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _KoreaMapTab(
                    repository: widget.repository,
                    user: widget.user,
                    mapService: _mapService,
                    siteSnapshots: data.siteSnapshots,
                    importedSites: data.importedSites,
                    selectedSite: selectedSite,
                    onSiteSelected: _handleSelectionChanged,
                    onRefreshAll: _refreshAll,
                    mapViewType: _mapViewType,
                    onMapViewTypeChanged: _changeMapViewType,
                    mode: _MapMode.weather,
                  ),
                  _KoreaMapTab(
                    repository: widget.repository,
                    user: widget.user,
                    mapService: _mapService,
                    siteSnapshots: data.siteSnapshots,
                    importedSites: data.importedSites,
                    selectedSite: selectedSite,
                    onSiteSelected: _handleSelectionChanged,
                    onRefreshAll: _refreshAll,
                    mapViewType: _mapViewType,
                    onMapViewTypeChanged: _changeMapViewType,
                    mode: _MapMode.flyable,
                  ),
                  SiteListScreen(
                    repository: widget.repository,
                    user: widget.user,
                    importedSites: data.importedSites,
                    selectedSite: selectedSite,
                    onSelectSiteForMap: _openOnMap,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _KoreaMapsData {
  const _KoreaMapsData({
    required this.siteSnapshots,
    required this.importedSites,
  });

  final List<KoreaSiteMapSnapshot> siteSnapshots;
  final List<ImportedParaglidingSite> importedSites;
}

enum _MapMode { weather, flyable }

class _KoreaMapTab extends StatefulWidget {
  const _KoreaMapTab({
    required this.repository,
    required this.user,
    required this.mapService,
    required this.siteSnapshots,
    required this.importedSites,
    required this.selectedSite,
    required this.onSiteSelected,
    required this.onRefreshAll,
    required this.mapViewType,
    required this.onMapViewTypeChanged,
    required this.mode,
  });

  final AppRepository repository;
  final AppUser user;
  final KoreaWeatherMapService mapService;
  final List<KoreaSiteMapSnapshot> siteSnapshots;
  final List<ImportedParaglidingSite> importedSites;
  final MapSiteSelection? selectedSite;
  final ValueChanged<MapSiteSelection?> onSiteSelected;
  final VoidCallback onRefreshAll;
  final ParaglidingMapViewType mapViewType;
  final ValueChanged<ParaglidingMapViewType> onMapViewTypeChanged;
  final _MapMode mode;

  @override
  State<_KoreaMapTab> createState() => _KoreaMapTabState();
}

class _KoreaMapTabState extends State<_KoreaMapTab>
    with WidgetsBindingObserver {
  static const _koreaCenter = LatLng(36.35, 127.9);

  final MapController _mapController = MapController();
  final KoreaFlightGuide _flightGuide = const KoreaFlightGuide();

  Timer? _debounce;
  StreamSubscription<Position>? _positionSubscription;

  LatLng _mapCenter = _koreaCenter;
  double _currentZoom = 7.2;
  KoreaSiteMapSnapshot? _selectedSiteSnapshot;
  ImportedParaglidingSite? _selectedImportedSite;
  LatLng? _selectedPoint;
  KoreaAreaWeatherSnapshot? _areaPreview;
  KoreaAreaWeatherSnapshot? _selectionArea;
  SiteDetail? _selectedSiteDetail;
  KoreaZoneAdvisory? _selectedAdvisory;
  List<LiveWeatherForecastItem> _selectedForecast = const [];
  LatLng? _currentLocation;
  String? _selectionError;
  String? _areaError;
  String? _locationError;
  bool _loadingArea = false;
  bool _loadingSelection = false;
  bool _refreshing = false;
  bool _locating = false;
  bool _followCurrentLocation = false;

  bool get _isWeatherMode => widget.mode == _MapMode.weather;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncIncomingSelection(useDefault: true);
    unawaited(_loadAreaPreview(_mapCenter));
    unawaited(_loadSelectionData());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _KoreaMapTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedSite?.siteId != oldWidget.selectedSite?.siteId ||
        widget.selectedSite?.importedSiteSourceId !=
            oldWidget.selectedSite?.importedSiteSourceId ||
        widget.siteSnapshots.length != oldWidget.siteSnapshots.length) {
      _syncIncomingSelection(useDefault: false);
      unawaited(_loadSelectionData());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshSelection());
    }
  }

  void _syncIncomingSelection({required bool useDefault}) {
    final nextRegistered = _findSiteById(widget.selectedSite?.siteId) ??
        (useDefault ? widget.siteSnapshots.firstOrNull : null);
    final nextImported =
        _findImportedSiteBySourceId(widget.selectedSite?.importedSiteSourceId);

    if (nextImported != null) {
      _selectedImportedSite = nextImported;
      _selectedSiteSnapshot = null;
      _selectedPoint = null;
      _moveToImportedSite(nextImported);
      return;
    }

    if (nextRegistered != null) {
      _selectedSiteSnapshot = nextRegistered;
      _selectedImportedSite = null;
      _selectedPoint = null;
      _moveToSite(nextRegistered);
    }
  }

  KoreaSiteMapSnapshot? _findSiteById(int? siteId) {
    if (siteId == null) {
      return null;
    }
    for (final snapshot in widget.siteSnapshots) {
      if (snapshot.site.id == siteId) {
        return snapshot;
      }
    }
    return null;
  }

  ImportedParaglidingSite? _findImportedSiteBySourceId(String? sourceId) {
    if (sourceId == null) {
      return null;
    }
    for (final site in widget.importedSites) {
      if (site.sourceId == sourceId) {
        return site;
      }
    }
    return null;
  }

  Future<SiteDetail> _loadSiteDetail(int siteId) {
    return widget.repository.getSiteDetail(
      siteId: siteId,
      pilotLevel: widget.user.pilotLevel,
    );
  }

  void _moveToSite(KoreaSiteMapSnapshot snapshot) {
    final point =
        LatLng(snapshot.metadata.latitude, snapshot.metadata.longitude);
    _mapCenter = point;
    _currentZoom = 9.1;
    try {
      _mapController.move(point, 9.1);
    } catch (_) {
      // 지도 초기화 전에는 이동을 건너뛴다.
    }
  }

  void _moveToImportedSite(ImportedParaglidingSite site) {
    final point = LatLng(site.latitude, site.longitude);
    _mapCenter = point;
    _currentZoom = 9.2;
    try {
      _mapController.move(point, 9.2);
    } catch (_) {
      // 지도 초기화 전에는 이동을 건너뛴다.
    }
  }

  Future<void> _loadAreaPreview(
    LatLng point, {
    bool forceRefresh = false,
  }) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingArea = true;
      _areaError = null;
      _mapCenter = point;
    });

    try {
      final snapshot = await widget.mapService.loadAreaWeather(
        latitude: point.latitude,
        longitude: point.longitude,
        siteSnapshots: widget.siteSnapshots,
        forceRefresh: forceRefresh,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _areaPreview = snapshot;
        _loadingArea = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingArea = false;
        _areaError = '선택한 지역의 날씨를 불러오지 못했습니다.';
      });
    }
  }

  Future<void> _loadSelectionData({bool forceRefresh = false}) async {
    final selectedSite = _selectedSiteSnapshot;
    final importedSite = _selectedImportedSite;
    final selectedPoint = _selectedPoint;

    final latitude = importedSite?.latitude ??
        selectedSite?.metadata.latitude ??
        selectedPoint?.latitude;
    final longitude = importedSite?.longitude ??
        selectedSite?.metadata.longitude ??
        selectedPoint?.longitude;

    if (latitude == null || longitude == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _selectionArea = null;
        _selectedSiteDetail = null;
        _selectedAdvisory = null;
        _selectedForecast = const [];
        _loadingSelection = false;
        _selectionError = null;
      });
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _loadingSelection = true;
      _selectionError = null;
    });

    SiteDetail? detail;
    KoreaZoneAdvisory? advisory;
    KoreaAreaWeatherSnapshot? selectionArea;
    List<LiveWeatherForecastItem> forecast = const [];
    String? errorText;

    try {
      final referenceSite = selectedSite?.site;
      if (selectedSite != null) {
        forecast = await widget.mapService.loadShortTermForecast(
          latitude: latitude,
          longitude: longitude,
          selectedSite: referenceSite,
          forceRefresh: forceRefresh,
        );
        advisory = selectedSite.advisory;
        try {
          detail = await _loadSiteDetail(selectedSite.site.id);
        } catch (_) {
          detail =
              _fallbackSiteDetail(selectedSite.site, selectedSite.metadata);
          errorText = '사이트 상세 정보 일부를 불러오지 못해 기본 안내로 표시합니다.';
        }
      } else {
        selectionArea = await widget.mapService.loadAreaWeather(
          latitude: latitude,
          longitude: longitude,
          siteSnapshots: widget.siteSnapshots,
          forceRefresh: forceRefresh,
        );
        forecast = await widget.mapService.loadShortTermForecast(
          latitude: latitude,
          longitude: longitude,
          selectedSite: selectionArea.nearbySite?.site,
          forceRefresh: forceRefresh,
        );

        if (importedSite != null) {
          detail = importedSite.toSiteDetail(
            weather: selectionArea.weather,
            forecast: forecast,
          );
          advisory = _buildImportedAdvisory(
            importedSite,
            detail.site.assessment.status,
          );
        } else {
          advisory = _flightGuide.assess(
            latitude: latitude,
            longitude: longitude,
            selectedSite: selectionArea.nearbySite?.site,
          );

          if (selectionArea.nearbySite != null) {
            try {
              detail = await _loadSiteDetail(selectionArea.nearbySite!.site.id);
            } catch (_) {
              detail = _fallbackSiteDetail(
                selectionArea.nearbySite!.site,
                selectionArea.nearbySite!.metadata,
              );
              errorText = '가까운 사이트 상세 정보 일부를 불러오지 못해 기본 안내로 표시합니다.';
            }
          }
        }
      }
    } catch (_) {
      errorText ??= '선택한 지점의 상세 정보를 불러오지 못했습니다.';
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _selectionArea = selectionArea;
      _selectedSiteDetail = detail;
      _selectedAdvisory = advisory;
      _selectedForecast = forecast;
      _loadingSelection = false;
      _selectionError = errorText;
    });
  }

  Future<void> _refreshSelection() async {
    if (_refreshing) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _refreshing = true;
    });

    try {
      final target = _selectedPoint ??
          (_selectedImportedSite != null
              ? LatLng(
                  _selectedImportedSite!.latitude,
                  _selectedImportedSite!.longitude,
                )
              : _selectedSiteSnapshot != null
                  ? LatLng(
                      _selectedSiteSnapshot!.metadata.latitude,
                      _selectedSiteSnapshot!.metadata.longitude,
                    )
                  : _mapCenter);
      await _loadAreaPreview(target, forceRefresh: true);
      await _loadSelectionData(forceRefresh: true);
      widget.onRefreshAll();
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  void _selectSite(KoreaSiteMapSnapshot site) {
    setState(() {
      _selectedSiteSnapshot = site;
      _selectedImportedSite = null;
      _selectedPoint = null;
      _selectionArea = null;
    });
    widget.onSiteSelected(MapSiteSelection.registered(site.site.id));
    _moveToSite(site);
    unawaited(_loadAreaPreview(
      LatLng(site.metadata.latitude, site.metadata.longitude),
    ));
    unawaited(_loadSelectionData(forceRefresh: true));
  }

  void _selectImportedSite(ImportedParaglidingSite site) {
    setState(() {
      _selectedSiteSnapshot = null;
      _selectedImportedSite = site;
      _selectedPoint = null;
      _selectionArea = null;
    });
    widget.onSiteSelected(MapSiteSelection.imported(site.sourceId));
    _moveToImportedSite(site);
    unawaited(_loadAreaPreview(LatLng(site.latitude, site.longitude)));
    unawaited(_loadSelectionData(forceRefresh: true));
  }

  void _selectPoint(LatLng point) {
    setState(() {
      _selectedSiteSnapshot = null;
      _selectedImportedSite = null;
      _selectedPoint = point;
      _selectionArea = null;
    });
    widget.onSiteSelected(null);
    _currentZoom = 9.3;
    try {
      _mapController.move(point, 9.3);
    } catch (_) {
      // 지도 초기화 전에는 이동을 건너뛴다.
    }
    unawaited(_loadAreaPreview(point));
    unawaited(_loadSelectionData(forceRefresh: true));
  }

  Future<void> _focusCurrentLocation() async {
    if (_locating) {
      return;
    }
    if (_positionSubscription != null) {
      setState(() {
        _followCurrentLocation = !_followCurrentLocation;
      });
      return;
    }
    await _startLocationUpdates();
  }

  Future<void> _startLocationUpdates({bool forceRestart = false}) async {
    if (_positionSubscription != null && !forceRestart) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _locating = true;
      _locationError = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('위치 서비스가 꺼져 있습니다.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        throw Exception('현재 위치를 보려면 위치 권한이 필요합니다.');
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('위치 권한이 영구적으로 거부되어 설정에서 허용이 필요합니다.');
      }

      await _positionSubscription?.cancel();

      final first = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      _applyPosition(first, moveCamera: true, selectPoint: true);

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 5,
        ),
      ).listen(
        (position) =>
            _applyPosition(position, moveCamera: _followCurrentLocation),
        onError: (_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _locating = false;
            _locationError = '현재 위치 업데이트가 중단되었습니다.';
          });
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _locating = false;
        _locationError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _applyPosition(
    Position position, {
    required bool moveCamera,
    bool selectPoint = false,
  }) {
    final point = LatLng(position.latitude, position.longitude);
    if (!mounted) {
      return;
    }
    setState(() {
      _currentLocation = point;
      _locating = false;
      _followCurrentLocation = true;
      _locationError = null;
    });
    if (moveCamera) {
      try {
        _mapController.move(point, 10.0);
        _currentZoom = 10.0;
      } catch (_) {
        // 지도 초기화 전에는 이동을 건너뛴다.
      }
    }
    if (selectPoint) {
      _selectPoint(point);
    }
  }

  void _handlePositionChanged(MapCamera camera, bool hasGesture) {
    if (mounted && _currentZoom != camera.zoom) {
      setState(() {
        _currentZoom = camera.zoom;
      });
    }
    if (!hasGesture) {
      return;
    }
    _mapCenter = camera.center;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) {
        return;
      }
      unawaited(_loadAreaPreview(camera.center));
    });
  }

  SiteDetail _fallbackSiteDetail(
    SiteSummary site,
    KoreaFlightSiteMetadata metadata,
  ) {
    return SiteDetail(
      site: site,
      description: metadata.note,
      takeoffAltitudeM: 0,
      landingAltitudeM: 0,
      allowedDirectionRange: '현장 확인 필요',
      rule: SiteRule(
        notes: metadata.safetyText,
        allowedDirectionStart: 0,
        allowedDirectionEnd: 359,
        beginnerAllowed: site.beginnerAllowed,
        maxGust: 8,
        maxGustDifference: 3,
      ),
    );
  }

  KoreaZoneAdvisory _buildImportedAdvisory(
    ImportedParaglidingSite site,
    FlightStatus status,
  ) {
    final mappedStatus = switch (status) {
      FlightStatus.good => KoreaZoneStatus.flyable,
      FlightStatus.caution => KoreaZoneStatus.caution,
      FlightStatus.bad => KoreaZoneStatus.confirmationRequired,
    };
    return KoreaZoneAdvisory(
      status: mappedStatus,
      confidence: KoreaZoneConfidence.curated,
      title: '현재 비행 참고 상태',
      summary: site.summaryLine.trim().isEmpty
          ? '${site.name} 기준 참고 정보를 표시합니다.'
          : site.summaryLine.trim(),
      detail: site.descriptionText.trim().isEmpty
          ? '${site.name}은 등록된 해외 또는 추가 사이트 기준 참고 정보입니다.'
          : site.descriptionText.trim(),
      disclaimer: '정확한 비행 가능 여부는 현장 및 공역 정보를 추가 확인해 주세요.',
      nearbySite: site.toGuideMetadata(),
      distanceMeters: 0,
    );
  }

  _MapPanelData? _buildPanelData() {
    final advisory = _selectedAdvisory;
    if (_selectedSiteSnapshot == null &&
        _selectedImportedSite == null &&
        _selectedPoint == null &&
        _selectionArea == null &&
        advisory == null) {
      return null;
    }

    if (_selectedSiteSnapshot != null) {
      final snapshot = _selectedSiteSnapshot!;
      final detail = _selectedSiteDetail ??
          _fallbackSiteDetail(snapshot.site, snapshot.metadata);
      return _MapPanelData(
        title: snapshot.site.name,
        region: snapshot.site.region,
        point: LatLng(snapshot.metadata.latitude, snapshot.metadata.longitude),
        weather: snapshot.weather,
        forecast: _selectedForecast,
        advisory: advisory ?? snapshot.advisory,
        detail: detail,
        basisLabel: '등록 비행장 기준',
        distanceMeters: _currentLocation == null
            ? null
            : Geolocator.distanceBetween(
                _currentLocation!.latitude,
                _currentLocation!.longitude,
                snapshot.metadata.latitude,
                snapshot.metadata.longitude,
              ),
        registeredSiteId: snapshot.site.id,
        importedSite: null,
      );
    }

    if (_selectedImportedSite != null && _selectionArea != null) {
      final importedSite = _selectedImportedSite!;
      return _MapPanelData(
        title: importedSite.name,
        region: importedSite.regionLabel,
        point: LatLng(importedSite.latitude, importedSite.longitude),
        weather: _selectionArea!.weather,
        forecast: _selectedForecast,
        advisory: advisory ??
            _buildImportedAdvisory(
              importedSite,
              _selectedSiteDetail?.site.assessment.status ??
                  FlightStatus.caution,
            ),
        detail: _selectedSiteDetail,
        basisLabel: '추가 사이트 기준',
        distanceMeters: _currentLocation == null
            ? null
            : Geolocator.distanceBetween(
                _currentLocation!.latitude,
                _currentLocation!.longitude,
                importedSite.latitude,
                importedSite.longitude,
              ),
        registeredSiteId: null,
        importedSite: importedSite,
      );
    }

    if (_selectionArea != null) {
      final area = _selectionArea!;
      final referenceSite = area.nearbySite;
      return _MapPanelData(
        title: area.areaLabel,
        region: referenceSite?.site.region ?? '선택 지점',
        point: LatLng(area.latitude, area.longitude),
        weather: area.weather,
        forecast: _selectedForecast,
        advisory: advisory ??
            _flightGuide.assess(
              latitude: area.latitude,
              longitude: area.longitude,
              selectedSite: referenceSite?.site,
            ),
        detail: _selectedSiteDetail,
        basisLabel: referenceSite == null ? '선택 지점 기준' : '선택 지점 + 가까운 비행장 참고',
        distanceMeters: _currentLocation == null
            ? null
            : Geolocator.distanceBetween(
                _currentLocation!.latitude,
                _currentLocation!.longitude,
                area.latitude,
                area.longitude,
              ),
        registeredSiteId: referenceSite?.site.id,
        importedSite: null,
      );
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final panelData = _buildPanelData();
    const showMarkerLabels = false;
    final currentImportedMarker = _selectedImportedSite;
    final importedMarkerSites = widget.importedSites
        .where((site) => currentImportedMarker?.sourceId != site.sourceId)
        .toList(growable: false);
    final topChipItems = <Widget>[
      _MapChoiceChip(
        title: _isWeatherMode ? '지도 중심' : '가까운 기준',
        subtitle: _areaPreview?.areaLabel ?? '선택 지점 보기',
        selected:
            _selectedSiteSnapshot == null && _selectedImportedSite == null,
        accentColor: theme.colorScheme.primary,
        onTap: () => _selectPoint(_mapCenter),
      ),
      if (currentImportedMarker != null)
        _MapChoiceChip(
          title: currentImportedMarker.name,
          subtitle: currentImportedMarker.preferredWindLabel,
          selected: true,
          accentColor: const Color(0xFF0F8B8D),
          onTap: () => _selectImportedSite(currentImportedMarker),
        ),
      ...widget.siteSnapshots.map(
        (site) => _MapChoiceChip(
          title: site.site.name,
          subtitle: _isWeatherMode
              ? formatTemperature(site.weather.temperatureCelsius)
              : site.advisory.status.label,
          selected: _selectedSiteSnapshot?.site.id == site.site.id,
          accentColor: _statusColor(site.advisory.status),
          onTap: () => _selectSite(site),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _mapCenter,
                initialZoom: 7.2,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
                onTap: (_, point) => _selectPoint(point),
                onPositionChanged: _handlePositionChanged,
              ),
              children: [
                buildParaglidingTileLayer(widget.mapViewType),
                if (!_isWeatherMode)
                  CircleLayer(
                    circles: widget.siteSnapshots
                        .map(
                          (site) => CircleMarker(
                            point: LatLng(
                              site.metadata.latitude,
                              site.metadata.longitude,
                            ),
                            radius: site.metadata.flyableRadiusMeters,
                            useRadiusInMeter: true,
                            color: _statusColor(site.advisory.status)
                                .withValues(alpha: 0.08),
                            borderColor: _statusColor(site.advisory.status)
                                .withValues(alpha: 0.25),
                            borderStrokeWidth: 1.4,
                          ),
                        )
                        .toList(growable: false),
                  ),
                MarkerLayer(
                  markers: [
                    ...importedMarkerSites.map(
                      (site) => Marker(
                        width: 40,
                        height: 40,
                        point: LatLng(site.latitude, site.longitude),
                        child: _ImportedSiteMarker(
                          selected: false,
                          color: _importedMarkerColor(site),
                          icon: _importedSiteIcon(site),
                          label: site.name,
                          showLabel: showMarkerLabels,
                          onTap: () => _selectImportedSite(site),
                        ),
                      ),
                    ),
                    ...widget.siteSnapshots.map(
                      (site) => Marker(
                        width: 44,
                        height: 44,
                        point: LatLng(
                          site.metadata.latitude,
                          site.metadata.longitude,
                        ),
                        child: _SiteMarker(
                          selected:
                              _selectedSiteSnapshot?.site.id == site.site.id,
                          color: _statusColor(site.advisory.status),
                          label: site.site.name,
                          showLabel: showMarkerLabels,
                          onTap: () => _selectSite(site),
                        ),
                      ),
                    ),
                    if (currentImportedMarker != null)
                      Marker(
                        width: 44,
                        height: 44,
                        point: LatLng(
                          currentImportedMarker.latitude,
                          currentImportedMarker.longitude,
                        ),
                        child: _ImportedSiteMarker(
                          selected: true,
                          color: _importedMarkerColor(currentImportedMarker),
                          icon: _importedSiteIcon(currentImportedMarker),
                          label: currentImportedMarker.name,
                          showLabel: false,
                          onTap: () =>
                              _selectImportedSite(currentImportedMarker),
                        ),
                      ),
                    if (_selectedPoint != null &&
                        _selectedSiteSnapshot == null &&
                        _selectedImportedSite == null)
                      Marker(
                        width: 30,
                        height: 30,
                        point: _selectedPoint!,
                        child: const _MapPointMarker(),
                      ),
                    if (_currentLocation != null)
                      Marker(
                        width: 42,
                        height: 42,
                        point: _currentLocation!,
                        child: const _CurrentLocationMarker(),
                      ),
                  ],
                ),
                RichAttributionWidget(
                  attributions: [
                    buildParaglidingAttribution(widget.mapViewType),
                  ],
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.14),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.12),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 76,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MapHeaderPanel(
                  title: _isWeatherMode ? '날씨 지도' : '비행 가능',
                  description: _isWeatherMode
                      ? '지도 지점이나 비행장을 누르면 현재 온도와 단기 예보를 바로 확인할 수 있습니다.'
                      : '주요 비행장을 기준으로 참고용 비행 상태와 현재 날씨를 함께 확인할 수 있습니다.',
                  registeredCount: widget.siteSnapshots.length,
                  importedCount: widget.importedSites.length,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 50,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: topChipItems.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) => topChipItems[index],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 16,
            top: 16,
            child: Column(
              children: [
                _MapControlButton(
                  icon: _refreshing ? null : Icons.refresh_rounded,
                  tooltip: '정보 새로고침',
                  onTap: _refreshing ? null : _refreshSelection,
                  loading: _refreshing,
                ),
                const SizedBox(height: 8),
                _MapControlButton(
                  tooltip: _followCurrentLocation ? '현재 위치 따라가기 중' : '현재 위치 보기',
                  onTap: _focusCurrentLocation,
                  icon: _locating
                      ? Icons.more_horiz_rounded
                      : _followCurrentLocation
                          ? Icons.gps_fixed_rounded
                          : Icons.my_location_rounded,
                ),
                const SizedBox(height: 8),
                MapViewToggle(
                  value: widget.mapViewType,
                  onChanged: widget.onMapViewTypeChanged,
                  compact: true,
                ),
              ],
            ),
          ),
          if (_locationError != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: panelData == null ? 18 : 250,
              child: _InlineMessage(
                icon: Icons.location_off_rounded,
                text: _locationError!,
              ),
            ),
          if (panelData != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: _MapDetailSheet(
                data: panelData,
                loading: _loadingArea || _loadingSelection,
                errorText: _selectionError ?? _areaError,
                onClose: () {
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _selectedSiteSnapshot = null;
                    _selectedImportedSite = null;
                    _selectedPoint = null;
                    _selectionArea = null;
                    _selectedSiteDetail = null;
                    _selectedAdvisory = null;
                    _selectedForecast = const [];
                    _selectionError = null;
                  });
                  widget.onSiteSelected(null);
                },
                onRefresh: _refreshSelection,
                onOpenDetail: panelData.registeredSiteId != null
                    ? () {
                        Navigator.pushNamed(
                          context,
                          AppRoutes.siteDetail,
                          arguments: SiteDetailArgs(
                            siteId: panelData.registeredSiteId,
                            pilotLevel: widget.user.pilotLevel,
                          ),
                        );
                      }
                    : panelData.importedSite == null
                        ? null
                        : () {
                            Navigator.pushNamed(
                              context,
                              AppRoutes.siteDetail,
                              arguments: SiteDetailArgs(
                                importedSite: panelData.importedSite,
                                pilotLevel: widget.user.pilotLevel,
                              ),
                            );
                          },
              ),
            ),
        ],
      ),
    );
  }
}

class _MapPanelData {
  const _MapPanelData({
    required this.title,
    required this.region,
    required this.point,
    required this.weather,
    required this.forecast,
    required this.advisory,
    required this.basisLabel,
    this.detail,
    this.distanceMeters,
    this.registeredSiteId,
    this.importedSite,
  });

  final String title;
  final String region;
  final LatLng point;
  final LiveWeatherSnapshot weather;
  final List<LiveWeatherForecastItem> forecast;
  final KoreaZoneAdvisory advisory;
  final SiteDetail? detail;
  final String basisLabel;
  final double? distanceMeters;
  final int? registeredSiteId;
  final ImportedParaglidingSite? importedSite;
}

class _MapDetailSheet extends StatelessWidget {
  const _MapDetailSheet({
    required this.data,
    required this.loading,
    required this.errorText,
    required this.onClose,
    required this.onRefresh,
    required this.onOpenDetail,
  });

  final _MapPanelData data;
  final bool loading;
  final String? errorText;
  final VoidCallback onClose;
  final VoidCallback onRefresh;
  final VoidCallback? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(data.advisory.status);
    final rule = data.detail?.rule;
    final allowedLabel = data.detail?.allowedDirectionRange;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 332),
        decoration: BoxDecoration(
          color: const Color(0xFFFDFEFF).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.74)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x18000000),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Material(
            color: const Color(0xFFFDFEFF).withValues(alpha: 0.95),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    data.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _StatusBadge(
                                  label: data.advisory.status.label,
                                  color: color,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${data.region} · ${data.basisLabel}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded),
                        tooltip: '닫기',
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (loading)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: LinearProgressIndicator(minHeight: 3),
                          ),
                        if (errorText != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _InlineMessage(
                              icon: Icons.info_outline_rounded,
                              text: errorText!,
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: _MetricCard(
                                label: '현재 온도',
                                value: formatTemperature(
                                  data.weather.temperatureCelsius,
                                ),
                                accentColor: const Color(0xFF2563EB),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _MetricCard(
                                label: '풍속',
                                value: data.weather.windSpeedMps == null
                                    ? '정보 준비 중'
                                    : formatSpeedMps(
                                        data.weather.windSpeedMps!),
                                accentColor: const Color(0xFF0F8B8D),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _MetricCard(
                                label: '풍향',
                                value: data.weather.windDirection == null
                                    ? '정보 준비 중'
                                    : formatHeading(
                                        data.weather.windDirection!.toDouble(),
                                      ),
                                accentColor: const Color(0xFF7C3AED),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _MetricCard(
                                label: '요약 상태',
                                value: data.weather.summary,
                                accentColor: color,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '시간대별 예보',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 132,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: data.forecast.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final item = data.forecast[index];
                              return _ForecastChip(item: item);
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '현재 비행 참고 상태',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              Text(data.advisory.summary),
                              const SizedBox(height: 8),
                              Text(
                                data.advisory.detail,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _InfoRow(
                          label: '관측 시각',
                          value: formatDateTime(data.weather.observedAt),
                        ),
                        if (data.distanceMeters != null)
                          _InfoRow(
                            label: '현재 위치와 거리',
                            value: formatDistanceMeters(data.distanceMeters!),
                          ),
                        if (allowedLabel != null &&
                            allowedLabel.trim().isNotEmpty)
                          _InfoRow(
                            label: '대표 풍향 참고',
                            value: allowedLabel.trim(),
                          ),
                        _InfoRow(
                          label: '데이터 출처',
                          value: data.weather.sourceLabel,
                        ),
                        if (rule != null && rule.notes.trim().isNotEmpty)
                          _InfoRow(
                            label: '주의 메모',
                            value: rule.notes.trim(),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          data.advisory.disclaimer,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF52616B),
                                  ),
                        ),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final narrow = constraints.maxWidth < 320;
                            final children = <Widget>[
                              if (!narrow)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: onRefresh,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('새로고침'),
                                  ),
                                )
                              else
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: onRefresh,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('새로고침'),
                                  ),
                                ),
                              if (onOpenDetail != null)
                                narrow
                                    ? SizedBox(
                                        width: double.infinity,
                                        child: FilledButton.icon(
                                          onPressed: onOpenDetail,
                                          icon: const Icon(
                                              Icons.open_in_new_rounded),
                                          label: const Text('사이트 상세'),
                                        ),
                                      )
                                    : Expanded(
                                        child: FilledButton.icon(
                                          onPressed: onOpenDetail,
                                          icon: const Icon(
                                              Icons.open_in_new_rounded),
                                          label: const Text('사이트 상세'),
                                        ),
                                      ),
                            ];

                            if (narrow) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  children.first,
                                  if (children.length > 1) ...[
                                    const SizedBox(height: 8),
                                    children[1],
                                  ],
                                ],
                              );
                            }

                            return Row(
                              children: [
                                children.first,
                                if (children.length > 1) ...[
                                  const SizedBox(width: 10),
                                  children[1],
                                ],
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MapHeaderPanel extends StatelessWidget {
  const _MapHeaderPanel({
    required this.title,
    required this.description,
    required this.registeredCount,
    required this.importedCount,
  });

  final String title;
  final String description;
  final int registeredCount;
  final int importedCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF143746).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.layers_outlined,
                  size: 18,
                  color: Color(0xFF143746),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF143746),
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF546973),
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LegendPill(
                color: const Color(0xFF2A9D8F),
                text: '주요 비행장 $registeredCount곳',
              ),
              _LegendPill(
                color: const Color(0xFF0F8B8D),
                text: '추가 이륙장 $importedCount곳',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendPill extends StatelessWidget {
  const _LegendPill({
    required this.color,
    required this.text,
  });

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 124),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF17324D),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapChoiceChip extends StatelessWidget {
  const _MapChoiceChip({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : const Color(0xFF17324D);
    return Material(
      color: selected ? accentColor : Colors.white.withValues(alpha: 0.86),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 140,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? accentColor
                  : const Color(0xFFD8E3E9).withValues(alpha: 0.92),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0E000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.92)
                      : const Color(0xFF607080),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.accentColor,
  });

  final String label;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.62)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: const Color(0xFF52616B)),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF17324D),
                ),
          ),
        ],
      ),
    );
  }
}

class _ForecastChip extends StatelessWidget {
  const _ForecastChip({required this.item});

  final LiveWeatherForecastItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4ECEF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatTime(item.time),
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            formatTemperature(item.temperatureCelsius),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            item.windSpeedMps == null
                ? '풍속 정보 준비 중'
                : formatSpeedMps(item.windSpeedMps!),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(
            formatHeading(item.windDirection.toDouble()),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                item.summaryText ?? '요약 준비 중',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: const Color(0xFF607080)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.tooltip,
    required this.onTap,
    this.icon,
    this.loading = false,
  });

  final IconData? icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFF143746).withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(icon, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: const Color(0xFF607080)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF52616B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SiteMarker extends StatelessWidget {
  const _SiteMarker({
    required this.selected,
    required this.color,
    required this.label,
    required this.showLabel,
    required this.onTap,
  });

  final bool selected;
  final Color color;
  final String label;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: selected ? 44 : 40,
            height: selected ? 44 : 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: selected ? 3 : 2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                selected ? Icons.flight_takeoff_rounded : Icons.place_rounded,
                color: Colors.white,
                size: selected ? 22 : 20,
              ),
            ),
          ),
          if (showLabel) ...[
            const SizedBox(height: 6),
            _MarkerLabel(
              text: label,
              backgroundColor: Colors.white,
            ),
          ],
        ],
      ),
    );
  }
}

class _ImportedSiteMarker extends StatelessWidget {
  const _ImportedSiteMarker({
    required this.selected,
    required this.color,
    required this.icon,
    required this.label,
    required this.showLabel,
    required this.onTap,
  });

  final bool selected;
  final Color color;
  final IconData icon;
  final String label;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: selected ? 40 : 36,
            height: selected ? 40 : 36,
            decoration: BoxDecoration(
              color: selected ? color : color.withValues(alpha: 0.92),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: selected ? 3 : 1.8,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                icon,
                color: Colors.white,
                size: selected ? 19 : 16,
              ),
            ),
          ),
          if (showLabel) ...[
            const SizedBox(height: 6),
            _MarkerLabel(
              text: label,
              backgroundColor: color.withValues(alpha: 0.16),
            ),
          ],
        ],
      ),
    );
  }
}

class _MarkerLabel extends StatelessWidget {
  const _MarkerLabel({
    required this.text,
    required this.backgroundColor,
  });

  final String text;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF17324D),
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _CurrentLocationMarker extends StatelessWidget {
  const _CurrentLocationMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB).withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      padding: const EdgeInsets.all(6),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF2563EB),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _MapPointMarker extends StatelessWidget {
  const _MapPointMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF17324D), width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: const Center(
        child: Icon(
          Icons.add_location_alt_rounded,
          size: 16,
          color: Color(0xFF17324D),
        ),
      ),
    );
  }
}

Color _statusColor(KoreaZoneStatus status) {
  return switch (status) {
    KoreaZoneStatus.flyable => const Color(0xFF2A9D8F),
    KoreaZoneStatus.caution => const Color(0xFFE9C46A),
    KoreaZoneStatus.confirmationRequired => const Color(0xFFE76F51),
    KoreaZoneStatus.potentiallyRestricted => const Color(0xFF8B5CF6),
  };
}

Color _importedMarkerColor(ImportedParaglidingSite site) {
  return switch (site.siteType) {
    ImportedParaglidingSiteType.takeoff => const Color(0xFF0F8B8D),
    ImportedParaglidingSiteType.practice => const Color(0xFF2563EB),
    ImportedParaglidingSiteType.landing => const Color(0xFF6B7280),
    ImportedParaglidingSiteType.site => const Color(0xFF7C3AED),
  };
}

IconData _importedSiteIcon(ImportedParaglidingSite site) {
  return switch (site.siteType) {
    ImportedParaglidingSiteType.takeoff => Icons.flight_takeoff_rounded,
    ImportedParaglidingSiteType.practice => Icons.school_rounded,
    ImportedParaglidingSiteType.landing => Icons.place_rounded,
    ImportedParaglidingSiteType.site => Icons.terrain_rounded,
  };
}
