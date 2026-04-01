import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app.dart';
import '../core/community_manager.dart';
import '../core/flight_analysis_summary.dart';
import '../core/flight_record_manager.dart';
import '../core/utils.dart';
import '../models/app_models.dart';
import '../repositories/app_repository.dart';

class FlightJournalComposerScreen extends StatefulWidget {
  const FlightJournalComposerScreen({
    super.key,
    required this.repository,
    required this.user,
    required this.flightRecordManager,
    required this.communityManager,
    required this.sessionId,
  });

  final AppRepository repository;
  final AppUser user;
  final FlightRecordManager flightRecordManager;
  final CommunityManager communityManager;
  final String sessionId;

  @override
  State<FlightJournalComposerScreen> createState() =>
      _FlightJournalComposerScreenState();
}

class _FlightJournalComposerScreenState
    extends State<FlightJournalComposerScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final TextEditingController _questionController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;
  FlightSessionDetail? _sessionDetail;
  FlightAnalysisSummary? _analysisSummary;
  FlightJournalPost? _existingPost;
  List<SiteSummary> _sites = [];
  List<FlightJournalMedia> _media = [];
  int? _selectedSiteId;
  bool _shareToCommunity = true;
  CommunityVisibility _visibility = CommunityVisibility.siteOnly;
  String _summaryText = '';
  String _weatherSummary = '';
  String _flyabilitySummary = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      await widget.communityManager.initialize(user: widget.user);
      await widget.flightRecordManager.initialize(userId: widget.user.id);
      final detail =
          await widget.flightRecordManager.getSessionDetail(widget.sessionId);
      if (detail == null) {
        throw Exception('연결된 비행 기록을 찾지 못했습니다.');
      }

      final sites =
          await widget.repository.getSites(pilotLevel: widget.user.pilotLevel);
      final analysis = FlightAnalysisSummary.fromDetail(detail);
      final existingPost =
          widget.communityManager.findPostBySessionId(widget.sessionId);

      final selectedSiteId = existingPost?.siteId ?? detail.session.siteId;
      final selectedSite = _siteById(sites, selectedSiteId);
      final title = existingPost?.title ??
          '${formatDate(detail.session.startedAt)} ${_resolvedSiteName(detail.session, selectedSite)} 비행일지';
      final summaryText = existingPost?.summaryText ??
          _buildSummaryText(detail.session, analysis);
      final weatherSummary =
          existingPost?.weatherSummary ?? selectedSite?.weather.summary ?? '';
      final flyabilitySummary = existingPost?.flyabilitySummary ??
          selectedSite?.assessment.summaryText ??
          '';
      final body = existingPost?.body ??
          _buildSuggestedBody(
            session: detail.session,
            analysis: analysis,
            site: selectedSite,
            weatherSummary: weatherSummary,
            flyabilitySummary: flyabilitySummary,
          );

      if (!mounted) {
        return;
      }

      _titleController.text = title;
      _bodyController.text = body;
      _questionController.text = existingPost?.questionText ?? '';
      setState(() {
        _sessionDetail = detail;
        _analysisSummary = analysis;
        _existingPost = existingPost;
        _sites = sites;
        _selectedSiteId = selectedSiteId;
        _shareToCommunity =
            (existingPost?.visibility ?? CommunityVisibility.siteOnly) !=
                CommunityVisibility.private;
        _visibility = existingPost?.visibility == CommunityVisibility.private
            ? CommunityVisibility.siteOnly
            : existingPost?.visibility ?? CommunityVisibility.siteOnly;
        _summaryText = summaryText;
        _weatherSummary = weatherSummary;
        _flyabilitySummary = flyabilitySummary;
        _media = existingPost?.media.toList(growable: true) ?? [];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  SiteSummary? _currentSelectedSite() => _siteById(_sites, _selectedSiteId);

  SiteSummary? _siteById(List<SiteSummary> sites, int? siteId) {
    if (siteId == null) {
      return null;
    }
    for (final site in sites) {
      if (site.id == siteId) {
        return site;
      }
    }
    return null;
  }

  String _resolvedSiteName(FlightSession session, SiteSummary? selectedSite) {
    final siteName = selectedSite?.name ?? session.siteName.trim();
    if (siteName.isNotEmpty) {
      return siteName;
    }
    return '현장';
  }

  String _buildSummaryText(
    FlightSession session,
    FlightAnalysisSummary analysis,
  ) {
    final segments = <String>[
      '${formatDate(session.startedAt)} 비행 기록',
      '총 비행 시간 ${formatDuration(session.duration)}',
      '총 이동 거리 ${formatDistanceMeters(session.totalDistanceMeters)}',
      '최고 고도 ${formatAltitudeMeters(session.maxAltitudeMeters)}',
      analysis.overview,
    ];
    return segments.join(' · ');
  }

  String _buildSuggestedBody({
    required FlightSession session,
    required FlightAnalysisSummary analysis,
    required SiteSummary? site,
    required String weatherSummary,
    required String flyabilitySummary,
  }) {
    final lines = <String>[
      '${_resolvedSiteName(session, site)}에서 ${formatDuration(session.duration)} 동안 비행했습니다.',
      '총 이동 거리는 ${formatDistanceMeters(session.totalDistanceMeters)}, 최고 고도는 ${formatAltitudeMeters(session.maxAltitudeMeters)}였습니다.',
      analysis.overview,
    ];
    if (weatherSummary.trim().isNotEmpty) {
      lines.add('현장 날씨는 $weatherSummary 였습니다.');
    }
    if (flyabilitySummary.trim().isNotEmpty) {
      lines.add('비행 참고 상태는 $flyabilitySummary');
    }
    if (session.memo.trim().isNotEmpty) {
      lines.add('현장 메모: ${session.memo.trim()}');
    }
    lines.add('오늘 비행에서 느낀 점을 자유롭게 남겨보세요.');
    return lines.join('\n\n');
  }

  Future<void> _pickPhotos() async {
    try {
      final currentImageCount = _media
          .where((item) => item.type == FlightJournalMediaType.image)
          .length;
      final remaining = 6 - currentImageCount;
      if (remaining <= 0) {
        _showMessage('사진은 최대 6장까지 첨부할 수 있습니다.');
        return;
      }

      final files = await _picker.pickMultiImage(
        imageQuality: 78,
        maxWidth: 1800,
      );
      if (files.isEmpty) {
        return;
      }

      final picked = files.take(remaining).map(_toImageMedia).toList();
      setState(() {
        _media = [..._media, ...picked];
      });
      if (files.length > remaining) {
        _showMessage('사진은 최대 6장까지만 첨부했습니다.');
      }
    } catch (_) {
      _showMessage('사진을 불러오지 못했습니다.');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final currentVideoCount = _media
          .where((item) => item.type == FlightJournalMediaType.video)
          .length;
      if (currentVideoCount >= 1) {
        _showMessage('동영상은 현재 1개까지만 첨부할 수 있습니다.');
        return;
      }

      final file = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 3),
      );
      if (file == null) {
        return;
      }

      setState(() {
        _media = [..._media, _toVideoMedia(file)];
      });
    } catch (_) {
      _showMessage('동영상을 불러오지 못했습니다.');
    }
  }

  FlightJournalMedia _toImageMedia(XFile file) {
    final now = DateTime.now();
    return FlightJournalMedia(
      id: 'media_${now.microsecondsSinceEpoch}',
      type: FlightJournalMediaType.image,
      localPath: file.path,
      fileName: file.name,
      createdAt: now,
    );
  }

  FlightJournalMedia _toVideoMedia(XFile file) {
    final now = DateTime.now();
    return FlightJournalMedia(
      id: 'media_${now.microsecondsSinceEpoch}',
      type: FlightJournalMediaType.video,
      localPath: file.path,
      fileName: file.name,
      createdAt: now,
    );
  }

  void _removeMedia(String mediaId) {
    setState(() {
      _media =
          _media.where((item) => item.id != mediaId).toList(growable: false);
    });
  }

  Future<void> _save() async {
    final detail = _sessionDetail;
    final analysis = _analysisSummary;
    if (detail == null || analysis == null) {
      return;
    }

    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty) {
      _showMessage('제목을 입력해 주세요.');
      return;
    }
    if (body.isEmpty) {
      _showMessage('비행 후기를 입력해 주세요.');
      return;
    }

    final selectedSite = _currentSelectedSite();
    final visibility =
        _shareToCommunity ? _visibility : CommunityVisibility.private;
    if (visibility != CommunityVisibility.private && selectedSite == null) {
      _showMessage('커뮤니티에 공유하려면 연결할 이륙장을 선택해 주세요.');
      return;
    }

    setState(() {
      _saving = true;
    });

    final post = await widget.communityManager.saveJournal(
      FlightJournalDraft(
        postId: _existingPost?.id,
        userId: widget.user.id,
        authorName: widget.user.fullName,
        flightSessionId: detail.session.id,
        siteId: selectedSite?.id,
        siteName: selectedSite?.name ?? detail.session.displaySiteName,
        siteRegion: selectedSite?.region ?? detail.session.displayRegion,
        title: title,
        body: body,
        questionText: _questionController.text.trim(),
        visibility: visibility,
        flightDate: detail.session.startedAt,
        flightStartedAt: detail.session.startedAt,
        flightEndedAt: detail.session.endedAt,
        durationSeconds: detail.session.durationSeconds,
        totalDistanceMeters: detail.session.totalDistanceMeters,
        maxAltitudeMeters: detail.session.maxAltitudeMeters,
        weatherSummary: selectedSite?.weather.summary ?? _weatherSummary,
        flyabilitySummary:
            selectedSite?.assessment.summaryText ?? _flyabilitySummary,
        summaryText: _summaryText,
        media: _media,
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _saving = false;
    });

    if (post == null) {
      _showMessage(
        widget.communityManager.errorMessage ?? '비행일지를 저장하지 못했습니다.',
      );
      return;
    }

    Navigator.pushReplacementNamed(
      context,
      AppRoutes.communityPostDetail,
      arguments: CommunityPostDetailArgs(postId: post.id),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('비행일지 작성')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null ||
        _sessionDetail == null ||
        _analysisSummary == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('비행일지 작성')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_errorMessage ?? '비행일지를 준비하지 못했습니다.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _load,
                  child: const Text('다시 불러오기'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final detail = _sessionDetail!;
    final selectedSite = _currentSelectedSite();
    final weatherSummary = selectedSite?.weather.summary ?? _weatherSummary;
    final flyabilitySummary =
        selectedSite?.assessment.summaryText ?? _flyabilitySummary;
    final siteFeedCount = selectedSite == null
        ? 0
        : widget.communityManager.siteFeedCount(
            siteId: selectedSite.id,
            siteName: selectedSite.name,
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('비행일지 작성'),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.upload_rounded),
          label: Text(
            _saving
                ? '저장 중...'
                : _shareToCommunity
                    ? selectedSite == null
                        ? '커뮤니티에 게시하기'
                        : '${selectedSite.name} 피드에 게시하기'
                    : '나만 보기로 저장하기',
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          _JournalSummaryHero(
            session: detail.session,
            summaryText: _summaryText,
            weatherSummary: weatherSummary,
            flyabilitySummary: flyabilitySummary,
            existingPost: _existingPost != null,
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: '게시 준비 흐름',
            subtitle: '분석 내용에서 바로 이어서 작성할 수 있게 연결했습니다.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    const _InfoChip(text: '자동 요약 완료'),
                    _InfoChip(
                      text: _media.isEmpty
                          ? '사진 추가 가능'
                          : '미디어 ${_media.length}개 연결됨',
                    ),
                    _InfoChip(
                      text: selectedSite == null ? '이륙장 선택 필요' : '이륙장 연결됨',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  selectedSite == null
                      ? '이륙장을 선택하면 해당 이륙장 피드에 바로 연결할 수 있습니다. 비행 요약은 이미 채워져 있으니 사진과 후기만 더해도 게시할 수 있습니다.'
                      : '${selectedSite.name} 피드에 최근 비행일지 $siteFeedCount개가 올라와 있습니다. 사진을 추가해 현장 분위기와 함께 공유해 보세요.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.45,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: '자동 생성 요약',
            subtitle: '비행 기록에서 바로 가져온 핵심 정보입니다.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(text: formatDate(detail.session.startedAt)),
                    _InfoChip(
                      text: formatDuration(detail.session.duration),
                    ),
                    _InfoChip(
                      text: formatDistanceMeters(
                          detail.session.totalDistanceMeters),
                    ),
                    _InfoChip(
                      text:
                          '최고 ${formatAltitudeMeters(detail.session.maxAltitudeMeters)}',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(_summaryText,
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: '비행일지 내용',
            subtitle: '짧게 적어도 바로 게시할 수 있도록 구성했습니다.',
            child: Column(
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: '제목',
                    hintText: '오늘 비행 어땠나요?',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _bodyController,
                  minLines: 6,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: '느낀 점 / 후기',
                    hintText: '비행 중 기억에 남은 장면이나 배운 점을 남겨보세요.',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _questionController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '질문',
                    hintText: '다른 파일럿에게 묻고 싶은 점이 있다면 적어보세요.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: '이륙장 연결',
            subtitle: '커뮤니티에 공유할 때는 연결할 이륙장을 선택해 주세요.',
            child: DropdownButtonFormField<int?>(
              initialValue: _selectedSiteId,
              decoration: const InputDecoration(
                labelText: '이륙장 커뮤니티',
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('이륙장 선택 안 함'),
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
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: '사진 / 동영상',
            subtitle:
                '사진은 최대 6장, 동영상은 현재 1개까지 첨부할 수 있습니다. 게시 전에 현장 사진을 더하면 피드에서 더 읽기 쉬워집니다.',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickPhotos,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('사진 추가'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickVideo,
                        icon: const Icon(Icons.videocam_outlined),
                        label: const Text('동영상 추가'),
                      ),
                    ),
                  ],
                ),
                if (_media.isEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F7F8),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text('아직 첨부한 사진이나 동영상이 없습니다.'),
                  ),
                ] else ...[
                  const SizedBox(height: 14),
                  ..._media.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MediaAttachmentTile(
                        media: item,
                        onRemove: () => _removeMedia(item.id),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: '공유 설정',
            subtitle: '분석과 비행일지를 어떤 범위까지 보여줄지 선택할 수 있습니다.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _shareToCommunity,
                  onChanged: (value) {
                    setState(() {
                      _shareToCommunity = value;
                    });
                  },
                  title: const Text('이륙장 커뮤니티에 공유'),
                  subtitle: Text(
                    _shareToCommunity
                        ? selectedSite == null
                            ? '게시 전에 연결할 이륙장을 선택하면 해당 피드에 바로 올라갑니다.'
                            : '게시 후 ${selectedSite.name} 피드에서 다른 파일럿이 바로 볼 수 있습니다.'
                        : '지금은 나만 볼 수 있도록 저장합니다.',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final visibility in [
                      CommunityVisibility.public,
                      CommunityVisibility.siteOnly,
                    ])
                      ChoiceChip(
                        label: Text(visibility.label),
                        selected:
                            _shareToCommunity && _visibility == visibility,
                        onSelected: _shareToCommunity
                            ? (_) {
                                setState(() {
                                  _visibility = visibility;
                                });
                              }
                            : null,
                      ),
                    ChoiceChip(
                      label: const Text('나만 보기'),
                      selected: !_shareToCommunity,
                      onSelected: (_) {
                        setState(() {
                          _shareToCommunity = false;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JournalSummaryHero extends StatelessWidget {
  const _JournalSummaryHero({
    required this.session,
    required this.summaryText,
    required this.weatherSummary,
    required this.flyabilitySummary,
    required this.existingPost,
  });

  final FlightSession session;
  final String summaryText;
  final String weatherSummary;
  final String flyabilitySummary;
  final bool existingPost;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF173845),
            Color(0xFF2A6F80),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (existingPost)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                '이전에 작성한 비행일지 수정',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (existingPost) const SizedBox(height: 12),
          Text(
            session.displaySiteName,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            '${formatDate(session.startedAt)} · ${session.displayRegion}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                ),
          ),
          const SizedBox(height: 14),
          Text(
            summaryText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  height: 1.45,
                ),
          ),
          if (weatherSummary.trim().isNotEmpty ||
              flyabilitySummary.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (weatherSummary.trim().isNotEmpty)
                  _HeroTag(text: weatherSummary),
                if (flyabilitySummary.trim().isNotEmpty)
                  _HeroTag(text: flyabilitySummary),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _MediaAttachmentTile extends StatelessWidget {
  const _MediaAttachmentTile({
    required this.media,
    required this.onRemove,
  });

  final FlightJournalMedia media;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final color = media.type == FlightJournalMediaType.image
        ? const Color(0xFF2A9D8F)
        : const Color(0xFF8B5CF6);
    final icon = media.type == FlightJournalMediaType.image
        ? Icons.photo_camera_back_rounded
        : Icons.play_circle_outline_rounded;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  media.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  media.type.label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
            tooltip: '첨부 제거',
          ),
        ],
      ),
    );
  }
}
