import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../core/favorite_sites_store.dart';
import '../core/flight_record_manager.dart';
import '../core/kmz_site_catalog.dart';
import '../core/utils.dart';
import '../models/app_models.dart';
import '../repositories/app_repository.dart';
import '../widgets/status_chip.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.user,
    required this.flightRecordManager,
    required this.onOpenFlightRecorder,
  });

  final AppRepository repository;
  final AppUser user;
  final FlightRecordManager flightRecordManager;
  final VoidCallback onOpenFlightRecorder;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final FavoriteSitesStore _favoriteSitesStore = FavoriteSitesStore();
  late Future<_HomeBundle> _future;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = _loadBundle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    unawaited(_reload());
  }

  Future<_HomeBundle> _loadBundle() async {
    final results = await Future.wait<Object>([
      widget.repository.getHome(pilotLevel: widget.user.pilotLevel),
      widget.repository.getSites(pilotLevel: widget.user.pilotLevel),
      _favoriteSitesStore.loadFavorites(),
    ]);
    return _HomeBundle(
      homeData: results[0] as HomeData,
      registeredSites: results[1] as List<SiteSummary>,
      favorites: results[2] as List<FavoriteSiteEntry>,
      importedSites: await ImportedParaglidingSiteCatalog.load(),
    );
  }

  Future<void> _reload() async {
    setState(() {
      _future = _loadBundle();
    });
    await _future;
  }

  List<_FavoriteSiteCardData> _resolveFavoriteCards(_HomeBundle bundle) {
    final resolved = <_FavoriteSiteCardData>[];
    for (final entry in bundle.favorites) {
      if (entry.type == FavoriteSiteType.registered &&
          entry.registeredSiteId != null) {
        SiteSummary? matched;
        for (final site in bundle.registeredSites) {
          if (site.id == entry.registeredSiteId) {
            matched = site;
            break;
          }
        }
        if (matched != null) {
          resolved.add(_FavoriteSiteCardData.registered(matched));
        }
        continue;
      }

      if (entry.type == FavoriteSiteType.imported &&
          entry.importedSiteSourceId != null) {
        ImportedParaglidingSite? matched;
        for (final site in bundle.importedSites) {
          if (site.sourceId == entry.importedSiteSourceId) {
            matched = site;
            break;
          }
        }
        if (matched != null) {
          resolved.add(_FavoriteSiteCardData.imported(matched));
        }
      }
    }
    return resolved;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HomeBundle>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: FilledButton(
              onPressed: _reload,
              child: const Text('홈 데이터를 다시 불러오기'),
            ),
          );
        }

        final bundle = snapshot.data!;
        final data = bundle.homeData;
        final favorites = _resolveFavoriteCards(bundle);

        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '오늘 추천 사이트',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 12),
                      if (data.recommendedSite == null)
                        const Text('현재 추천 가능한 사이트가 없습니다.')
                      else ...[
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                data.recommendedSite!.name,
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                            ),
                            StatusChip(
                              status: data.recommendedSite!.assessment.status,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(data.recommendedSite!.shortDescription),
                        const SizedBox(height: 12),
                        Text(
                          '추천 요약: ${data.recommendedSite!.assessment.reasons.join(' / ')}',
                        ),
                        const SizedBox(height: 14),
                        FilledButton.tonal(
                          onPressed: () {
                            Navigator.pushNamed(
                              context,
                              AppRoutes.siteDetail,
                              arguments: SiteDetailArgs(
                                siteId: data.recommendedSite!.id,
                                pilotLevel: widget.user.pilotLevel,
                              ),
                            );
                          },
                          child: const Text('사이트 상세'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              AnimatedBuilder(
                animation: widget.flightRecordManager,
                builder: (context, _) {
                  final activeSession =
                      widget.flightRecordManager.activeSession;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '비행 기록',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            activeSession == null
                                ? '비행 이후 기록을 남기고 종료 후에는 바로 일지와 커뮤니티 글로 이어갈 수 있습니다.'
                                : '${activeSession.displaySiteName}에서 ${formatDuration(activeSession.duration)}째 기록 중입니다.',
                          ),
                          const SizedBox(height: 14),
                          FilledButton.tonal(
                            onPressed: widget.onOpenFlightRecorder,
                            child: Text(
                              activeSession == null ? '비행 기록 열기' : '진행 중 기록 보기',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              Text(
                '즐겨찾기',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '지도의 사이트 목록에서 검색한 뒤 별표를 누르면 홈에 바로 모아볼 수 있습니다.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (favorites.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '아직 즐겨찾기한 사이트가 없습니다.',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '지도 > 사이트 목록에서 검색하고 별표를 누르면 이곳에 빠르게 모아볼 수 있습니다.',
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...favorites.map(
                  (favorite) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _FavoriteSiteCard(
                      data: favorite,
                      pilotLevel: widget.user.pilotLevel,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                '최근 공지',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              ...data.notices.map(
                (notice) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text(notice.title),
                    subtitle: Text(
                      notice.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: notice.isPinned
                        ? const Icon(Icons.push_pin_outlined)
                        : null,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HomeBundle {
  const _HomeBundle({
    required this.homeData,
    required this.registeredSites,
    required this.favorites,
    required this.importedSites,
  });

  final HomeData homeData;
  final List<SiteSummary> registeredSites;
  final List<FavoriteSiteEntry> favorites;
  final List<ImportedParaglidingSite> importedSites;
}

class _FavoriteSiteCardData {
  const _FavoriteSiteCardData.registered(this.registeredSite)
      : importedSite = null;

  const _FavoriteSiteCardData.imported(this.importedSite)
      : registeredSite = null;

  final SiteSummary? registeredSite;
  final ImportedParaglidingSite? importedSite;

  bool get isRegistered => registeredSite != null;
}

class _FavoriteSiteCard extends StatelessWidget {
  const _FavoriteSiteCard({
    required this.data,
    required this.pilotLevel,
  });

  final _FavoriteSiteCardData data;
  final PilotLevel pilotLevel;

  @override
  Widget build(BuildContext context) {
    if (data.isRegistered) {
      final site = data.registeredSite!;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      site.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  StatusChip(status: site.assessment.status),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FavoriteMetaChip(text: site.region),
                  _FavoriteMetaChip(text: site.difficulty.siteDifficultyLabel),
                  _FavoriteMetaChip(
                    text: site.beginnerAllowed ? '초급 가능' : '초급 제한',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(site.shortDescription),
              const SizedBox(height: 8),
              Text(
                '현재 상태: ${site.assessment.summaryText}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    AppRoutes.siteDetail,
                    arguments: SiteDetailArgs(
                      siteId: site.id,
                      pilotLevel: pilotLevel,
                    ),
                  );
                },
                child: const Text('사이트 상세'),
              ),
            ],
          ),
        ),
      );
    }

    final site = data.importedSite!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    site.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F4F4),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '추가 이륙장',
                    style: TextStyle(
                      color: Color(0xFF0B5B5C),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FavoriteMetaChip(text: site.regionLabel),
                _FavoriteMetaChip(text: site.siteTypeLabel),
                _FavoriteMetaChip(text: site.preferredWindLabel),
              ],
            ),
            const SizedBox(height: 12),
            Text(site.summaryLine.isEmpty
                ? site.descriptionText
                : site.summaryLine),
            if (site.windNote?.trim().isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text(
                '바람 메모: ${site.windNote}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.tonal(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  AppRoutes.siteDetail,
                  arguments: SiteDetailArgs(
                    importedSite: site,
                    pilotLevel: pilotLevel,
                  ),
                );
              },
              child: const Text('사이트 상세'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoriteMetaChip extends StatelessWidget {
  const _FavoriteMetaChip({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text),
    );
  }
}
