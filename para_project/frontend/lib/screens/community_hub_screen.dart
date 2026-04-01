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
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: FilledButton(
          onPressed: _load,
          child: const Text('커뮤니티 다시 불러오기'),
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
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F6F8),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
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
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
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
                              Text(
                                '비행 후 바로 커뮤니티로 이어지게 만들었습니다.',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '비행 기록에서 만든 비행일지가 이륙장 커뮤니티 글이 됩니다. 후기, 질문, 사진, 피드백이 같은 흐름 안에서 이어집니다.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color:
                                          Colors.white.withValues(alpha: 0.9),
                                      height: 1.5,
                                    ),
                              ),
                              const SizedBox(height: 14),
                              FilledButton.tonalIcon(
                                onPressed: _openRecentJournal,
                                icon: Icon(
                                  latestExistingPost == null
                                      ? Icons.edit_note_rounded
                                      : Icons.forum_outlined,
                                ),
                                label: Text(
                                  latestExistingPost == null
                                      ? '최근 비행으로 비행일지 작성'
                                      : '최근 비행 글 보기',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '이륙장 커뮤니티',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 44,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _sites.length + 1,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                return ChoiceChip(
                                  label: const Text('전체'),
                                  selected: _selectedSiteId == null,
                                  onSelected: (_) {
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
                              return ChoiceChip(
                                label: Text('${site.name} $count'),
                                selected: _selectedSiteId == site.id,
                                onSelected: (_) {
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
                            ChoiceChip(
                              label: const Text('최신순'),
                              selected:
                                  _sortOrder == _CommunitySortOrder.latest,
                              onSelected: (_) {
                                setState(() {
                                  _sortOrder = _CommunitySortOrder.latest;
                                });
                              },
                            ),
                            ChoiceChip(
                              label: const Text('인기순'),
                              selected:
                                  _sortOrder == _CommunitySortOrder.popular,
                              onSelected: (_) {
                                setState(() {
                                  _sortOrder = _CommunitySortOrder.popular;
                                });
                              },
                            ),
                            FilterChip(
                              label: const Text('사진 많은 글'),
                              selected: _photosOnly,
                              onSelected: (value) {
                                setState(() {
                                  _photosOnly = value;
                                });
                              },
                            ),
                            FilterChip(
                              label: const Text('질문 포함 글'),
                              selected: _questionsOnly,
                              onSelected: (value) {
                                setState(() {
                                  _questionsOnly = value;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (refreshedPosts.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedSiteId == null
                                        ? '아직 올라온 비행일지가 없습니다.'
                                        : '이 이륙장에는 아직 올라온 비행일지가 없습니다.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    '비행을 마친 뒤 비행일지를 작성하면 이곳 피드에 바로 나타납니다.',
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.tonalIcon(
                                    onPressed: _openRecentJournal,
                                    icon:
                                        const Icon(Icons.add_comment_outlined),
                                    label: const Text('비행일지 작성하기'),
                                  ),
                                ],
                              ),
                            ),
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
