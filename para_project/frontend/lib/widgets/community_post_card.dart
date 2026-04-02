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
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post.hasMedia)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        post.videoCount > 0
                            ? Icons.play_circle_fill_rounded
                            : Icons.photo_library_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 10),
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
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
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
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFFE8F1F4),
                        child: Text(
                          post.authorName.characters.first,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF173845),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              post.authorName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${post.siteName} · ${formatDateTime(post.createdAt)}',
                              style: theme.textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      _VisibilityBadge(visibility: post.visibility),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF264653),
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (post.body.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      post.body.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.5,
                        color: const Color(0xFF4B5563),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 360;
                      final stats = Wrap(
                        spacing: 14,
                        runSpacing: 8,
                        children: [
                          _ActionStat(
                            icon: isLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            label: '좋아요 ${post.likeCount}',
                            color: isLiked
                                ? const Color(0xFFE76F51)
                                : const Color(0xFF607080),
                            onTap: onLike,
                          ),
                          _ActionStat(
                            icon: Icons.chat_bubble_outline_rounded,
                            label: '댓글 ${post.commentCount}',
                            color: const Color(0xFF607080),
                          ),
                        ],
                      );

                      final detailButton = TextButton(
                        onPressed: onTap,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        child: const Text('자세히 보기'),
                      );

                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            stats,
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: detailButton,
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: stats),
                          const SizedBox(width: 12),
                          detailButton,
                        ],
                      );
                    },
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accentColor.withValues(
            alpha: accentColor == const Color(0xFF8B5CF6) ? 0.16 : 1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: accentColor == const Color(0xFF8B5CF6)
                  ? const Color(0xFF7C3AED)
                  : const Color(0xFF304454),
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        visibility.label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
      ),
    );
  }
}

class _ActionStat extends StatelessWidget {
  const _ActionStat({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF5B6674),
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );

    if (onTap == null) {
      return child;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: child,
      ),
    );
  }
}
