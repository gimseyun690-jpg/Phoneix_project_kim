import 'package:flutter/material.dart';

import '../core/utils.dart';
import '../models/app_models.dart';
import '../repositories/app_repository.dart';

class TrainingLogsScreen extends StatefulWidget {
  const TrainingLogsScreen({
    super.key,
    required this.repository,
    required this.user,
  });

  final AppRepository repository;
  final AppUser user;

  @override
  State<TrainingLogsScreen> createState() => _TrainingLogsScreenState();
}

class _TrainingLogsScreenState extends State<TrainingLogsScreen> {
  final _trainingTypeController = TextEditingController(text: '이륙 반복 훈련');
  final _memoController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<SiteSummary> _sites = [];
  List<TrainingLog> _logs = [];

  DateTime _selectedDate = DateTime.now();
  int? _selectedSiteId;
  String _difficulty = 'easy';
  bool _participated = true;
  bool _flightSuccess = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _trainingTypeController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sites =
          await widget.repository.getSites(pilotLevel: widget.user.pilotLevel);
      final logs =
          await widget.repository.getTrainingLogs(userId: widget.user.id);
      setState(() {
        _sites = sites;
        _logs = logs;
        _selectedSiteId ??= sites.isNotEmpty ? sites.first.id : null;
      });
    } catch (_) {
      setState(() {
        _error = '훈련 기록을 불러오지 못했습니다.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedSiteId == null ||
        _trainingTypeController.text.trim().isEmpty) {
      setState(() {
        _error = '사이트와 훈련 유형을 입력해 주세요.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.repository.createTrainingLog(
        TrainingLogDraft(
          userId: widget.user.id,
          siteId: _selectedSiteId!,
          trainingDate: _selectedDate,
          trainingType: _trainingTypeController.text.trim(),
          participated: _participated,
          flightSuccess: _flightSuccess,
          difficulty: _difficulty,
          memo: _memoController.text.trim(),
        ),
      );

      _memoController.clear();
      _flightSuccess = false;
      await _load();
    } catch (_) {
      setState(() {
        _error = '훈련 기록 저장에 실패했습니다.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _logs.isEmpty && _sites.isEmpty) {
      return Center(
        child: FilledButton(onPressed: _load, child: const Text('다시 불러오기')),
      );
    }

    final isCompactLayout = MediaQuery.sizeOf(context).width < 560;

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
                  Text(
                    '훈련 기록 작성',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (isCompactLayout) ...[
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(formatDate(_selectedDate)),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      key: ValueKey(_selectedSiteId),
                      initialValue: _selectedSiteId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '사이트'),
                      items: _sites
                          .map(
                            (site) => DropdownMenuItem<int>(
                              value: site.id,
                              child: Text(
                                site.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedSiteId = value;
                        });
                      },
                    ),
                  ] else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickDate,
                            icon: const Icon(Icons.calendar_today_outlined),
                            label: Text(formatDate(_selectedDate)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: ValueKey(_selectedSiteId),
                            initialValue: _selectedSiteId,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: '사이트'),
                            items: _sites
                                .map(
                                  (site) => DropdownMenuItem<int>(
                                    value: site.id,
                                    child: Text(
                                      site.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedSiteId = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _trainingTypeController,
                    decoration: const InputDecoration(labelText: '훈련 유형'),
                  ),
                  const SizedBox(height: 12),
                  if (isCompactLayout) ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey(_difficulty),
                      initialValue: _difficulty,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '난이도'),
                      items: const [
                        DropdownMenuItem(value: 'easy', child: Text('쉬움')),
                        DropdownMenuItem(value: 'medium', child: Text('보통')),
                        DropdownMenuItem(value: 'hard', child: Text('어려움')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _difficulty = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _memoController,
                      decoration: const InputDecoration(labelText: '메모'),
                    ),
                  ] else
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(_difficulty),
                            initialValue: _difficulty,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: '난이도'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'easy', child: Text('쉬움')),
                              DropdownMenuItem(
                                  value: 'medium', child: Text('보통')),
                              DropdownMenuItem(
                                  value: 'hard', child: Text('어려움')),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _difficulty = value;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _memoController,
                            decoration: const InputDecoration(labelText: '메모'),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('훈련 참여'),
                    value: _participated,
                    onChanged: (value) {
                      setState(() {
                        _participated = value;
                      });
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('비행 성공'),
                    value: _flightSuccess,
                    onChanged: (value) {
                      setState(() {
                        _flightSuccess = value;
                      });
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: Text(_submitting ? '저장 중...' : '기록 저장'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '작성한 훈련 기록',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          if (_logs.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('등록된 훈련 기록이 없습니다.'),
              ),
            ),
          ..._logs.map(
            (log) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isCompactLayout) ...[
                      Text(
                        '${log.siteName} | ${log.trainingType}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(formatDate(log.trainingDate)),
                    ] else
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${log.siteName} | ${log.trainingType}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(formatDate(log.trainingDate)),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Tag(text: log.difficulty.trainingDifficultyLabel),
                        _Tag(text: log.participated ? '참여' : '불참'),
                        _Tag(text: log.flightSuccess ? '성공' : '미성공'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(log.memo.isEmpty ? '메모 없음' : log.memo),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

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
