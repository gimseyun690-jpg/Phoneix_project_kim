import 'package:flutter/material.dart';

import '../app.dart';
import '../core/community_manager.dart';
import '../core/flight_record_manager.dart';
import '../models/app_models.dart';
import '../repositories/app_repository.dart';
import '../widgets/community_post_card.dart';
import 'notices_screen.dart';

enum _CommunitySortOrder { latest, popular }

class CommunityHubScreen extends StatefulWidget {
  const CommunityHubScreen({
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
  State<CommunityHubScreen> createState() => _CommunityHubScreenState();
}

class _CommunityHubScreenState extends State<CommunityHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;
  String? _errorMessage;
  List<SiteSummary> _sites = [];
  int? _selectedSiteId;
  _CommunitySortOrder _sortOrder = _CommunitySortOrder.latest;
  bool _photosOnly = false;
  bool _questionsOnly = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
      final sites =
          await widget.repository.getSites(pilotLevel: widget.user.pilotLevel);
      if (!mounted) {
        return;
      }
      setState(() {
        _sites = sites;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = '커뮤니티 화면을 준비하지 못했습니다.';
      });
    }
  }

  FlightSession? _latestCompletedSession() {
    for (final session in widget.flightRecordManager.sessions) {
      if (session.status == FlightSessionStatus.completed) {
        return session;
      }
    }
    return null;
  }

  List<FlightJournalPost> _filteredPosts() {
    final base = widget.communityManager.siteFeedPosts(siteId: _selectedSiteId);
    final filtered = base.where((post) {
      if (_photosOnly && post.imageCount == 0) {
        return false;
      }
      if (_questionsOnly && !post.hasQuestion) {
        return false;
      }
      return true;
    }).toList(growable: false);

    if (_sortOrder == _CommunitySortOrder.latest) {
      filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return filtered;
    }

    filtered.sort((a, b) {
      final popularityA = a.likeCount * 2 + a.commentCount;
      final popularityB = b.likeCount * 2 + b.commentCount;
      if (popularityA == popularityB) {
        return b.createdAt.compareTo(a.createdAt);
      }
      return popularityB.compareTo(popularityA);
    });
    return filtered;
  }

  void _openPost(String postId) {
    Navigator.pushNamed(
      context,
      AppRoutes.communityPostDetail,
      arguments: CommunityPostDetailArgs(postId: postId),
    );
  }

  void _openRecentJournal() {
    final session = _latestCompletedSession();
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('먼저 비행을 기록한 뒤 비행일지를 작성할 수 있습니다.'),
        ),
      );
      return;
    }

    final existingPost =
        widget.communityManager.findPostBySessionId(session.id);
    if (existingPost != null) {
      _openPost(existingPost.id);
      return;
    }

    Navigator.pushNamed(
      context,
      AppRoutes.flightJournalComposer,
      arguments: FlightJournalComposerArgs(sessionId: session.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: _CommunityStateCard(
            title: '커뮤니티를 불러오는 중입니다.',
            description: '이륙장 피드와 최근 비행일지를 정리하고 있습니다.',
            child: Padding(
              padding: EdgeInsets.only(top: 4),
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _CommunityStateCard(
            title: '커뮤니티를 준비하지 못했습니다.',
            description: _errorMessage!,
            child: FilledButton(
              onPressed: _load,
              child: const Text('커뮤니티 다시 불러오기'),
            ),
          ),
        ),
      );
    }

    final latestSession = _latestCompletedSession();
    final latestExistingPost = latestSession == null
        ? null
        : widget.communityManager.findPostBySessionId(latestSession.id);

    return AnimatedBuilder(
      animation: widget.communityManager,
      builder: (context, _) {
        final refreshedPosts = _filteredPosts();
        final totalPosts = widget.communityManager.siteFeedPosts().length;
        SiteSummary? selectedSite;
        if (_selectedSiteId != null) {
          for (final site in _sites) {
            if (site.id == _selectedSiteId) {
              selectedSite = site;
              break;
            }
          }
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F6F8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TabBar(
                  controller: _tabController,
                  dividerColor: Colors.transparent,
                  labelStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                  unselectedLabelStyle:
                      Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  tabs: const [
                    Tab(text: '사이트 피드'),
                    Tab(text: '공지'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        _CommunityHeroCard(
                          hasExistingPost: latestExistingPost != null,
                          totalPosts: totalPosts,
                          onPressed: _openRecentJournal,
                        ),
                        const SizedBox(height: 18),
                        _CommunitySectionHeader(
                          title: selectedSite?.name ?? '이륙장 커뮤니티',
                          subtitle: selectedSite == null
                              ? '보고 싶은 이륙장과 글 조건을 가볍게 골라보세요.'
                              : '${selectedSite.region}의 최근 비행일지와 질문을 모아봅니다.',
                          trailingText: refreshedPosts.isEmpty
                              ? null
                              : '${refreshedPosts.length}개',
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 42,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _sites.length + 1,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                return _CommunityScopeChip(
                                  label: '전체',
                                  count: totalPosts,
                                  selected: _selectedSiteId == null,
                                  onTap: () {
                                    setState(() {
                                      _selectedSiteId = null;
                                    });
                                  },
                                );
                              }
                              final site = _sites[index - 1];
                              final count = widget.communityManager
                                  .siteFeedPosts(siteId: site.id)
                                  .length;
                              return _CommunityScopeChip(
                                label: site.name,
                                count: count,
                                selected: _selectedSiteId == site.id,
                                onTap: () {
                                  setState(() {
                                    _selectedSiteId = site.id;
                                  });
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _CommunityToggleChip(
                              label: '최신순',
                              selected:
                                  _sortOrder == _CommunitySortOrder.latest,
                              onTap: () {
                                setState(() {
                                  _sortOrder = _CommunitySortOrder.latest;
                                });
                              },
                            ),
                            _CommunityToggleChip(
                              label: '인기순',
                              selected:
                                  _sortOrder == _CommunitySortOrder.popular,
                              onTap: () {
                                setState(() {
                                  _sortOrder = _CommunitySortOrder.popular;
                                });
                              },
                            ),
                            _CommunityToggleChip(
                              label: '사진 많은 글',
                              selected: _photosOnly,
                              onTap: () {
                                setState(() {
                                  _photosOnly = !_photosOnly;
                                });
                              },
                            ),
                            _CommunityToggleChip(
                              label: '질문 포함 글',
                              selected: _questionsOnly,
                              onTap: () {
                                setState(() {
                                  _questionsOnly = !_questionsOnly;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (refreshedPosts.isEmpty)
                          _CommunityEmptyStateCard(
                            title: _selectedSiteId == null
                                ? '아직 올라온 비행일지가 없습니다.'
                                : '이 이륙장에는 아직 올라온 비행일지가 없습니다.',
                            description: '비행을 마친 뒤 비행일지를 작성하면 이곳 피드에 바로 나타납니다.',
                            onPressed: _openRecentJournal,
                          ),
                        ...refreshedPosts.map(
                          (post) => CommunityPostCard(
                            post: post,
                            isLiked:
                                widget.communityManager.currentUser != null &&
                                    post.isLikedBy(
                                      widget.communityManager.currentUser!.id,
                                    ),
                            onTap: () => _openPost(post.id),
                            onLike: () =>
                                widget.communityManager.toggleLike(post.id),
                          ),
                        ),
                      ],
                    ),
                  ),
                  NoticesScreen(repository: widget.repository),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CommunityHeroCard extends StatelessWidget {
  const _CommunityHeroCard({
    required this.hasExistingPost,
    required this.totalPosts,
    required this.onPressed,
  });

  final bool hasExistingPost;
  final int totalPosts;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '비행 기록에서 바로 이어짐',
              style: theme.textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '비행일지와 현장 피드백을 한 흐름으로 모았습니다.',
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            totalPosts == 0
                ? '첫 비행일지가 올라오면 이륙장 커뮤니티가 시작됩니다.'
                : '현재 $totalPosts개의 비행일지와 질문이 이륙장 피드에 정리되어 있습니다.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                icon: Icon(
                  hasExistingPost
                      ? Icons.forum_outlined
                      : Icons.edit_note_rounded,
                ),
                label: Text(
                  hasExistingPost ? '최근 비행 글 보기' : '최근 비행일지 작성',
                ),
              ),
              Text(
                '후기, 질문, 사진, 피드백을 같은 리듬으로 볼 수 있습니다.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.84),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommunitySectionHeader extends StatelessWidget {
  const _CommunitySectionHeader({
    required this.title,
    required this.subtitle,
    this.trailingText,
  });

  final String title;
  final String subtitle;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        if (trailingText != null) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F1F4),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              trailingText!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: const Color(0xFF173845),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CommunityScopeChip extends StatelessWidget {
  const _CommunityScopeChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final baseColor =
        selected ? const Color(0xFF1F6E82) : const Color(0xFFF4F7F9);
    final textColor = selected ? Colors.white : const Color(0xFF334155);
    return Material(
      color: baseColor,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.18)
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color:
                            selected ? Colors.white : const Color(0xFF475569),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommunityToggleChip extends StatelessWidget {
  const _CommunityToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      side: BorderSide(
        color: selected
            ? const Color(0xFF1F6E82).withValues(alpha: 0.24)
            : const Color(0xFFE2E8F0),
      ),
      selectedColor: const Color(0xFFE0EFF4),
      backgroundColor: const Color(0xFFF7F9FB),
      labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: selected ? const Color(0xFF1F5E6E) : const Color(0xFF4B5563),
            fontWeight: FontWeight.w700,
          ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _CommunityEmptyStateCard extends StatelessWidget {
  const _CommunityEmptyStateCard({
    required this.title,
    required this.description,
    required this.onPressed,
  });

  final String title;
  final String description;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('비행일지 작성하기'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityStateCard extends StatelessWidget {
  const _CommunityStateCard({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}
