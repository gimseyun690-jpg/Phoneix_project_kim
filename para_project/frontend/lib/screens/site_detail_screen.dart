import 'package:flutter/material.dart';

import '../core/utils.dart';
import '../models/app_models.dart';
import '../repositories/app_repository.dart';
import '../widgets/status_chip.dart';

class SiteDetailScreen extends StatefulWidget {
  const SiteDetailScreen({
    super.key,
    required this.repository,
    required this.siteId,
    required this.pilotLevel,
  });

  final AppRepository repository;
  final int siteId;
  final PilotLevel pilotLevel;

  @override
  State<SiteDetailScreen> createState() => _SiteDetailScreenState();
}

class _SiteDetailScreenState extends State<SiteDetailScreen> {
  late Future<SiteDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.getSiteDetail(
      siteId: widget.siteId,
      pilotLevel: widget.pilotLevel,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('사이트 상세')),
      body: FutureBuilder<SiteDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('사이트 상세를 불러오지 못했습니다.'));
          }

          final detail = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              detail.site.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          StatusChip(status: detail.site.assessment.status),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                          '${detail.site.region} | ${detail.site.difficulty.siteDifficultyLabel}'),
                      const SizedBox(height: 12),
                      Text(detail.description),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _MetricCard(
                              label: '평균 풍속',
                              value:
                                  '${detail.site.weather.averageWindSpeed.toStringAsFixed(1)} m/s'),
                          _MetricCard(
                              label: '풍향',
                              value: '${detail.site.weather.windDirection}°'),
                          _MetricCard(
                              label: '돌풍',
                              value:
                                  '${detail.site.weather.gustSpeed.toStringAsFixed(1)} m/s'),
                          _MetricCard(
                            label: '강수',
                            value: detail.site.weather.precipitationMm == null
                                ? '예보 없음'
                                : '${detail.site.weather.precipitationMm!.toStringAsFixed(1)} mm',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('허용 풍향: ${detail.allowedDirectionRange}'),
                      const SizedBox(height: 6),
                      Text(
                          '이륙장 ${detail.takeoffAltitudeM}m / 착륙장 ${detail.landingAltitudeM}m'),
                      const SizedBox(height: 6),
                      Text('기준 메모: ${detail.rule.notes}'),
                      const SizedBox(height: 6),
                      Text(
                          '관측 시각: ${formatDateTime(detail.site.weather.observedAt)}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '비행 판단 결과',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                          '${detail.site.assessment.score}점 | ${detail.site.assessment.summaryText}'),
                      const SizedBox(height: 12),
                      ...detail.site.assessment.reasons.map(
                        (reason) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('- '),
                              Expanded(child: Text(reason)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '시간대별 예보',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 12),
                      ...detail.site.weather.hourlyForecast.map(
                        (item) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F7F8),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              SizedBox(width: 64, child: Text(item.timeLabel)),
                              Expanded(
                                child: Text(
                                  '풍속 ${item.averageWindSpeed.toStringAsFixed(1)} / 풍향 ${item.windDirection}° / 돌풍 ${item.gustSpeed.toStringAsFixed(1)}',
                                ),
                              ),
                              Text(
                                item.precipitationMm == null
                                    ? '강수 -'
                                    : '${item.precipitationMm!.toStringAsFixed(1)} mm',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
