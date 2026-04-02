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
  final FocusNode _commentFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _feedbackMode = false;

  @override
  void initState() {
    super.initState();
    _commentFocusNode.addListener(_handleCommentFocusChanged);
  }

  @override
  void dispose() {
    _commentFocusNode.removeListener(_handleCommentFocusChanged);
    _scrollController.dispose();
    _commentFocusNode.dispose();
    _commentController.dispose();
    super.dispose();
  }

  void _handleCommentFocusChanged() {
    if (!_commentFocusNode.hasFocus) {
      return;
    }
    _scrollToCommentBottom();
    Future<void>.delayed(const Duration(milliseconds: 260), () {
      if (!mounted || !_commentFocusNode.hasFocus) {
        return;
      }
      _scrollToCommentBottom();
    });
  }

  void _scrollToCommentBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final target = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _commentFocusNode.requestFocus();
      _scrollToCommentBottom();
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
        final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

        return Scaffold(
          resizeToAvoidBottomInset: false,
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
          body: SafeArea(
            top: false,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(bottom: keyboardInset),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      controller: _scrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        const _SectionTitle(
                          title: '게시된 비행일지',
                          subtitle: '이륙장 피드에 올라간 원본 내용을 다시 확인합니다.',
                        ),
                        const SizedBox(height: 12),
                        CommunityPostCard(
                          post: post,
                          isLiked: isLiked,
                          onTap: () {},
                          onLike: () =>
                              widget.communityManager.toggleLike(post.id),
                        ),
                        const SizedBox(height: 4),
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
                          _SurfaceCard(
                            child: Text(
                              post.body.trim(),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    height: 1.65,
                                    color: const Color(0xFF334155),
                                  ),
                            ),
                          ),
                        ],
                        if (post.questionText.trim().isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _SurfaceCard(
                            backgroundColor: const Color(0xFFF7F3FF),
                            borderColor:
                                const Color(0xFF8B5CF6).withValues(alpha: 0.14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '함께 묻고 싶은 질문',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  post.questionText.trim(),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        height: 1.55,
                                        color: const Color(0xFF4C1D95),
                                      ),
                                ),
                              ],
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
                                return _SurfaceCard(
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
                                );
                              }

                              return _SurfaceCard(
                                padding:
                                    const EdgeInsets.fromLTRB(14, 14, 14, 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    FlightMapView(
                                      points: detail.points,
                                      height: 220,
                                      showLegend: false,
                                      emptyMessage: '경로 정보가 충분하지 않습니다.',
                                    ),
                                    const SizedBox(height: 12),
                                    const Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _LegendPill(
                                          color: Color(0xFF2A9D8F),
                                          label: '출발',
                                          icon: Icons.flight_takeoff_rounded,
                                        ),
                                        _LegendPill(
                                          color: Color(0xFFE76F51),
                                          label: '종료',
                                          icon: Icons.flag_rounded,
                                        ),
                                      ],
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
                                                arguments:
                                                    FlightRecordDetailArgs(
                                                  sessionId:
                                                      post.flightSessionId!,
                                                ),
                                              );
                                            },
                                            icon: const Icon(
                                              Icons.analytics_outlined,
                                            ),
                                            label: const Text('비행 분석 보기'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final stacked = constraints.maxWidth < 380;
                            final likeButton = FilledButton.tonalIcon(
                              onPressed: () =>
                                  widget.communityManager.toggleLike(post.id),
                              icon: Icon(
                                isLiked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                              ),
                              label: Text(isLiked ? '응원 취소' : '응원해요'),
                            );
                            final siteButton = post.siteName.trim().isEmpty
                                ? null
                                : OutlinedButton.icon(
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
                                  );

                            if (stacked) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  likeButton,
                                  if (siteButton != null) ...[
                                    const SizedBox(height: 10),
                                    siteButton,
                                  ],
                                ],
                              );
                            }

                            return Row(
                              children: [
                                Expanded(child: likeButton),
                                if (siteButton != null) ...[
                                  const SizedBox(width: 10),
                                  Expanded(child: siteButton),
                                ],
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        _SectionTitle(
                          title: '댓글 ${comments.length}',
                          subtitle: '응원과 경험 공유가 이어지는 공간입니다.',
                        ),
                        const SizedBox(height: 12),
                        if (comments.isEmpty)
                          const _SurfaceCard(
                            child: Text(
                              '아직 댓글이 없습니다. 첫 댓글로 응원이나 팁을 남겨보세요.',
                            ),
                          ),
                        ...comments.map(
                          (comment) => _CommentCard(
                            margin: const EdgeInsets.only(bottom: 10),
                            comment: comment,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _CommentComposerBar(
                    controller: _commentController,
                    focusNode: _commentFocusNode,
                    feedbackMode: _feedbackMode,
                    isWorking: widget.communityManager.isWorking,
                    onFeedbackModeChanged: (value) {
                      setState(() {
                        _feedbackMode = value;
                      });
                    },
                    onSubmit: _submitComment,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CommentComposerBar extends StatelessWidget {
  const _CommentComposerBar({
    required this.controller,
    required this.focusNode,
    required this.feedbackMode,
    required this.isWorking,
    required this.onFeedbackModeChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool feedbackMode;
  final bool isWorking;
  final ValueChanged<bool> onFeedbackModeChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFDFEFF),
          border: Border(
            top: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.18),
            ),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 18,
              offset: Offset(0, -6),
            ),
          ],
        ),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final canSubmit = value.text.trim().isNotEmpty && !isWorking;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      label: const Text('참고 피드백'),
                      selected: feedbackMode,
                      onSelected: onFeedbackModeChanged,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      selectedColor: const Color(0xFFE0EFF4),
                      backgroundColor: const Color(0xFFF7F9FB),
                      side: BorderSide(
                        color: feedbackMode
                            ? const Color(0xFF1F6E82).withValues(alpha: 0.24)
                            : const Color(0xFFE2E8F0),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Text(
                      feedbackMode ? '부드러운 피드백으로 남깁니다.' : '응원이나 질문 답변을 남겨보세요.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 380;
                    final field = TextField(
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      scrollPadding: const EdgeInsets.only(bottom: 120),
                      decoration: InputDecoration(
                        hintText: feedbackMode ? '참고 피드백을 남겨보세요' : '댓글 남기기',
                        helperText: '입력 중에도 최근 댓글을 계속 확인할 수 있습니다.',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                    );

                    final submitButton = FilledButton(
                      onPressed: canSubmit ? onSubmit : null,
                      style: FilledButton.styleFrom(
                        minimumSize: Size(stacked ? 0 : 72, 50),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: Text(isWorking ? '저장 중' : '등록'),
                    );

                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          field,
                          const SizedBox(height: 10),
                          submitButton,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: field),
                        const SizedBox(width: 10),
                        submitButton,
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PostSummaryCard extends StatelessWidget {
  const _PostSummaryCard({required this.post});

  final FlightJournalPost post;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
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
                value: formatDuration(Duration(seconds: post.durationSeconds)),
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
            Text(
              '날씨 요약',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF173845),
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              post.weatherSummary,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF475569),
                    height: 1.45,
                  ),
            ),
          ],
          if (post.flyabilitySummary.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '비행 참고 상태',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF173845),
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              post.flyabilitySummary,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF475569),
                    height: 1.45,
                  ),
            ),
          ],
        ],
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
        ),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              media.type == FlightJournalMediaType.image
                  ? Icons.photo_library_rounded
                  : Icons.play_circle_fill_rounded,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(width: 10),
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
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
        ),
      ],
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.backgroundColor = Colors.white,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: borderColor ??
              Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({
    required this.comment,
    this.margin = EdgeInsets.zero,
  });

  final PostComment comment;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    comment.authorName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                if (comment.isFeedback)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            const SizedBox(height: 10),
            Text(
              comment.body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.55,
                    color: const Color(0xFF334155),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              formatDateTime(comment.createdAt),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendPill extends StatelessWidget {
  const _LegendPill({
    required this.color,
    required this.label,
    required this.icon,
  });

  final Color color;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
