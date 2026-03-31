import 'package:flutter/material.dart';

import '../app.dart';
import '../core/flight_record_manager.dart';
import '../core/utils.dart';
import '../models/app_models.dart';
import '../repositories/app_repository.dart';
import '../widgets/site_card.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  late Future<HomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.getHome(pilotLevel: widget.user.pilotLevel);
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.repository.getHome(pilotLevel: widget.user.pilotLevel);
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HomeData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: FilledButton(
                onPressed: _reload, child: const Text('홈 데이터 다시 불러오기')),
          );
        }

        final data = snapshot.data!;

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
                                status:
                                    data.recommendedSite!.assessment.status),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(data.recommendedSite!.shortDescription),
                        const SizedBox(height: 12),
                        Text(
                            '위험 요약: ${data.recommendedSite!.assessment.reasons.join(' / ')}'),
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
                          child: const Text('상세 보기'),
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
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            activeSession == null
                                ? '이륙 전후 기록을 남기고, 저장 후 클럽원이나 강사에게 바로 공유할 수 있습니다.'
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
                '사이트 상태 카드',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              ...data.sites.map(
                (site) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SiteCard(
                    site: site,
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        AppRoutes.siteDetail,
                        arguments: SiteDetailArgs(
                          siteId: site.id,
                          pilotLevel: widget.user.pilotLevel,
                        ),
                      );
                    },
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
