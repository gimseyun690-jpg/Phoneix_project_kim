import '../core/utils.dart';
import '../models/app_models.dart';
import 'app_repository.dart';

class MockAppRepository implements AppRepository {
  MockAppRepository();

  final List<Map<String, dynamic>> _siteMaps = _buildSiteMaps();
  final List<Map<String, dynamic>> _noticeMaps = _buildNoticeMaps();
  final List<Map<String, dynamic>> _trainingLogMaps = _buildTrainingLogMaps();

  static List<Map<String, dynamic>> _buildSiteMaps() {
    final now = DateTime.now();

    Map<String, dynamic> weather({
      required double avg,
      required int direction,
      required double gust,
      required double? rain,
      required String summary,
      required List<Map<String, dynamic>> hourly,
    }) {
      return {
        'observed_at': now.toIso8601String(),
        'average_wind_speed': avg,
        'wind_direction': direction,
        'gust_speed': gust,
        'precipitation_mm': rain,
        'summary': summary,
        'hourly_forecast': hourly,
      };
    }

    List<Map<String, dynamic>> hourly(
            double baseAvg, int baseDirection, double baseGust, double? rain) =>
        [
          {
            'time_label': '09:00',
            'average_wind_speed': baseAvg - 0.4,
            'wind_direction': baseDirection - 10,
            'gust_speed': baseGust - 0.2,
            'precipitation_mm': rain,
          },
          {
            'time_label': '12:00',
            'average_wind_speed': baseAvg,
            'wind_direction': baseDirection,
            'gust_speed': baseGust,
            'precipitation_mm': rain,
          },
          {
            'time_label': '15:00',
            'average_wind_speed': baseAvg + 0.5,
            'wind_direction': baseDirection + 8,
            'gust_speed': baseGust + 0.6,
            'precipitation_mm': rain,
          },
        ];

    return [
      {
        'id': 1,
        'name': '양평 패러밸리',
        'region': '경기',
        'difficulty': 'beginner',
        'short_description': '초급자 훈련과 클럽 비행에 자주 쓰이는 완만한 능선 사이트',
        'beginner_allowed': true,
        'description': '남서풍 계열에서 비교적 안정적이며, 교육 비행과 팀 브리핑에 많이 사용됩니다.',
        'takeoff_altitude_m': 640,
        'landing_altitude_m': 180,
        'allowed_direction_range': '180-250도',
        'rule': {
          'notes': '남서풍 기준 운영, 초급 교육 비행 가능',
          'allowed_direction_start': 180,
          'allowed_direction_end': 250,
          'beginner_allowed': true,
          'max_gust': 8.5,
          'max_gust_difference': 2.5,
        },
        'weather': weather(
          avg: 4.8,
          direction: 215,
          gust: 6.4,
          rain: 0.0,
          summary: '구름 조금, 이륙장 시정 양호',
          hourly: hourly(4.8, 215, 6.4, 0.0),
        ),
        'assessment': {
          'score': 100,
          'status': 'good',
          'reasons': ['주요 비행 기준을 모두 충족합니다.'],
          'summary_text': '현재 기준으로는 비행 여건이 양호합니다.',
        },
      },
      {
        'id': 2,
        'name': '단양 리지포인트',
        'region': '충북',
        'difficulty': 'intermediate',
        'short_description': '열활공과 크로스컨트리 입문에 적합한 대표 리지 사이트',
        'beginner_allowed': true,
        'description': '풍향이 맞으면 좋은 상승대를 기대할 수 있지만, 오후 돌풍을 확인해야 합니다.',
        'takeoff_altitude_m': 780,
        'landing_altitude_m': 210,
        'allowed_direction_range': '130-210도',
        'rule': {
          'notes': '오후 돌풍 점검 필요',
          'allowed_direction_start': 130,
          'allowed_direction_end': 210,
          'beginner_allowed': true,
          'max_gust': 9.0,
          'max_gust_difference': 3.0,
        },
        'weather': weather(
          avg: 5.8,
          direction: 165,
          gust: 8.1,
          rain: 0.0,
          summary: '정오 이후 풍속 증가 예상',
          hourly: hourly(5.8, 165, 8.1, 0.0),
        ),
        'assessment': {
          'score': 70,
          'status': 'caution',
          'reasons': ['평균 풍속 5.8m/s가 초급 기준 4.5m/s를 초과합니다.'],
          'summary_text': '일부 조건이 한계에 가까워 주의가 필요합니다.',
        },
      },
      {
        'id': 3,
        'name': '제주 코스탈 클리프',
        'region': '제주',
        'difficulty': 'advanced',
        'short_description': '해안 지형 영향이 큰 숙련자 전용 사이트',
        'beginner_allowed': false,
        'description': '해풍 변화가 빠르고 돌풍 편차가 커서 숙련자 중심으로 운영됩니다.',
        'takeoff_altitude_m': 420,
        'landing_altitude_m': 35,
        'allowed_direction_range': '40-110도',
        'rule': {
          'notes': '숙련자 전용, 해안 돌풍 주의',
          'allowed_direction_start': 40,
          'allowed_direction_end': 110,
          'beginner_allowed': false,
          'max_gust': 10.0,
          'max_gust_difference': 2.5,
        },
        'weather': weather(
          avg: 6.9,
          direction: 128,
          gust: 11.8,
          rain: 0.6,
          summary: '풍향 이탈과 약한 강수 가능성',
          hourly: hourly(6.9, 128, 11.8, 0.6),
        ),
        'assessment': {
          'score': 0,
          'status': 'bad',
          'reasons': [
            '초급자 비행이 허용되지 않는 사이트입니다.',
            '현재 풍향 128도가 허용 범위 40-110도 밖입니다.',
            '평균 풍속 6.9m/s가 초급 기준 4.0m/s를 초과합니다.',
            '최대 돌풍 11.8m/s가 허용치 10.0m/s를 초과합니다.',
            '돌풍 편차 4.9m/s가 허용 편차 2.5m/s를 초과합니다.',
            '강수 가능성이 있어 비행을 권장하지 않습니다.',
          ],
          'summary_text': '안전 기준을 충족하지 않아 비행 비추천입니다.',
        },
      },
      {
        'id': 4,
        'name': '문경 활공랜드',
        'region': '경북 문경',
        'difficulty': 'intermediate',
        'short_description': '넓은 착륙장과 계곡풍 판단 연습에 적합한 내륙 사이트',
        'beginner_allowed': true,
        'description': '오전에는 비교적 안정적이지만 오후에는 계곡풍이 강해질 수 있어 시간대 판단이 중요합니다.',
        'takeoff_altitude_m': 690,
        'landing_altitude_m': 160,
        'allowed_direction_range': '210-280도',
        'rule': {
          'notes': '오전 비행 적합, 오후 계곡풍 증폭 주의',
          'allowed_direction_start': 210,
          'allowed_direction_end': 280,
          'beginner_allowed': true,
          'max_gust': 8.8,
          'max_gust_difference': 2.8,
        },
        'weather': weather(
          avg: 5.1,
          direction: 238,
          gust: 7.0,
          rain: 0.0,
          summary: '오전 약한 남서풍, 시정 양호',
          hourly: hourly(5.1, 238, 7.0, 0.0),
        ),
        'assessment': {
          'score': 78,
          'status': 'caution',
          'reasons': ['평균 풍속 5.1m/s가 초급 기준 4.8m/s를 초과합니다.'],
          'summary_text': '일부 조건이 한계에 가까워 주의가 필요합니다.',
        },
      },
    ];
  }

  static List<Map<String, dynamic>> _buildNoticeMaps() {
    final now = DateTime.now();
    return [
      {
        'id': 1,
        'title': '주말 클럽 브리핑 시간 변경',
        'body': '이번 주 토요일 브리핑은 오전 8시 30분에 착륙장에서 시작합니다.',
        'category': 'club',
        'is_pinned': true,
        'published_at': now.subtract(const Duration(days: 1)).toIso8601String(),
        'created_at': now.subtract(const Duration(days: 2)).toIso8601String(),
        'updated_at': now.subtract(const Duration(days: 1)).toIso8601String(),
      },
      {
        'id': 2,
        'title': '양평 패러밸리 초급 교육 편성',
        'body': '초급자 1차 교육은 양평 패러밸리에서 진행되며 헬멧, 장갑, 무전기 점검이 필수입니다.',
        'category': 'training',
        'is_pinned': false,
        'published_at': now.subtract(const Duration(days: 2)).toIso8601String(),
        'created_at': now.subtract(const Duration(days: 3)).toIso8601String(),
        'updated_at': now.subtract(const Duration(days: 2)).toIso8601String(),
      },
      {
        'id': 3,
        'title': '문경 활공랜드 진입로 혼잡 안내',
        'body': '주말 오전에는 행사 차량이 많아 문경 활공랜드 진입 시간이 지연될 수 있습니다.',
        'category': 'safety',
        'is_pinned': false,
        'published_at': now.subtract(const Duration(days: 3)).toIso8601String(),
        'created_at': now.subtract(const Duration(days: 4)).toIso8601String(),
        'updated_at': now.subtract(const Duration(days: 3)).toIso8601String(),
      },
    ];
  }

  static List<Map<String, dynamic>> _buildTrainingLogMaps() {
    final now = DateTime.now();
    return [
      {
        'id': 1,
        'user_id': 2,
        'site_id': 1,
        'site_name': '양평 패러밸리',
        'training_date': formatDate(now.subtract(const Duration(days: 7))),
        'training_type': '이륙 반복 훈련',
        'participated': true,
        'flight_success': true,
        'difficulty': 'easy',
        'memo': '런업과 자세 교정 중심으로 진행',
        'created_at': now.subtract(const Duration(days: 7)).toIso8601String(),
      },
      {
        'id': 2,
        'user_id': 2,
        'site_id': 2,
        'site_name': '단양 리지포인트',
        'training_date': formatDate(now.subtract(const Duration(days: 2))),
        'training_type': '리지 판단 브리핑',
        'participated': true,
        'flight_success': false,
        'difficulty': 'medium',
        'memo': '오후 돌풍 증가로 실제 비행은 취소',
        'created_at': now.subtract(const Duration(days: 2)).toIso8601String(),
      },
      {
        'id': 3,
        'user_id': 2,
        'site_id': 4,
        'site_name': '문경 활공랜드',
        'training_date': formatDate(now.subtract(const Duration(days: 1))),
        'training_type': '계곡풍 판단 훈련',
        'participated': true,
        'flight_success': true,
        'difficulty': 'medium',
        'memo': '정오 전 이륙 후 접근 패턴을 복습했습니다.',
        'created_at': now.subtract(const Duration(days: 1)).toIso8601String(),
      },
    ];
  }

  Future<T> _delayed<T>(T value) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return value;
  }

  @override
  Future<AppUser> login(
      {required String email, required String password}) async {
    if ((email == 'pilot@parawing.local' && password == 'pilot123') ||
        (email == 'admin@parawing.local' && password == 'admin123')) {
      final isAdmin = email.startsWith('admin');
      return _delayed(
        AppUser(
          id: isAdmin ? 1 : 2,
          email: email,
          fullName: isAdmin ? '관리자' : '김초급',
          pilotLevel: isAdmin ? PilotLevel.advanced : PilotLevel.beginner,
          isAdmin: isAdmin,
        ),
      );
    }
    throw Exception('이메일 또는 비밀번호가 올바르지 않습니다.');
  }

  @override
  Future<HomeData> getHome({required PilotLevel pilotLevel}) async {
    final sites = _siteMaps.map(SiteSummary.fromJson).toList();
    sites.sort((a, b) => b.assessment.score.compareTo(a.assessment.score));
    return _delayed(
      HomeData(
        date: DateTime.now(),
        pilotLevel: pilotLevel,
        recommendedSite: sites.isEmpty ? null : sites.first,
        sites: sites,
        notices: _noticeMaps.map(NoticeItem.fromJson).toList(),
      ),
    );
  }

  @override
  Future<List<SiteSummary>> getSites({
    required PilotLevel pilotLevel,
    String query = '',
  }) async {
    final lower = query.trim().toLowerCase();
    final list = _siteMaps
        .where((item) {
          if (lower.isEmpty) {
            return true;
          }
          return (item['name'] as String).toLowerCase().contains(lower) ||
              (item['region'] as String).toLowerCase().contains(lower);
        })
        .map(SiteSummary.fromJson)
        .toList();
    return _delayed(list);
  }

  @override
  Future<SiteDetail> getSiteDetail({
    required int siteId,
    required PilotLevel pilotLevel,
  }) async {
    final json = _siteMaps.firstWhere((item) => item['id'] == siteId);
    return _delayed(SiteDetail.fromJson(json));
  }

  @override
  Future<List<TrainingLog>> getTrainingLogs({required int userId}) async {
    final list = _trainingLogMaps
        .where((item) => item['user_id'] == userId)
        .map(TrainingLog.fromJson)
        .toList()
      ..sort((a, b) => b.trainingDate.compareTo(a.trainingDate));
    return _delayed(list);
  }

  @override
  Future<TrainingLog> createTrainingLog(TrainingLogDraft draft) async {
    final nextId =
        _trainingLogMaps.isEmpty ? 1 : (_trainingLogMaps.last['id'] as int) + 1;
    final site = _siteMaps.firstWhere((item) => item['id'] == draft.siteId);
    final json = {
      'id': nextId,
      'user_id': draft.userId,
      'site_id': draft.siteId,
      'site_name': site['name'],
      'training_date': formatDate(draft.trainingDate),
      'training_type': draft.trainingType,
      'participated': draft.participated,
      'flight_success': draft.flightSuccess,
      'difficulty': draft.difficulty,
      'memo': draft.memo,
      'created_at': DateTime.now().toIso8601String(),
    };
    _trainingLogMaps.add(json);
    return _delayed(TrainingLog.fromJson(json));
  }

  @override
  Future<List<NoticeItem>> getNotices() async {
    return _delayed(_noticeMaps.map(NoticeItem.fromJson).toList());
  }

  @override
  Future<NoticeItem> getNoticeDetail({required int noticeId}) async {
    final json = _noticeMaps.firstWhere((item) => item['id'] == noticeId);
    return _delayed(NoticeItem.fromJson(json));
  }
}
