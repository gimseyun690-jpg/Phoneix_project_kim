import 'package:flutter/material.dart';

import '../app.dart';
import '../core/community_manager.dart';
import '../core/flight_record_manager.dart';
import '../core/utils.dart';
import '../models/app_models.dart';
import '../widgets/community_post_card.dart';
import '../widgets/flight_map_view.dart';

class CommunityPostDetailScreen extends StatefulWidget {
  const CommunityPostDetailScreen({
    super.key,
    required this.communityManager,
    required this.flightRecordManager,
    required this.postId,
  });

  final CommunityManager communityManager;
  final FlightRecordManager flightRecordManager;
  final String postId;

  @override
  State<CommunityPostDetailScreen> createState() =>
      _CommunityPostDetailScreenState();
}

class _CommunityPostDetailScreenState extends State<CommunityPostDetailScreen> {
  final TextEditingController _commentController = TextEditingController();
  bool _feedbackMode = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitComment() async {
    final comment = await widget.communityManager.addComment(
      postId: widget.postId,
      body: _commentController.text,
      isFeedback: _feedbackMode,
    );
    if (!mounted) {
      return;
    }
    if (comment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.communityManager.errorMessage ?? '댓글을 저장하지 못했습니다.',
          ),
        ),
      );
      return;
    }
    _commentController.clear();
    setState(() {
      _feedbackMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.communityManager,
      builder: (context, _) {
        final post = widget.communityManager.getPost(widget.postId);
        if (post == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('커뮤니티 글')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('게시글을 찾지 못했습니다.'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('이전 화면으로'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final currentUserId = widget.communityManager.currentUser?.id;
        final isLiked = currentUserId != null && post.isLikedBy(currentUserId);
        final comments = widget.communityManager.commentsForPost(post.id);

        return Scaffold(
          appBar: AppBar(
            title: Text(post.siteName),
            actions: [
              IconButton(
                onPressed: () => widget.communityManager.toggleLike(post.id),
                icon: Icon(
                  isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
                tooltip: '좋아요',
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x16000000),
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      FilterChip(
                        label: const Text('참고 피드백'),
                        selected: _feedbackMode,
                        onSelected: (value) {
                          setState(() {
                            _feedbackMode = value;
                          });
                        },
                      ),
                      const Spacer(),
                      Text(
                        _feedbackMode
                            ? '부드러운 피드백으로 남깁니다.'
                            : '응원이나 질문 답변을 남겨보세요.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: '댓글 남기기',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _submitComment,
                        child: const Text('등록'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
            children: [
              CommunityPostCard(
                post: post,
                isLiked: isLiked,
                onTap: () {},
                onLike: () => widget.communityManager.toggleLike(post.id),
              ),
              const SizedBox(height: 2),
              _PostSummaryCard(post: post),
              if (post.media.isNotEmpty) ...[
                const SizedBox(height: 16),
                const _SectionTitle(
                  title: '첨부한 사진과 동영상',
                  subtitle: '현장에서 남긴 기록을 함께 확인할 수 있습니다.',
                ),
                const SizedBox(height: 12),
                ...post.media.map(
                  (media) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _MediaDisplayCard(media: media),
                  ),
                ),
              ],
              if (post.body.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                const _SectionTitle(
                  title: '비행일지 본문',
                  subtitle: '실제 비행과 연결된 기록이라 더 읽기 쉽게 구성했습니다.',
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      post.body.trim(),
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(height: 1.6),
                    ),
                  ),
                ),
              ],
              if (post.questionText.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  color: const Color(0xFFF5F3FF),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '함께 묻고 싶은 질문',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Text(post.questionText.trim()),
                      ],
                    ),
                  ),
                ),
              ],
              if (post.flightSessionId != null) ...[
                const SizedBox(height: 16),
                const _SectionTitle(
                  title: '연결된 비행 기록',
                  subtitle: '비행 경로와 분석 화면으로 바로 이어집니다.',
                ),
                const SizedBox(height: 12),
                FutureBuilder<FlightSessionDetail?>(
                  future: widget.flightRecordManager
                      .getSessionDetail(post.flightSessionId!),
                  builder: (context, snapshot) {
                    final detail = snapshot.data;
                    if (detail == null || detail.points.isEmpty) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              const Icon(Icons.map_outlined),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  snapshot.connectionState ==
                                          ConnectionState.waiting
                                      ? '비행 경로를 불러오는 중입니다.'
                                      : '연결된 경로 정보가 없어서 요약만 표시합니다.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FlightMapView(
                              points: detail.points,
                              height: 220,
                              showLegend: true,
                              emptyMessage: '경로 정보가 충분하지 않습니다.',
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.pushNamed(
                                        context,
                                        AppRoutes.flightRecordDetail,
                                        arguments: FlightRecordDetailArgs(
                                          sessionId: post.flightSessionId!,
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.analytics_outlined),
                                    label: const Text('비행 분석 보기'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          widget.communityManager.toggleLike(post.id),
                      icon: Icon(
                        isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                      ),
                      label: Text(isLiked ? '응원 취소' : '응원해요'),
                    ),
                  ),
                  if (post.siteName.trim().isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pushNamed(
                            context,
                            AppRoutes.siteCommunity,
                            arguments: SiteCommunityArgs(
                              siteId: post.siteId,
                              siteName: post.siteName,
                            ),
                          );
                        },
                        icon: const Icon(Icons.forum_outlined),
                        label: const Text('이륙장 피드 보기'),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              _SectionTitle(
                title: '댓글 ${comments.length}',
                subtitle: '응원과 경험 공유가 이어지는 공간입니다.',
              ),
              const SizedBox(height: 12),
              if (comments.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('아직 댓글이 없습니다. 첫 댓글로 응원이나 팁을 남겨보세요.'),
                  ),
                ),
              ...comments.map(
                (comment) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            comment.authorName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (comment.isFeedback)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F0FE),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              '피드백',
                              style: TextStyle(
                                color: Color(0xFF2563EB),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(comment.body),
                          const SizedBox(height: 8),
                          Text(
                            formatDateTime(comment.createdAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
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

class _PostSummaryCard extends StatelessWidget {
  const _PostSummaryCard({required this.post});

  final FlightJournalPost post;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '비행 요약 카드',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _SummaryChip(label: '비행일', value: formatDate(post.flightDate)),
                _SummaryChip(
                  label: '비행 시간',
                  value:
                      formatDuration(Duration(seconds: post.durationSeconds)),
                ),
                _SummaryChip(
                  label: '최고 고도',
                  value: formatAltitudeMeters(post.maxAltitudeMeters),
                ),
                _SummaryChip(
                  label: '이동 거리',
                  value: formatDistanceMeters(post.totalDistanceMeters),
                ),
              ],
            ),
            if (post.weatherSummary.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('날씨 요약: ${post.weatherSummary}'),
            ],
            if (post.flyabilitySummary.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('비행 참고 상태: ${post.flyabilitySummary}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _MediaDisplayCard extends StatelessWidget {
  const _MediaDisplayCard({required this.media});

  final FlightJournalMedia media;

  @override
  Widget build(BuildContext context) {
    final color = media.type == FlightJournalMediaType.image
        ? const Color(0xFF2A9D8F)
        : const Color(0xFF8B5CF6);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              media.type == FlightJournalMediaType.image
                  ? Icons.photo_library_rounded
                  : Icons.play_circle_fill_rounded,
              color: color,
              size: 28,
            ),
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
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text('${media.type.label} 첨부',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
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
      ],
    );
  }
}
