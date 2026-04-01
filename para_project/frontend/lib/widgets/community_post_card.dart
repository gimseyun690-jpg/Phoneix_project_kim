import 'package:flutter/material.dart';

import '../core/utils.dart';
import '../models/app_models.dart';

class CommunityPostCard extends StatelessWidget {
  const CommunityPostCard({
    super.key,
    required this.post,
    required this.isLiked,
    required this.onTap,
    required this.onLike,
  });

  final FlightJournalPost post;
  final bool isLiked;
  final VoidCallback onTap;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post.hasMedia)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF173845),
                      Color(0xFF2A6F80),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        post.videoCount > 0
                            ? Icons.play_circle_fill_rounded
                            : Icons.photo_library_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.imageCount > 0 && post.videoCount > 0
                                ? '사진 ${post.imageCount}장 · 동영상 ${post.videoCount}개'
                                : post.imageCount > 0
                                    ? '사진 ${post.imageCount}장 첨부'
                                    : '동영상 ${post.videoCount}개 첨부',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '비행일지와 함께 현장 기록을 남겼습니다.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.86),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFFE8F1F4),
                        child: Text(
                          post.authorName.characters.first,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF173845),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              post.authorName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${post.siteName} · ${formatDateTime(post.createdAt)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      _VisibilityBadge(visibility: post.visibility),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    post.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetaChip(text: formatDate(post.flightDate)),
                      _MetaChip(
                        text: formatDuration(
                          Duration(seconds: post.durationSeconds),
                        ),
                      ),
                      _MetaChip(
                        text:
                            '최고 ${formatAltitudeMeters(post.maxAltitudeMeters)}',
                      ),
                      _MetaChip(
                        text: formatDistanceMeters(post.totalDistanceMeters),
                      ),
                      if (post.hasQuestion)
                        const _MetaChip(
                          text: '질문 있음',
                          accentColor: Color(0xFF8B5CF6),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (post.summaryText.trim().isNotEmpty)
                    Text(
                      post.summaryText.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF264653),
                        height: 1.45,
                      ),
                    ),
                  if (post.body.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      post.body.trim(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: onLike,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isLiked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 18,
                                color: isLiked
                                    ? const Color(0xFFE76F51)
                                    : const Color(0xFF607080),
                              ),
                              const SizedBox(width: 6),
                              Text('좋아요 ${post.likeCount}'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 18,
                            color: Color(0xFF607080),
                          ),
                          const SizedBox(width: 6),
                          Text('댓글 ${post.commentCount}'),
                        ],
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: onTap,
                        child: const Text('자세히 보기'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.text,
    this.accentColor = const Color(0xFFE8EEF2),
  });

  final String text;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accentColor,
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

class _VisibilityBadge extends StatelessWidget {
  const _VisibilityBadge({required this.visibility});

  final CommunityVisibility visibility;

  @override
  Widget build(BuildContext context) {
    final color = switch (visibility) {
      CommunityVisibility.public => const Color(0xFF2A9D8F),
      CommunityVisibility.siteOnly => const Color(0xFF2563EB),
      CommunityVisibility.private => const Color(0xFF6B7280),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        visibility.label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}
