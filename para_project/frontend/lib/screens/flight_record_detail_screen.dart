import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app.dart';
import '../core/community_manager.dart';
import '../core/flight_analysis_summary.dart';
import '../core/flight_record_manager.dart';
import '../core/korea_flight_guide.dart';
import '../core/map_view_type.dart';
import '../core/utils.dart';
import '../models/app_models.dart';
import '../repositories/app_repository.dart';
import '../widgets/flight_analysis_replay_section.dart';
import '../widgets/flight_map_view.dart';
import '../widgets/flight_trend_chart.dart';
import '../widgets/map_view_toggle.dart';

class FlightRecordDetailScreen extends StatefulWidget {
  const FlightRecordDetailScreen({
    super.key,
    required this.flightRecordManager,
    required this.communityManager,
    required this.repository,
    required this.user,
    required this.pilotLevel,
    required this.sessionId,
  });

  final FlightRecordManager flightRecordManager;
  final CommunityManager communityManager;
  final AppRepository repository;
  final AppUser user;
  final PilotLevel pilotLevel;
  final String sessionId;

  @override
  State<FlightRecordDetailScreen> createState() =>
      _FlightRecordDetailScreenState();
}

class _FlightRecordDetailScreenState extends State<FlightRecordDetailScreen> {
  final KoreaFlightGuide _flightGuide = const KoreaFlightGuide();
  final MapController _mapController = MapController();
  final MapViewPreferenceStore _mapViewPreferenceStore =
      MapViewPreferenceStore();
  late Future<_FlightAnalysisLoadResult?> _future;
  ParaglidingMapViewType _mapViewType = ParaglidingMapViewType.satellite;
  FlightAnalysisMomentType? _selectedMomentType;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _loadMapViewType();
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

  Future<_FlightAnalysisLoadResult?> _load() async {
    final detail =
        await widget.flightRecordManager.getSessionDetail(widget.sessionId);
    if (detail == null) {
      return null;
    }

    SiteDetail? siteDetail;
    if (detail.session.siteId != null) {
      try {
        siteDetail = await widget.repository.getSiteDetail(
          siteId: detail.session.siteId!,
          pilotLevel: widget.pilotLevel,
        );
      } catch (_) {
        siteDetail = null;
      }
    }

    final summary = FlightAnalysisSummary.fromDetail(detail);
    return _FlightAnalysisLoadResult(
      detail: detail,
      siteDetail: siteDetail,
      summary: summary,
    );
  }

  Future<void> _reload() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _share() async {
    final shared =
        await widget.flightRecordManager.shareSession(widget.sessionId);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(shared ? '비행 분석 요약을 공유했습니다.' : '비행 기록 공유에 실패했습니다.'),
      ),
    );
  }

  void _openJournalFlow() {
    final existingPost =
        widget.communityManager.findPostBySessionId(widget.sessionId);
    if (existingPost != null) {
      Navigator.pushNamed(
        context,
        AppRoutes.communityPostDetail,
        arguments: CommunityPostDetailArgs(postId: existingPost.id),
      );
      return;
    }

    Navigator.pushNamed(
      context,
      AppRoutes.flightJournalComposer,
      arguments: FlightJournalComposerArgs(sessionId: widget.sessionId),
    );
  }

  void _focusMoment(FlightAnalysisMoment moment) {
    setState(() {
      _selectedMomentType = moment.type;
    });
    _mapController.move(
      LatLng(moment.point.latitude, moment.point.longitude),
      14.8,
    );
  }

  FlightAnalysisMoment? _selectedMomentFor(FlightAnalysisSummary summary) {
    if (summary.keyMoments.isEmpty) {
      return null;
    }

    final selectedType =
        _selectedMomentType ?? FlightAnalysisMomentType.highestAltitude;
    for (final moment in summary.keyMoments) {
      if (moment.type == selectedType) {
        return moment;
      }
    }
    return summary.keyMoments.first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('비행 분석'),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '분석 다시 불러오기',
          ),
          IconButton(
            onPressed: _share,
            icon: const Icon(Icons.share_outlined),
            tooltip: '요약 공유',
          ),
        ],
      ),
      body: FutureBuilder<_FlightAnalysisLoadResult?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data;
          if (data == null) {
            return Center(
              child: FilledButton(
                onPressed: _reload,
                child: const Text('비행 분석 다시 불러오기'),
              ),
            );
          }

          return _buildAnalysisBody(context, data);
        },
      ),
    );
  }

  Widget _buildAnalysisBody(
    BuildContext context,
    _FlightAnalysisLoadResult data,
  ) {
    final detail = data.detail;
    final session = detail.session;
    final summary = data.summary;
    final siteDetail = data.siteDetail;
    final siteMetadata = _flightGuide.metadataForSite(
      siteId: session.siteId,
      siteName: session.siteName,
    );
    final resolvedStartedAt = detail.resolvedStartedAt;
    final resolvedEndedAt = detail.resolvedEndedAt;
    final resolvedDuration = detail.resolvedDuration;
    final selectedMoment = _selectedMomentFor(summary);
    final startPoint = summary.startPoint;
    final endPoint = summary.endPoint;
    final startAdvisory = startPoint == null
        ? null
        : _flightGuide.assess(
            latitude: startPoint.latitude,
            longitude: startPoint.longitude,
            selectedSite: siteDetail?.site,
            selectedSiteName: session.siteName,
          );

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _AnalysisHeroCard(
            session: session,
            summary: summary,
            startedAt: resolvedStartedAt,
            endedAt: resolvedEndedAt,
            duration: resolvedDuration,
          ),
          const SizedBox(height: 16),
          const _SectionTitle(
            title: '핵심 성과 요약',
            subtitle: '비행 후 가장 먼저 확인해야 하는 결과만 우선적으로 정리했습니다.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _AnalysisMetricCard.hero(
                label: '총 비행 시간',
                value: formatDuration(resolvedDuration),
                hint:
                    '${formatTime(resolvedStartedAt)} ~ ${resolvedEndedAt == null ? '기록 중' : formatTime(resolvedEndedAt)}',
              ),
              _AnalysisMetricCard.hero(
                label: '최고 고도',
                value: formatAltitudeMeters(session.maxAltitudeMeters),
                hint: summary.highestPoint == null
                    ? '최고 고도 시점 계산 중'
                    : '${formatTime(summary.highestPoint!.timestamp)} 도달',
              ),
              _AnalysisMetricCard(
                label: '총 이동 거리',
                value: formatDistanceMeters(session.totalDistanceMeters),
              ),
              _AnalysisMetricCard(
                label: '평균 속도',
                value: formatSpeedKmh(session.avgSpeedMps),
              ),
              _AnalysisMetricCard(
                label: '최고 속도',
                value: formatSpeedKmh(session.maxSpeedMps),
              ),
              _AnalysisMetricCard(
                label: '평균 고도',
                value: formatAltitudeMeters(summary.averageAltitudeMeters),
              ),
              _AnalysisMetricCard(
                label: '누적 상승',
                value: formatAltitudeMeters(summary.totalAltitudeGainMeters),
              ),
              _AnalysisMetricCard(
                label: '누적 하강',
                value: formatAltitudeMeters(summary.totalAltitudeLossMeters),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionTitle(
            title: '지도 기반 비행 리뷰',
            subtitle: '비행 경로와 핵심 시점을 지도에서 바로 다시 볼 수 있습니다.',
          ),
          const SizedBox(height: 12),
          _buildReplaySection(
            context: context,
            detail: detail,
            summary: summary,
            siteMetadata: siteMetadata,
            selectedMoment: selectedMoment,
          ),
          const SizedBox(height: 20),
          const _SectionTitle(
            title: '고도와 속도 흐름',
            subtitle: '한 번의 비행에서 고도와 속도가 어떻게 변했는지 빠르게 훑어볼 수 있게 구성했습니다.',
          ),
          const SizedBox(height: 12),
          FlightTrendChart(
            title: '시간 대비 고도 변화',
            samples: summary.timelineSamples,
            color: const Color(0xFF2A9D8F),
            unitLabel: '고도',
            valueBuilder: (sample) => sample.altitudeMeters,
            labelBuilder: formatAltitudeMeters,
          ),
          const SizedBox(height: 12),
          FlightTrendChart(
            title: '시간 대비 속도 변화',
            samples: summary.timelineSamples,
            color: const Color(0xFFE76F51),
            unitLabel: '속도',
            valueBuilder: (sample) => sample.speedMps,
            labelBuilder: formatSpeedKmh,
          ),
          const SizedBox(height: 20),
          const _SectionTitle(
            title: '이번 비행 해석',
            subtitle: '원시 숫자보다 한눈에 이해되는 요약과 특징을 먼저 제공합니다.',
          ),
          const SizedBox(height: 12),
          _buildInsightSection(context, session: session, summary: summary),
          const SizedBox(height: 20),
          const _SectionTitle(
            title: '환경과 참고 정보',
            subtitle: '비행 자체가 중심이며, 기상과 구역 정보는 해석을 돕는 참고 정보로만 표시합니다.',
          ),
          const SizedBox(height: 12),
          _buildEnvironmentSection(
            context: context,
            siteDetail: siteDetail,
            siteMetadata: siteMetadata,
            startAdvisory: startAdvisory,
          ),
          const SizedBox(height: 16),
          _buildActionButtons(context, siteDetail: siteDetail),
          if (startPoint != null || endPoint != null) ...[
            const SizedBox(height: 12),
            _buildCoordinateFooter(
              context,
              startPoint: startPoint,
              endPoint: endPoint,
              summary: summary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReplaySection({
    required BuildContext context,
    required FlightSessionDetail detail,
    required FlightAnalysisSummary summary,
    required KoreaFlightSiteMetadata? siteMetadata,
    required FlightAnalysisMoment? selectedMoment,
  }) {
    return FlightAnalysisReplaySection(
      detail: detail,
      summary: summary,
      siteMetadata: siteMetadata,
      selectedMoment: selectedMoment,
      onFocusMoment: _focusMoment,
      mapController: _mapController,
      mapViewType: _mapViewType,
      onMapViewTypeChanged: _changeMapViewType,
    );
  }

  // ignore: unused_element
  Widget _buildMapSection({
    required BuildContext context,
    required FlightSessionDetail detail,
    required FlightAnalysisSummary summary,
    required KoreaFlightSiteMetadata? siteMetadata,
    required FlightAnalysisMoment? selectedMoment,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final moment in summary.keyMoments) ...[
                    _MomentChip(
                      moment: moment,
                      isSelected: selectedMoment?.type == moment.type,
                      onTap: () => _focusMoment(moment),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Stack(
              children: [
                FlightMapView(
                  points: detail.points,
                  height: 340,
                  mapController: _mapController,
                  mapViewType: _mapViewType,
                  showLegend: true,
                  showCurrentMarker: false,
                  emptyMessage: '경로 데이터가 아직 충분하지 않습니다.',
                  siteLatitude: siteMetadata?.latitude,
                  siteLongitude: siteMetadata?.longitude,
                  siteLabel: siteMetadata?.name,
                  highlightLatitude: selectedMoment?.point.latitude,
                  highlightLongitude: selectedMoment?.point.longitude,
                  highlightLabel: selectedMoment?.title,
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: MapViewToggle(
                    value: _mapViewType,
                    onChanged: _changeMapViewType,
                  ),
                ),
                if (selectedMoment != null)
                  Positioned(
                    left: 12,
                    right: 96,
                    bottom: 12,
                    child: _SelectedMomentOverlay(
                      title: selectedMoment.title,
                      subtitle: selectedMoment.subtitle,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightSection(
    BuildContext context, {
    required FlightSession session,
    required FlightAnalysisSummary summary,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '이번 비행 요약',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            Text(summary.overview),
            const SizedBox(height: 16),
            for (final insight in summary.insights) ...[
              _InsightTile(
                title: insight.title,
                description: insight.description,
              ),
              if (insight != summary.insights.last) const SizedBox(height: 10),
            ],
            if (session.memo.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '파일럿 메모',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(session.memo.trim()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEnvironmentSection({
    required BuildContext context,
    required SiteDetail? siteDetail,
    required KoreaFlightSiteMetadata? siteMetadata,
    required KoreaZoneAdvisory? startAdvisory,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '현재 사이트 기준 참고 정보',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            if (siteDetail == null)
              const Text(
                '현재 저장 구조에는 당시 기상이 보관되지 않아 현재 사이트 기준 참고 정보만 표시합니다.',
              )
            else ...[
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _AnalysisMetricCard(
                    label: '현재 풍속',
                    value: formatSpeedMps(
                      siteDetail.site.weather.averageWindSpeed,
                    ),
                  ),
                  _AnalysisMetricCard(
                    label: '현재 풍향',
                    value: formatHeading(
                      siteDetail.site.weather.windDirection.toDouble(),
                    ),
                  ),
                  _AnalysisMetricCard(
                    label: '현재 돌풍',
                    value: formatSpeedMps(siteDetail.site.weather.gustSpeed),
                  ),
                  _AnalysisMetricCard(
                    label: '현재 상태',
                    value: siteDetail.site.assessment.status.label,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('참고용 요약: ${siteDetail.site.weather.summary}'),
              const SizedBox(height: 6),
              Text(
                '관측 시각 ${formatDateTime(siteDetail.site.weather.observedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (startAdvisory != null) ...[
              const SizedBox(height: 16),
              Text(
                '비행장 기준 참고 구역',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              Text(startAdvisory.summary),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetaPill(label: '상태', value: startAdvisory.status.label),
                  _MetaPill(
                    label: '신뢰 수준',
                    value: startAdvisory.confidence.label,
                  ),
                  if (startAdvisory.distanceMeters != null)
                    _MetaPill(
                      label: '기준 비행장 거리',
                      value:
                          formatDistanceMeters(startAdvisory.distanceMeters!),
                    ),
                ],
              ),
            ],
            if (siteMetadata != null) ...[
              const SizedBox(height: 16),
              Text(
                '안전 참고',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              Text(siteMetadata.safetyText),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context, {
    required SiteDetail? siteDetail,
  }) {
    final existingPost =
        widget.communityManager.findPostBySessionId(widget.sessionId);
    final feedCount = siteDetail == null
        ? 0
        : widget.communityManager.siteFeedCount(
            siteId: siteDetail.site.id,
            siteName: siteDetail.site.name,
          );
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F7F8),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                existingPost == null
                    ? '분석 내용을 바탕으로 비행일지 초안을 바로 만들 수 있습니다.'
                    : '이 비행은 이미 커뮤니티 글과 연결되어 있습니다.',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                existingPost == null
                    ? '비행 시간, 최고 고도, 이동 거리, 사이트 정보는 자동으로 채워집니다. 사진을 추가하고 이륙장 피드에 바로 공유해 보세요.'
                    : '분석 결과와 비행일지가 같은 흐름으로 연결되어 있어 다시 열어 피드백과 댓글을 확인할 수 있습니다.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.45,
                    ),
              ),
              if (siteDetail != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetaPill(
                      label: '연결 이륙장',
                      value: siteDetail.site.name,
                    ),
                    _MetaPill(
                      label: '피드 글 수',
                      value: '$feedCount개',
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _share,
                icon: const Icon(Icons.share_outlined),
                label: const Text('요약 공유'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('기록 목록으로'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _openJournalFlow,
                icon: Icon(
                  existingPost == null
                      ? Icons.edit_note_rounded
                      : Icons.forum_outlined,
                ),
                label: Text(
                  existingPost == null ? '분석 기반 비행일지 작성' : '작성한 글 보기',
                ),
              ),
            ),
            if (siteDetail != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.siteCommunity,
                      arguments: SiteCommunityArgs(
                        siteId: siteDetail.site.id,
                        siteName: siteDetail.site.name,
                      ),
                    );
                  },
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text('이륙장 피드'),
                ),
              ),
            ],
          ],
        ),
        if (siteDetail != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  AppRoutes.siteDetail,
                  arguments: SiteDetailArgs(
                    siteId: siteDetail.site.id,
                    pilotLevel: widget.pilotLevel,
                  ),
                );
              },
              icon: const Icon(Icons.landscape_outlined),
              label: const Text('사이트 상세 보기'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCoordinateFooter(
    BuildContext context, {
    required FlightTrackPoint? startPoint,
    required FlightTrackPoint? endPoint,
    required FlightAnalysisSummary summary,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (startPoint != null)
              _MetaPill(
                label: '시작 좌표',
                value: formatCoordinates(
                  startPoint.latitude,
                  startPoint.longitude,
                ),
              ),
            if (endPoint != null)
              _MetaPill(
                label: '종료 좌표',
                value: formatCoordinates(
                  endPoint.latitude,
                  endPoint.longitude,
                ),
              ),
            _MetaPill(
              label: '가장 긴 구간 이동',
              value: formatDistanceMeters(summary.longestSegmentMeters),
            ),
            _MetaPill(
              label: '기록 품질 참고',
              value: summary.averageAccuracyMeters == null
                  ? '정확도 부족'
                  : formatAccuracy(summary.averageAccuracyMeters),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlightAnalysisLoadResult {
  const _FlightAnalysisLoadResult({
    required this.detail,
    required this.siteDetail,
    required this.summary,
  });

  final FlightSessionDetail detail;
  final SiteDetail? siteDetail;
  final FlightAnalysisSummary summary;
}

class _AnalysisHeroCard extends StatelessWidget {
  const _AnalysisHeroCard({
    required this.session,
    required this.summary,
    required this.startedAt,
    required this.endedAt,
    required this.duration,
  });

  final FlightSession session;
  final FlightAnalysisSummary summary;
  final DateTime startedAt;
  final DateTime? endedAt;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF264653),
            Color(0xFF2A9D8F),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.displaySiteName,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            '${formatDate(startedAt)} · ${session.displayRegion}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _HeroInfo(label: '시작', value: formatTime(startedAt)),
              _HeroInfo(
                label: '종료',
                value: endedAt == null ? '기록 중' : formatTime(endedAt!),
              ),
              _HeroInfo(label: '총 비행 시간', value: formatDuration(duration)),
              _HeroInfo(
                label: '분석 품질',
                value: summary.averageAccuracyMeters == null
                    ? '참고용'
                    : summary.averageAccuracyMeters! <= 10
                        ? '양호'
                        : summary.averageAccuracyMeters! <= 25
                            ? '보통'
                            : '주의',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroInfo extends StatelessWidget {
  const _HeroInfo({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _AnalysisMetricCard extends StatelessWidget {
  const _AnalysisMetricCard({
    required this.label,
    required this.value,
  })  : hint = null,
        isHero = false;

  const _AnalysisMetricCard.hero({
    required this.label,
    required this.value,
    this.hint,
  }) : isHero = true;

  final String label;
  final String value;
  final String? hint;
  final bool isHero;

  @override
  Widget build(BuildContext context) {
    final width = isHero ? 220.0 : 150.0;
    return Container(
      width: width,
      padding: EdgeInsets.all(isHero ? 16 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Text(
            value,
            style: (isHero
                    ? Theme.of(context).textTheme.headlineSmall
                    : Theme.of(context).textTheme.titleLarge)
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(
              hint!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MomentChip extends StatelessWidget {
  const _MomentChip({
    required this.moment,
    required this.isSelected,
    required this.onTap,
  });

  final FlightAnalysisMoment moment;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF264653) : const Color(0xFFF4F7F8),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              moment.title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: isSelected ? Colors.white : null,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              moment.subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.82)
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedMomentOverlay extends StatelessWidget {
  const _SelectedMomentOverlay({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                ),
          ),
        ],
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F8),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(description),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
          children: [
            TextSpan(
              text: '$label  ',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
