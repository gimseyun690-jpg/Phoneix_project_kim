import 'package:flutter/material.dart';

import '../app.dart';
import '../models/app_models.dart';
import '../repositories/app_repository.dart';
import '../widgets/status_chip.dart';

class SiteListScreen extends StatefulWidget {
  const SiteListScreen({
    super.key,
    required this.repository,
    required this.user,
  });

  final AppRepository repository;
  final AppUser user;

  @override
  State<SiteListScreen> createState() => _SiteListScreenState();
}

class _SiteListScreenState extends State<SiteListScreen> {
  final _searchController = TextEditingController();
  late Future<List<SiteSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.getSites(pilotLevel: widget.user.pilotLevel);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search() {
    setState(() {
      _future = widget.repository.getSites(
        pilotLevel: widget.user.pilotLevel,
        query: _searchController.text,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                    hintText: '지역 또는 사이트명 검색',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _search,
                child: const Text('검색'),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<SiteSummary>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Center(child: Text('사이트 목록을 불러오지 못했습니다.'));
              }
              final sites = snapshot.data ?? [];
              if (sites.isEmpty) {
                return const Center(child: Text('검색 결과가 없습니다.'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: sites.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final site = sites[index];
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(site.name),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _LabelChip(text: site.region),
                                _LabelChip(
                                    text: site.difficulty.siteDifficultyLabel),
                                _LabelChip(
                                    text: site.beginnerAllowed
                                        ? '초급 가능'
                                        : '초급 제한'),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(site.shortDescription),
                          ],
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          StatusChip(status: site.assessment.status),
                          const SizedBox(height: 8),
                          Text('${site.assessment.score}점'),
                        ],
                      ),
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          AppRoutes.siteDetail,
                          arguments: SiteDetailArgs(
                            siteId: site.id,
                            pilotLevel: widget.user.pilotLevel,
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LabelChip extends StatelessWidget {
  const _LabelChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text),
    );
  }
}
