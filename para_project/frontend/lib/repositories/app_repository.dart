import '../models/app_models.dart';

abstract class AppRepository {
  Future<AppUser> login({required String email, required String password});

  Future<HomeData> getHome({required PilotLevel pilotLevel});

  Future<List<SiteSummary>> getSites({
    required PilotLevel pilotLevel,
    String query = '',
  });

  Future<SiteDetail> getSiteDetail({
    required int siteId,
    required PilotLevel pilotLevel,
  });

  Future<List<TrainingLog>> getTrainingLogs({required int userId});

  Future<TrainingLog> createTrainingLog(TrainingLogDraft draft);

  Future<List<NoticeItem>> getNotices();

  Future<NoticeItem> getNoticeDetail({required int noticeId});
}
