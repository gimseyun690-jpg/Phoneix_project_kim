import 'package:flutter/material.dart';

import '../app.dart';
import '../core/utils.dart';
import '../models/app_models.dart';
import '../repositories/app_repository.dart';

class NoticesScreen extends StatefulWidget {
  const NoticesScreen({
    super.key,
    required this.repository,
  });

  final AppRepository repository;

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  late Future<List<NoticeItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.getNotices();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<NoticeItem>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('공지 목록을 불러오지 못했습니다.'));
        }
        final notices = snapshot.data ?? [];
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: notices.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final notice = notices[index];
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                title: Row(
                  children: [
                    Expanded(child: Text(notice.title)),
                    if (notice.isPinned)
                      const Icon(Icons.push_pin_outlined, size: 18),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${notice.category.noticeCategoryLabel} | ${formatDate(notice.publishedAt)}'),
                      const SizedBox(height: 8),
                      Text(
                        notice.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    AppRoutes.noticeDetail,
                    arguments: NoticeDetailArgs(noticeId: notice.id),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
