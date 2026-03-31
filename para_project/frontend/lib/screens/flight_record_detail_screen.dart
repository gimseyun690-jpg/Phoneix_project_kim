import 'package:flutter/material.dart';

import '../core/flight_record_manager.dart';
import '../core/utils.dart';
import '../models/app_models.dart';
import '../widgets/flight_path_preview.dart';

class FlightRecordDetailScreen extends StatefulWidget {
  const FlightRecordDetailScreen({
    super.key,
    required this.flightRecordManager,
    required this.sessionId,
  });

  final FlightRecordManager flightRecordManager;
  final String sessionId;

  @override
  State<FlightRecordDetailScreen> createState() =>
      _FlightRecordDetailScreenState();
}

class _FlightRecordDetailScreenState extends State<FlightRecordDetailScreen> {
  late Future<FlightSessionDetail?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.flightRecordManager.getSessionDetail(widget.sessionId);
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.flightRecordManager.getSessionDetail(widget.sessionId);
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
        content: Text(shared ? '비행 기록을 공유했습니다.' : '비행 기록 공유에 실패했습니다.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('비행 기록 상세'),
        actions: [
          IconButton(
            onPressed: _share,
            icon: const Icon(Icons.share_outlined),
            tooltip: '공유',
          ),
        ],
      ),
      body: FutureBuilder<FlightSessionDetail?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final detail = snapshot.data;
          if (detail == null) {
            return Center(
              child: FilledButton(
                onPressed: _reload,
                child: const Text('비행 기록 다시 불러오기'),
              ),
            );
          }

          final session = detail.session;

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
                          session.displaySiteName,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${formatDate(session.startedAt)} | ${session.displayRegion} | ${session.status.label}',
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _DetailStatCard(
                              label: '비행 시간',
                              value: formatDuration(session.duration),
                            ),
                            _DetailStatCard(
                              label: '총 거리',
                              value: formatDistanceMeters(
                                  session.totalDistanceMeters),
                            ),
                            _DetailStatCard(
                              label: '최고 고도',
                              value: formatAltitudeMeters(
                                  session.maxAltitudeMeters),
                            ),
                            _DetailStatCard(
                              label: '평균 속도',
                              value: formatSpeedMps(session.avgSpeedMps),
                            ),
                            _DetailStatCard(
                              label: '최고 속도',
                              value: formatSpeedMps(session.maxSpeedMps),
                            ),
                            _DetailStatCard(
                              label: '기록 포인트',
                              value: '${session.trackPointCount}개',
                            ),
                          ],
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
                          '경로 요약',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        FlightPathPreview(points: detail.points),
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
                          '비행 메모',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        Text(session.memo.trim().isEmpty
                            ? '저장된 메모가 없습니다.'
                            : session.memo.trim()),
                        const SizedBox(height: 16),
                        Text(
                          '세부 정보',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        _InfoRow(
                          label: '시작 시각',
                          value: formatDateTime(session.startedAt),
                        ),
                        _InfoRow(
                          label: '종료 시각',
                          value: session.endedAt == null
                              ? '기록 중'
                              : formatDateTime(session.endedAt!),
                        ),
                        _InfoRow(
                          label: '최저 고도',
                          value:
                              formatAltitudeMeters(session.minAltitudeMeters),
                        ),
                        _InfoRow(
                          label: '마지막 정확도',
                          value: session.lastAccuracyMeters == null
                              ? '정보 없음'
                              : '${session.lastAccuracyMeters!.toStringAsFixed(0)}m',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('비행 기록 공유'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DetailStatCard extends StatelessWidget {
  const _DetailStatCard({
    required this.label,
    required this.value,
  });

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
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
