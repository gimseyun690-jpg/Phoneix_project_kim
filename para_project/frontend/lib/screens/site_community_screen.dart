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
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: Text('${widget.siteName} 커뮤니티')),
        body: Center(
          child: FilledButton(
            onPressed: _load,
            child: const Text('다시 불러오기'),
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
                        widget.siteName,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      if (_site != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${_site!.region} · ${_site!.assessment.summaryText}',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.92),
                                  ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        posts.isEmpty
                            ? '첫 비행일지가 올라오면 이륙장 커뮤니티가 시작됩니다.'
                            : '최근 비행일지 ${posts.length}개가 이 이륙장 커뮤니티에 올라와 있습니다.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white,
                              height: 1.5,
                            ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: _openWrite,
                              icon: const Icon(Icons.edit_note_rounded),
                              label: const Text('비행일지 작성'),
                            ),
                          ),
                          if (_site != null) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pushNamed(
                                    context,
                                    AppRoutes.siteDetail,
                                    arguments: SiteDetailArgs(
                                      siteId: _site!.id,
                                      pilotLevel: widget.user.pilotLevel,
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.landscape_outlined),
                                label: const Text('사이트 상세'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (posts.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('아직 이륙장 피드에 올라온 글이 없습니다. 첫 비행일지를 남겨보세요.'),
                    ),
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
