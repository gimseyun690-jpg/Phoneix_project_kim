import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'status_chip.dart';

class SiteCard extends StatelessWidget {
  const SiteCard({
    super.key,
    required this.site,
    required this.onTap,
  });

  final SiteSummary site;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
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
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${site.region} | ${site.difficulty.siteDifficultyLabel}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  StatusChip(status: site.assessment.status),
                ],
              ),
              const SizedBox(height: 12),
              Text(site.shortDescription),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricPill(
                      label: '평균풍속',
                      value:
                          '${site.weather.averageWindSpeed.toStringAsFixed(1)} m/s'),
                  _MetricPill(
                      label: '풍향', value: '${site.weather.windDirection}°'),
                  _MetricPill(
                      label: '돌풍',
                      value:
                          '${site.weather.gustSpeed.toStringAsFixed(1)} m/s'),
                  _MetricPill(label: '점수', value: '${site.assessment.score}점'),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                site.assessment.summaryText,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('$label $value'),
    );
  }
}
