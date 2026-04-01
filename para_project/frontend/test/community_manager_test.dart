import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:paragliding_mvp_frontend/core/community_manager.dart';
import 'package:paragliding_mvp_frontend/models/app_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CommunityManager', () {
    late CommunityManager manager;
    const user = AppUser(
      id: 7,
      email: 'pilot@example.com',
      fullName: '김파일럿',
      pilotLevel: PilotLevel.intermediate,
      isAdmin: false,
    );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      manager = CommunityManager();
      await manager.initialize(user: user);
    });

    test('비행일지를 저장하고 좋아요와 댓글을 반영한다', () async {
      final saved = await manager.saveJournal(
        FlightJournalDraft(
          userId: user.id,
          authorName: user.fullName,
          flightSessionId: 'session_1',
          siteId: 3,
          siteName: '문경 이륙장',
          siteRegion: '경북 문경',
          title: '오후 상승기류 체크',
          body: '상승기류가 부드럽게 이어져서 기록을 남깁니다.',
          questionText: '후반 접근 라인에 대한 의견을 듣고 싶습니다.',
          visibility: CommunityVisibility.siteOnly,
          flightDate: DateTime(2026, 4, 1, 13, 0),
          flightStartedAt: DateTime(2026, 4, 1, 13, 5),
          flightEndedAt: DateTime(2026, 4, 1, 14, 2),
          durationSeconds: 3420,
          totalDistanceMeters: 18240,
          maxAltitudeMeters: 1180,
          weatherSummary: '북서풍 약함, 시정 양호',
          flyabilitySummary: '비행 가능',
          summaryText: '57분 비행, 최고 1180m, 총 이동 18.2km',
          media: const [],
        ),
      );

      expect(saved, isNotNull);
      expect(manager.posts, hasLength(1));
      expect(manager.posts.first.commentCount, 0);
      expect(manager.posts.first.likeCount, 0);

      final liked = await manager.toggleLike(saved!.id);
      expect(liked, isTrue);
      expect(manager.getPost(saved.id)?.likeCount, 1);

      final comment = await manager.addComment(
        postId: saved.id,
        body: '후반 라인이 깔끔해서 참고가 됩니다.',
        isFeedback: true,
      );
      expect(comment, isNotNull);
      expect(manager.commentsForPost(saved.id), hasLength(1));
      expect(manager.getPost(saved.id)?.commentCount, 1);
      expect(manager.siteFeedCount(siteId: 3), 1);
    });
  });
}
