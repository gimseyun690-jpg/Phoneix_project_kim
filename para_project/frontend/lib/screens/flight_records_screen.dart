import 'package:flutter/material.dart';

import '../app.dart';
import '../core/community_manager.dart';
import '../core/flight_live_metrics.dart';
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
    required this.communityManager,
  });

  final AppRepository repository;
  final AppUser user;
  final FlightRecordManager flightRecordManager;
  final CommunityManager communityManager;

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
      await widget.communityManager.initialize(user: widget.user);
      await widget.flightRecordManager.initialize(userId: widget.user.id);
      final sites =
          await widget.repository.getSites(pilotLevel: widget.user.pilotLevel);
      if (!mounted) {
        return;
      }
      setState(() {
        _sites = sites;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
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
      Navigator.pushNamed(context, AppRoutes.liveFlight);
      return;
    }

    if (widget.flightRecordManager.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.flightRecordManager.errorMessage!)),
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
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: '메모',
            hintText: '오늘 비행에서 공유할 포인트를 간단히 적어 주세요.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('분석 보기'),
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

    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.flightRecordManager.errorMessage ?? '비행 기록 저장에 실패했습니다.',
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('비행 기록을 저장했습니다.')),
    );
    await _openPostFlightActions(session.id);
  }

  Future<void> _openPostFlightActions(String sessionId) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '비행을 마쳤습니다.',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                '바로 비행 분석을 보거나, 오늘 비행을 비행일지로 작성해 이륙장 커뮤니티에 공유할 수 있습니다.',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Navigator.pushNamed(
                      context,
                      AppRoutes.flightJournalComposer,
                      arguments:
                          FlightJournalComposerArgs(sessionId: sessionId),
                    );
                  },
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('비행일지 작성'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Navigator.pushNamed(
                      context,
                      AppRoutes.flightRecordDetail,
                      arguments: FlightRecordDetailArgs(sessionId: sessionId),
                    );
                  },
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('비행 분석 보기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
          child: const Text('비행 기록 다시 불러오기'),
        ),
      );
    }

    return AnimatedBuilder(
      animation: widget.flightRecordManager,
      builder: (context, _) {
        final manager = widget.flightRecordManager;
        final activeSession = manager.activeSession;
        final points = manager.activePoints;
        final metrics = activeSession == null
            ? null
            : FlightLiveMetrics.fromSession(
                session: activeSession,
                points: points,
              );

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
                              activeSession == null ? '비행 기록 센터' : '진행 중인 비행',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (activeSession != null)
                            const _StatusPill(
                              text: '실시간 기록 중',
                              color: Color(0xFFE76F51),
                              backgroundColor: Color(0xFFFCE9E4),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (activeSession == null) ...[
                        Text(
                          '이륙 전부터 착륙 후 저장까지 한 흐름으로 기록합니다. 네트워크가 끊겨도 기록은 먼저 기기에 저장되고, 실시간 화면과 기록 상세에서 이어서 확인할 수 있습니다.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<int?>(
                          initialValue: _selectedSiteId,
                          decoration: const InputDecoration(
                            labelText: '기준 비행장',
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('비행장 미지정'),
                            ),
                            ..._sites.map(
                              (site) => DropdownMenuItem<int?>(
                                value: site.id,
                                child: Text('${site.region} · ${site.name}'),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedSiteId = value;
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed:
                                manager.isWorking ? null : _startRecording,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(
                              manager.isWorking ? '준비 중...' : '비행 기록 시작',
                            ),
                          ),
                        ),
                      ] else ...[
                        Text(
                          '${activeSession.displayRegion} / ${activeSession.displaySiteName}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _StatCard(
                              label: '경과 시간',
                              value: formatDuration(metrics!.elapsed),
                            ),
                            _StatCard(
                              label: '현재 고도',
                              value: formatAltitudeMeters(
                                  metrics.currentAltitudeMeters),
                            ),
                            _StatCard(
                              label: '이동 거리',
                              value: formatDistanceMeters(
                                  metrics.totalDistanceMeters),
                            ),
                            _StatCard(
                              label: '현재 속도',
                              value: formatSpeedKmh(metrics.currentSpeedMps),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isCompact = constraints.maxWidth < 460;

                            if (isCompact) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: () {
                                      Navigator.pushNamed(
                                        context,
                                        AppRoutes.liveFlight,
                                      );
                                    },
                                    icon: const Icon(Icons.map_outlined),
                                    label: const Text('비행 모드 열기'),
                                  ),
                                  const SizedBox(height: 10),
                                  FilledButton.icon(
                                    onPressed: manager.isWorking
                                        ? null
                                        : _stopRecording,
                                    icon:
                                        const Icon(Icons.stop_circle_outlined),
                                    label: Text(
                                      manager.isWorking
                                          ? '저장 중...'
                                          : '종료하고 분석 보기',
                                    ),
                                  ),
                                ],
                              );
                            }

                            return Row(
                              children: [
                                Expanded(
                                  child: FilledButton.tonalIcon(
                                    onPressed: () {
                                      Navigator.pushNamed(
                                        context,
                                        AppRoutes.liveFlight,
                                      );
                                    },
                                    icon: const Icon(Icons.map_outlined),
                                    label: const Text('비행 모드 열기'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: manager.isWorking
                                        ? null
                                        : _stopRecording,
                                    icon:
                                        const Icon(Icons.stop_circle_outlined),
                                    label: Text(
                                      manager.isWorking
                                          ? '저장 중...'
                                          : '종료하고 분석 보기',
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F7F8),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          activeSession == null
                              ? '기록을 시작하면 위치 추적과 저장이 바로 이어집니다. 화면을 벗어나도 기록을 최대한 유지하도록 배경 추적을 강화했습니다.'
                              : '실시간 지도 화면에서 현재 경로, 현재 온도, 한국형 참고 구역 상태를 바로 확인할 수 있습니다.',
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
                      if (manager.trackingNotice != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: switch (manager.trackingNotice!.tone) {
                              FlightTrackingNoticeTone.info =>
                                const Color(0xFFE8F0F8),
                              FlightTrackingNoticeTone.caution =>
                                const Color(0xFFFFF4DE),
                              FlightTrackingNoticeTone.warning =>
                                const Color(0xFFFDE9E4),
                            },
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                manager.trackingNotice!.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                manager.trackingNotice!.description,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
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
                            '${formatDate(session.startedAt)} · ${session.displayRegion}',
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _ChipText(text: formatDuration(session.duration)),
                              _ChipText(
                                text: formatDistanceMeters(
                                  session.totalDistanceMeters,
                                ),
                              ),
                              _ChipText(
                                text:
                                    '최고 ${formatAltitudeMeters(session.maxAltitudeMeters)}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    final existingPost = widget.communityManager
                                        .findPostBySessionId(session.id);
                                    Navigator.pushNamed(
                                      context,
                                      existingPost == null
                                          ? AppRoutes.flightJournalComposer
                                          : AppRoutes.communityPostDetail,
                                      arguments: existingPost == null
                                          ? FlightJournalComposerArgs(
                                              sessionId: session.id,
                                            )
                                          : CommunityPostDetailArgs(
                                              postId: existingPost.id,
                                            ),
                                    );
                                  },
                                  icon: Icon(
                                    widget.communityManager.findPostBySessionId(
                                                session.id) ==
                                            null
                                        ? Icons.edit_note_rounded
                                        : Icons.forum_outlined,
                                  ),
                                  label: Text(
                                    widget.communityManager.findPostBySessionId(
                                                session.id) ==
                                            null
                                        ? '비행일지 작성'
                                        : '작성한 글 보기',
                                  ),
                                ),
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.text,
    required this.color,
    required this.backgroundColor,
  });

  final String text;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
