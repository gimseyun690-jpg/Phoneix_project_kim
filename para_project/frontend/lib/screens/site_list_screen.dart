import 'package:flutter/material.dart';

import '../app.dart';
import '../core/favorite_sites_store.dart';
import '../core/kmz_site_catalog.dart';
import '../models/app_models.dart';
import '../repositories/app_repository.dart';
import '../widgets/status_chip.dart';

class SiteListScreen extends StatefulWidget {
  const SiteListScreen({
    super.key,
    required this.repository,
    required this.user,
    required this.importedSites,
    this.selectedSite,
    this.onSelectSiteForMap,
  });

  final AppRepository repository;
  final AppUser user;
  final List<ImportedParaglidingSite> importedSites;
  final MapSiteSelection? selectedSite;
  final ValueChanged<MapSiteSelection>? onSelectSiteForMap;

  @override
  State<SiteListScreen> createState() => _SiteListScreenState();
}

class _SiteListScreenState extends State<SiteListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FavoriteSitesStore _favoriteSitesStore = FavoriteSitesStore();

  late Future<List<SiteSummary>> _future;
  Set<String> _favoriteKeys = <String>{};
  bool _favoritesOnly = false;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.getSites(pilotLevel: widget.user.pilotLevel);
    _loadFavorites();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final favorites = await _favoriteSitesStore.loadFavorites();
    if (!mounted) {
      return;
    }
    setState(() {
      _favoriteKeys = favorites.map((item) => item.storageKey).toSet();
    });
  }

  void _search() {
    setState(() {
      _future = widget.repository.getSites(
        pilotLevel: widget.user.pilotLevel,
        query: _searchController.text.trim(),
      );
    });
  }

  bool _isRegisteredFavorite(int siteId) =>
      _favoriteKeys.contains(FavoriteSiteEntry.registered(siteId).storageKey);

  bool _isImportedFavorite(String sourceId) =>
      _favoriteKeys.contains(FavoriteSiteEntry.imported(sourceId).storageKey);

  Future<void> _toggleFavorite(FavoriteSiteEntry entry, String siteName) async {
    final existed = _favoriteKeys.contains(entry.storageKey);
    final updatedFavorites = await _favoriteSitesStore.toggle(entry);
    if (!mounted) {
      return;
    }
    setState(() {
      _favoriteKeys = updatedFavorites.map((item) => item.storageKey).toSet();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existed ? '$siteName 즐겨찾기를 해제했습니다.' : '$siteName 즐겨찾기를 추가했습니다.',
        ),
      ),
    );
  }

  List<ImportedParaglidingSite> _filterImportedSites() {
    final query = _searchController.text.trim();
    var filtered = widget.importedSites.where((site) {
      if (query.isEmpty) {
        return true;
      }
      return site.name.contains(query) ||
          site.regionHint.contains(query) ||
          (site.windNote?.contains(query) ?? false);
    }).toList(growable: false);

    if (_favoritesOnly) {
      filtered = filtered
          .where((site) => _isImportedFavorite(site.sourceId))
          .toList(growable: false);
    }
    return filtered;
  }

  List<SiteSummary> _filterRegisteredSites(List<SiteSummary> sites) {
    if (!_favoritesOnly) {
      return sites;
    }
    return sites
        .where((site) => _isRegisteredFavorite(site.id))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final importedSites = _filterImportedSites();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onSubmitted: (_) => _search(),
                      decoration: const InputDecoration(
                        hintText: '비행장 이름이나 지역명을 검색해보세요',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _search,
                    child: const Text('검색'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  FilterChip(
                    label: const Text('즐겨찾기만 보기'),
                    selected: _favoritesOnly,
                    onSelected: (value) {
                      setState(() {
                        _favoritesOnly = value;
                      });
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '검색 후 별표를 누르면 홈 즐겨찾기에 바로 추가됩니다.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<SiteSummary>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Center(
                  child: Text('사이트 목록을 불러오지 못했습니다.'),
                );
              }

              final registeredSites = _filterRegisteredSites(
                  snapshot.data ?? const <SiteSummary>[]);
              if (registeredSites.isEmpty && importedSites.isEmpty) {
                return Center(
                  child: Text(
                    _favoritesOnly ? '즐겨찾기한 사이트가 없습니다.' : '검색 결과가 없습니다.',
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (registeredSites.isNotEmpty) ...[
                    const _SectionHeader(
                      title: '주요 비행장',
                      description: '현재 상태와 날씨 요약, 비행 참고 정보를 함께 확인할 수 있습니다.',
                    ),
                    const SizedBox(height: 12),
                    ...registeredSites.map(_buildRegisteredCard),
                  ],
                  if (importedSites.isNotEmpty) ...[
                    if (registeredSites.isNotEmpty) const SizedBox(height: 6),
                    _SectionHeader(
                      title: '추가 이륙장',
                      description:
                          '주변에서 많이 찾는 이륙장 ${importedSites.length}곳을 함께 볼 수 있습니다. 즐겨찾기에 담아 홈에서 빠르게 확인할 수 있습니다.',
                    ),
                    const SizedBox(height: 12),
                    ...importedSites.map(_buildImportedCard),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRegisteredCard(SiteSummary site) {
    final selected = widget.selectedSite?.matchesRegistered(site.id) ?? false;
    final isFavorite = _isRegisteredFavorite(site.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: selected ? const Color(0xFFF2F8FB) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? const Color(0xFF2F6B7A) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                          site.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _LabelChip(text: site.region),
                            _LabelChip(
                              text: site.difficulty.siteDifficultyLabel,
                            ),
                            _LabelChip(
                              text: site.beginnerAllowed ? '초급 가능' : '초급 제한',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _toggleFavorite(
                      FavoriteSiteEntry.registered(site.id),
                      site.name,
                    ),
                    icon: Icon(
                      isFavorite
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: isFavorite
                          ? const Color(0xFFE0A106)
                          : const Color(0xFF607080),
                    ),
                    tooltip: isFavorite ? '즐겨찾기 해제' : '즐겨찾기 추가',
                  ),
                  StatusChip(status: site.assessment.status),
                ],
              ),
              const SizedBox(height: 12),
              Text(site.shortDescription),
              const SizedBox(height: 12),
              Text(
                '현재 요약: ${site.assessment.summaryText}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  if (widget.onSelectSiteForMap != null)
                    OutlinedButton.icon(
                      onPressed: () => widget.onSelectSiteForMap!(
                        MapSiteSelection.registered(site.id),
                      ),
                      icon: const Icon(Icons.map_rounded, size: 18),
                      label: Text(selected ? '지도에서 선택됨' : '지도에서 보기'),
                    ),
                  if (widget.onSelectSiteForMap != null)
                    const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          AppRoutes.siteDetail,
                          arguments: SiteDetailArgs(
                            siteId: site.id,
                            pilotLevel: widget.user.pilotLevel,
                          ),
                        );
                      },
                      child: const Text('사이트 상세'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImportedCard(ImportedParaglidingSite site) {
    final selected =
        widget.selectedSite?.matchesImported(site.sourceId) ?? false;
    final isFavorite = _isImportedFavorite(site.sourceId);
    final quality = site.dataQuality;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: selected ? const Color(0xFFF0FBFB) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? const Color(0xFF0F8B8D) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                          site.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _LabelChip(text: site.regionLabel),
                            _LabelChip(text: site.siteTypeLabel),
                            _LabelChip(text: site.preferredWindLabel),
                            _QualityChip(quality: quality),
                            if (site.windyUrl != null)
                              const _LabelChip(text: '상세 예보 링크'),
                            if (site.windguruUrl != null)
                              const _LabelChip(text: '바람 예보 링크'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _toggleFavorite(
                      FavoriteSiteEntry.imported(site.sourceId),
                      site.name,
                    ),
                    icon: Icon(
                      isFavorite
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: isFavorite
                          ? const Color(0xFFE0A106)
                          : const Color(0xFF607080),
                    ),
                    tooltip: isFavorite ? '즐겨찾기 해제' : '즐겨찾기 추가',
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
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
              const SizedBox(height: 12),
              Text(
                site.summaryLine.isEmpty
                    ? (site.descriptionText.trim().isEmpty
                        ? quality.summaryText
                        : site.descriptionText)
                    : site.summaryLine,
              ),
              const SizedBox(height: 8),
              Text(
                quality.summaryText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF56707C),
                    ),
              ),
              if (site.stationLabel != null) ...[
                const SizedBox(height: 8),
                Text(
                  '가까운 관측 지점: ${site.stationLabel}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  if (widget.onSelectSiteForMap != null)
                    OutlinedButton.icon(
                      onPressed: () => widget.onSelectSiteForMap!(
                        MapSiteSelection.imported(site.sourceId),
                      ),
                      icon: const Icon(Icons.map_rounded, size: 18),
                      label: Text(selected ? '지도에서 선택됨' : '지도에서 보기'),
                    ),
                  if (widget.onSelectSiteForMap != null)
                    const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          AppRoutes.siteDetail,
                          arguments: SiteDetailArgs(
                            importedSite: site,
                            pilotLevel: widget.user.pilotLevel,
                          ),
                        );
                      },
                      child: const Text('사이트 상세'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _LabelChip extends StatelessWidget {
  const _LabelChip({
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

class _QualityChip extends StatelessWidget {
  const _QualityChip({required this.quality});

  final ImportedSiteDataQuality quality;

  @override
  Widget build(BuildContext context) {
    final colors = switch (quality.level) {
      ImportedSiteDataQualityLevel.rich => (
          background: const Color(0xFFE7F4EE),
          foreground: const Color(0xFF217A4C),
        ),
      ImportedSiteDataQualityLevel.moderate => (
          background: const Color(0xFFFFF2DB),
          foreground: const Color(0xFF8C5B00),
        ),
      ImportedSiteDataQualityLevel.limited => (
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
        quality.label,
        style: TextStyle(
          color: colors.foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
