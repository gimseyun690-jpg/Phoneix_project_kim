import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_models.dart';
import 'app_repository.dart';

class ApiAppRepository implements AppRepository {
  ApiAppRepository({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<Map<String, dynamic>> _getObject(String path) async {
    final response = await _client.get(Uri.parse('$baseUrl$path'));
    if (response.statusCode >= 400) {
      throw Exception('API 조회에 실패했습니다. (${response.statusCode})');
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<List<dynamic>> _getList(String path) async {
    final response = await _client.get(Uri.parse('$baseUrl$path'));
    if (response.statusCode >= 400) {
      throw Exception('API 조회에 실패했습니다. (${response.statusCode})');
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
  }

  Future<Map<String, dynamic>> _postObject(
      String path, Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (response.statusCode >= 400) {
      throw Exception('API 저장에 실패했습니다. (${response.statusCode})');
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  @override
  Future<AppUser> login(
      {required String email, required String password}) async {
    final json = await _postObject(
        '/auth/login', {'email': email, 'password': password});
    return AppUser.fromJson(json['user'] as Map<String, dynamic>);
  }

  @override
  Future<HomeData> getHome({required PilotLevel pilotLevel}) async {
    final json = await _getObject('/home?pilot_level=${pilotLevel.value}');
    return HomeData.fromJson(json);
  }

  @override
  Future<List<SiteSummary>> getSites({
    required PilotLevel pilotLevel,
    String query = '',
  }) async {
    final encodedQuery = Uri.encodeQueryComponent(query);
    final json = await _getList(
        '/sites?pilot_level=${pilotLevel.value}&q=$encodedQuery');
    return json
        .map((item) => SiteSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<SiteDetail> getSiteDetail({
    required int siteId,
    required PilotLevel pilotLevel,
  }) async {
    final json =
        await _getObject('/sites/$siteId?pilot_level=${pilotLevel.value}');
    return SiteDetail.fromJson(json);
  }

  @override
  Future<List<TrainingLog>> getTrainingLogs({required int userId}) async {
    final json = await _getList('/training-logs?user_id=$userId');
    return json
        .map((item) => TrainingLog.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<TrainingLog> createTrainingLog(TrainingLogDraft draft) async {
    final json = await _postObject('/training-logs', draft.toJson());
    return TrainingLog.fromJson(json);
  }

  @override
  Future<List<NoticeItem>> getNotices() async {
    final json = await _getList('/notices');
    return json
        .map((item) => NoticeItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<NoticeItem> getNoticeDetail({required int noticeId}) async {
    final json = await _getObject('/notices/$noticeId');
    return NoticeItem.fromJson(json);
  }
}
