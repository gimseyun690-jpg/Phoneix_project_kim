import 'package:flutter/material.dart';

import '../app.dart';
import '../core/flight_record_manager.dart';
import '../core/utils.dart';
import '../models/app_models.dart';
import '../repositories/app_repository.dart';

class FlightRecordsScreen extends StatefulWidget {
  const FlightRecordsScreen({
    super.key,
    required this.repository,
    required this.user,
    required this.flightRecordManager,
  });

  final AppRepository repository;
  final AppUser user;
  final FlightRecordManager flightRecordManager;

  @override
  State<FlightRecordsScreen> createState() => _FlightRecordsScreenState();
}

class _FlightRecordsScreenState extends State<FlightRecordsScreen> {
  bool _loading = true;
  String? _screenError;
  List<SiteSummary> _sites = [];
  int? _selectedSiteId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _screenError = null;
    });

    try {
      await widget.flightRecordManager.initialize(userId: widget.user.id);
      final sites =
          await widget.repository.getSites(pilotLevel: widget.user.pilotLevel);
      setState(() {
        _sites = sites;
      });
    } catch (_) {
      setState(() {
        _screenError = '비행 기록 화면을 준비하지 못했습니다.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  SiteSummary? get _selectedSite {
    if (_selectedSiteId == null) {
      return null;
    }
    for (final site in _sites) {
      if (site.id == _selectedSiteId) {
        return site;
      }
    }
    return null;
  }

  Future<void> _startRecording() async {
    final started = await widget.flightRecordManager.startRecording(
      userId: widget.user.id,
      site: _selectedSite,
    );
    if (!mounted) {
      return;
    }
    if (started) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비행 기록을 시작했습니다.')),
      );
    }
  }

  Future<void> _stopRecording() async {
    final controller = TextEditingController();
    final memo = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('비행 기록 저장'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '메모',
            hintText: '강한 상승대, 접근 패턴, 참고 사항 등을 남길 수 있습니다.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (memo == null) {
      return;
    }

    final session = await widget.flightRecordManager.stopRecording(memo: memo);
    if (!mounted) {
      return;
    }

    if (session != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비행 기록을 저장했습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_screenError != null) {
      return Center(
        child: FilledButton(
          onPressed: _load,
          child: const Text('다시 불러오기'),
        ),
      );
    }

    return AnimatedBuilder(
      animation: widget.flightRecordManager,
      builder: (context, _) {
        final manager = widget.flightRecordManager;
        final activeSession = manager.activeSession;
        final lastPoint = manager.lastPoint;

        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
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
                              activeSession == null ? '새 비행 기록' : '비행 기록 진행 중',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (activeSession != null) ...[
                            const Icon(Icons.fiber_manual_record,
                                color: Color(0xFFE76F51), size: 14),
                            const SizedBox(width: 6),
                            const Text('기록 중'),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (activeSession == null) ...[
                        Text(
                          '앱이 열린 상태에서 위치를 기록하고, 종료 시 기기에 먼저 저장합니다.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int?>(
                          initialValue: _selectedSiteId,
                          decoration:
                              const InputDecoration(labelText: '비행 사이트'),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('사이트 미지정'),
                            ),
                            ..._sites.map(
                              (site) => DropdownMenuItem<int?>(
                                value: site.id,
                                child: Text('${site.region} | ${site.name}'),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedSiteId = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed:
                                manager.isWorking ? null : _startRecording,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(
                                manager.isWorking ? '준비 중...' : '비행 기록 시작'),
                          ),
                        ),
                      ] else ...[
                        Text(
                          '${activeSession.displayRegion} / ${activeSession.displaySiteName}',
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _StatCard(
                              label: '비행 시간',
                              value: formatDuration(activeSession.duration),
                            ),
                            _StatCard(
                              label: '총 거리',
                              value: formatDistanceMeters(
                                  activeSession.totalDistanceMeters),
                            ),
                            _StatCard(
                              label: '최고 고도',
                              value: formatAltitudeMeters(
                                  activeSession.maxAltitudeMeters),
                            ),
                            _StatCard(
                              label: '현재 고도',
                              value: formatAltitudeMeters(lastPoint?.altitude ??
                                  activeSession.maxAltitudeMeters),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed:
                                manager.isWorking ? null : _stopRecording,
                            icon: const Icon(Icons.stop_circle_outlined),
                            label:
                                Text(manager.isWorking ? '저장 중...' : '기록 저장'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F7F8),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          '현재 MVP는 전경 기록 방식입니다. 앱이 닫히거나 백그라운드에서 강제 종료되면 위치 기록이 중단될 수 있습니다.',
                        ),
                      ),
                      if (manager.errorMessage != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          manager.errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      if (manager.statusMessage != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          manager.statusMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '저장된 비행 기록',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if (manager.sessions.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('저장된 비행 기록이 없습니다.'),
                  ),
                ),
              ...manager.sessions.map(
                (session) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(session.displaySiteName),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${formatDate(session.startedAt)} | ${session.displayRegion}'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _ChipText(
                                text: formatDuration(session.duration),
                              ),
                              _ChipText(
                                text: formatDistanceMeters(
                                    session.totalDistanceMeters),
                              ),
                              _ChipText(
                                text:
                                    '최고 ${formatAltitudeMeters(session.maxAltitudeMeters)}',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        AppRoutes.flightRecordDetail,
                        arguments:
                            FlightRecordDetailArgs(sessionId: session.id),
                      );
                    },
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

class _StatCard extends StatelessWidget {
  const _StatCard({
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

class _ChipText extends StatelessWidget {
  const _ChipText({required this.text});

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
