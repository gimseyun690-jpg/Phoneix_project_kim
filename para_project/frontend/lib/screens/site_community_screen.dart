import 'package:flutter/material.dart';

import '../app.dart';
import '../core/community_manager.dart';
import '../core/flight_record_manager.dart';
import '../models/app_models.dart';
import '../repositories/app_repository.dart';
import '../widgets/community_post_card.dart';

class SiteCommunityScreen extends StatefulWidget {
  const SiteCommunityScreen({
    super.key,
    required this.repository,
    required this.user,
    required this.communityManager,
    required this.flightRecordManager,
    this.siteId,
    required this.siteName,
  });

  final AppRepository repository;
  final AppUser user;
  final CommunityManager communityManager;
  final FlightRecordManager flightRecordManager;
  final int? siteId;
  final String siteName;

  @override
  State<SiteCommunityScreen> createState() => _SiteCommunityScreenState();
}

class _SiteCommunityScreenState extends State<SiteCommunityScreen> {
  bool _loading = true;
  String? _errorMessage;
  SiteSummary? _site;

  @override
  void initState() {
    super.initState();
    _load();
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
      SiteSummary? matched;
      if (widget.siteId != null) {
        for (final site in sites) {
          if (site.id == widget.siteId) {
            matched = site;
            break;
          }
        }
      } else {
        for (final site in sites) {
          if (site.name == widget.siteName) {
            matched = site;
            break;
          }
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _site = matched;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = '이륙장 커뮤니티를 불러오지 못했습니다.';
      });
    }
  }

  FlightSession? _latestMatchingSession() {
    for (final session in widget.flightRecordManager.sessions) {
      if (session.status != FlightSessionStatus.completed) {
        continue;
      }
      if (widget.siteId != null && session.siteId == widget.siteId) {
        return session;
      }
      if (session.siteName == widget.siteName) {
        return session;
      }
    }
    return null;
  }

  void _openWrite() {
    final session = _latestMatchingSession();
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이 이륙장과 연결된 비행 기록이 있을 때 비행일지를 바로 작성할 수 있습니다.'),
        ),
      );
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
      return Scaffold(
        appBar: AppBar(title: Text('${widget.siteName} 커뮤니티')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: _SiteCommunityStateCard(
              title: '이륙장 피드를 불러오는 중입니다.',
              description: '최근 비행일지와 피드백을 정리하고 있습니다.',
              child: Padding(
                padding: EdgeInsets.only(top: 4),
                child: CircularProgressIndicator(),
              ),
            ),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: Text('${widget.siteName} 커뮤니티')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _SiteCommunityStateCard(
              title: '이륙장 커뮤니티를 불러오지 못했습니다.',
              description: _errorMessage!,
              child: FilledButton(
                onPressed: _load,
                child: const Text('다시 불러오기'),
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: widget.communityManager,
      builder: (context, _) {
        final posts = widget.communityManager.siteFeedPosts(
          siteId: widget.siteId,
          siteName: widget.siteName,
        );

        return Scaffold(
          appBar: AppBar(
            title: Text('${widget.siteName} 커뮤니티'),
          ),
          body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _SiteCommunityHeroCard(
                  siteName: widget.siteName,
                  siteSummary: _site == null
                      ? null
                      : '${_site!.region} · ${_site!.assessment.summaryText}',
                  postCount: posts.length,
                  onWrite: _openWrite,
                  onOpenSiteDetail: _site == null
                      ? null
                      : () {
                          Navigator.pushNamed(
                            context,
                            AppRoutes.siteDetail,
                            arguments: SiteDetailArgs(
                              siteId: _site!.id,
                              pilotLevel: widget.user.pilotLevel,
                            ),
                          );
                        },
                ),
                const SizedBox(height: 18),
                if (posts.isEmpty)
                  _SiteCommunityEmptyCard(
                    onPressed: _openWrite,
                  ),
                ...posts.map(
                  (post) => CommunityPostCard(
                    post: post,
                    isLiked: widget.communityManager.currentUser != null &&
                        post.isLikedBy(widget.communityManager.currentUser!.id),
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        AppRoutes.communityPostDetail,
                        arguments: CommunityPostDetailArgs(postId: post.id),
                      );
                    },
                    onLike: () => widget.communityManager.toggleLike(post.id),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SiteCommunityHeroCard extends StatelessWidget {
  const _SiteCommunityHeroCard({
    required this.siteName,
    required this.siteSummary,
    required this.postCount,
    required this.onWrite,
    required this.onOpenSiteDetail,
  });

  final String siteName;
  final String? siteSummary;
  final int postCount;
  final VoidCallback onWrite;
  final VoidCallback? onOpenSiteDetail;

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
              '이륙장 커뮤니티',
              style: theme.textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            siteName,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (siteSummary != null) ...[
            const SizedBox(height: 4),
            Text(
              siteSummary!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            postCount == 0
                ? '첫 비행일지가 올라오면 이륙장 커뮤니티가 시작됩니다.'
                : '최근 비행일지 $postCount개가 이 이륙장 커뮤니티에 올라와 있습니다.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 360 || onOpenSiteDetail == null;
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: onWrite,
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text('비행일지 작성'),
                    ),
                    if (onOpenSiteDetail != null) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: onOpenSiteDetail,
                        icon: const Icon(Icons.landscape_outlined),
                        label: const Text('사이트 상세'),
                      ),
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: onWrite,
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text('비행일지 작성'),
                    ),
                  ),
                  if (onOpenSiteDetail != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onOpenSiteDetail,
                        icon: const Icon(Icons.landscape_outlined),
                        label: const Text('사이트 상세'),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SiteCommunityEmptyCard extends StatelessWidget {
  const _SiteCommunityEmptyCard({required this.onPressed});

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
              '아직 이륙장 피드에 올라온 글이 없습니다.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '첫 비행일지를 남기면 이 이륙장의 기록과 피드백이 이곳부터 쌓입니다.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('비행일지 남기기'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SiteCommunityStateCard extends StatelessWidget {
  const _SiteCommunityStateCard({
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
