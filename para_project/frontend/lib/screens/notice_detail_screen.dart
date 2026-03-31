import 'package:flutter/material.dart';

import '../core/utils.dart';
import '../models/app_models.dart';
import '../repositories/app_repository.dart';

class NoticeDetailScreen extends StatefulWidget {
  const NoticeDetailScreen({
    super.key,
    required this.repository,
    required this.noticeId,
  });

  final AppRepository repository;
  final int noticeId;

  @override
  State<NoticeDetailScreen> createState() => _NoticeDetailScreenState();
}

class _NoticeDetailScreenState extends State<NoticeDetailScreen> {
  late Future<NoticeItem> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.getNoticeDetail(noticeId: widget.noticeId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('공지 상세')),
      body: FutureBuilder<NoticeItem>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('공지 상세를 불러오지 못했습니다.'));
          }
          final notice = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notice.title,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                          '${notice.category.noticeCategoryLabel} | ${formatDate(notice.publishedAt)}'),
                      const SizedBox(height: 18),
                      Text(notice.body),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
