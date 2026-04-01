enum PilotLevel { beginner, intermediate, advanced }

extension PilotLevelLabel on PilotLevel {
  String get value => switch (this) {
        PilotLevel.beginner => 'beginner',
        PilotLevel.intermediate => 'intermediate',
        PilotLevel.advanced => 'advanced',
      };

  String get label => switch (this) {
        PilotLevel.beginner => '초급',
        PilotLevel.intermediate => '중급',
        PilotLevel.advanced => '숙련',
      };

  static PilotLevel fromString(String value) => PilotLevel.values.firstWhere(
        (item) => item.value == value,
        orElse: () => PilotLevel.beginner,
      );
}

enum FlightStatus { good, caution, bad }

extension FlightStatusLabel on FlightStatus {
  String get value => switch (this) {
        FlightStatus.good => 'good',
        FlightStatus.caution => 'caution',
        FlightStatus.bad => 'bad',
      };

  String get label => switch (this) {
        FlightStatus.good => '좋음',
        FlightStatus.caution => '주의',
        FlightStatus.bad => '비추천',
      };

  static FlightStatus fromString(String value) =>
      FlightStatus.values.firstWhere(
        (item) => item.value == value,
        orElse: () => FlightStatus.caution,
      );
}

extension SiteDifficultyLabel on String {
  String get siteDifficultyLabel => switch (this) {
        'beginner' => '초급',
        'intermediate' => '중급',
        'advanced' => '숙련',
        _ => this,
      };
}

extension TrainingDifficultyLabel on String {
  String get trainingDifficultyLabel => switch (this) {
        'easy' => '쉬움',
        'medium' => '보통',
        'hard' => '어려움',
        _ => this,
      };
}

extension NoticeCategoryLabel on String {
  String get noticeCategoryLabel => switch (this) {
        'club' => '클럽',
        'training' => '훈련',
        'safety' => '안전',
        'weather' => '기상',
        _ => this,
      };
}

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.pilotLevel,
    required this.isAdmin,
  });

  final int id;
  final String email;
  final String fullName;
  final PilotLevel pilotLevel;
  final bool isAdmin;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as int,
        email: json['email'] as String,
        fullName: json['full_name'] as String,
        pilotLevel: PilotLevelLabel.fromString(json['pilot_level'] as String),
        isAdmin: json['is_admin'] as bool,
      );
}

class Assessment {
  const Assessment({
    required this.score,
    required this.status,
    required this.reasons,
    required this.summaryText,
  });

  final int score;
  final FlightStatus status;
  final List<String> reasons;
  final String summaryText;

  factory Assessment.fromJson(Map<String, dynamic> json) => Assessment(
        score: json['score'] as int,
        status: FlightStatusLabel.fromString(json['status'] as String),
        reasons: List<String>.from(json['reasons'] as List<dynamic>),
        summaryText: json['summary_text'] as String,
      );
}

class HourlyForecast {
  const HourlyForecast({
    required this.timeLabel,
    required this.averageWindSpeed,
    required this.windDirection,
    required this.gustSpeed,
    this.precipitationMm,
  });

  final String timeLabel;
  final double averageWindSpeed;
  final int windDirection;
  final double gustSpeed;
  final double? precipitationMm;

  factory HourlyForecast.fromJson(Map<String, dynamic> json) => HourlyForecast(
        timeLabel: json['time_label'] as String,
        averageWindSpeed: (json['average_wind_speed'] as num).toDouble(),
        windDirection: json['wind_direction'] as int,
        gustSpeed: (json['gust_speed'] as num).toDouble(),
        precipitationMm: (json['precipitation_mm'] as num?)?.toDouble(),
      );
}

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.observedAt,
    required this.averageWindSpeed,
    required this.windDirection,
    required this.gustSpeed,
    required this.summary,
    required this.hourlyForecast,
    this.precipitationMm,
  });

  final DateTime observedAt;
  final double averageWindSpeed;
  final int windDirection;
  final double gustSpeed;
  final double? precipitationMm;
  final String summary;
  final List<HourlyForecast> hourlyForecast;

  factory WeatherSnapshot.fromJson(Map<String, dynamic> json) =>
      WeatherSnapshot(
        observedAt: DateTime.parse(json['observed_at'] as String).toLocal(),
        averageWindSpeed: (json['average_wind_speed'] as num).toDouble(),
        windDirection: json['wind_direction'] as int,
        gustSpeed: (json['gust_speed'] as num).toDouble(),
        precipitationMm: (json['precipitation_mm'] as num?)?.toDouble(),
        summary: json['summary'] as String,
        hourlyForecast: (json['hourly_forecast'] as List<dynamic>)
            .map(
                (item) => HourlyForecast.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class SiteRule {
  const SiteRule({
    required this.notes,
    required this.allowedDirectionStart,
    required this.allowedDirectionEnd,
    required this.beginnerAllowed,
    required this.maxGust,
    required this.maxGustDifference,
  });

  final String notes;
  final int allowedDirectionStart;
  final int allowedDirectionEnd;
  final bool beginnerAllowed;
  final double maxGust;
  final double maxGustDifference;

  factory SiteRule.fromJson(Map<String, dynamic> json) => SiteRule(
        notes: json['notes'] as String,
        allowedDirectionStart: json['allowed_direction_start'] as int,
        allowedDirectionEnd: json['allowed_direction_end'] as int,
        beginnerAllowed: json['beginner_allowed'] as bool,
        maxGust: (json['max_gust'] as num).toDouble(),
        maxGustDifference: (json['max_gust_difference'] as num).toDouble(),
      );
}

class SiteSummary {
  const SiteSummary({
    required this.id,
    required this.name,
    required this.region,
    required this.difficulty,
    required this.shortDescription,
    required this.beginnerAllowed,
    required this.weather,
    required this.assessment,
  });

  final int id;
  final String name;
  final String region;
  final String difficulty;
  final String shortDescription;
  final bool beginnerAllowed;
  final WeatherSnapshot weather;
  final Assessment assessment;

  factory SiteSummary.fromJson(Map<String, dynamic> json) => SiteSummary(
        id: json['id'] as int,
        name: json['name'] as String,
        region: json['region'] as String,
        difficulty: json['difficulty'] as String,
        shortDescription: json['short_description'] as String,
        beginnerAllowed: json['beginner_allowed'] as bool,
        weather:
            WeatherSnapshot.fromJson(json['weather'] as Map<String, dynamic>),
        assessment:
            Assessment.fromJson(json['assessment'] as Map<String, dynamic>),
      );
}

class SiteDetail {
  const SiteDetail({
    required this.site,
    required this.description,
    required this.takeoffAltitudeM,
    required this.landingAltitudeM,
    required this.allowedDirectionRange,
    required this.rule,
  });

  final SiteSummary site;
  final String description;
  final int takeoffAltitudeM;
  final int landingAltitudeM;
  final String allowedDirectionRange;
  final SiteRule rule;

  factory SiteDetail.fromJson(Map<String, dynamic> json) => SiteDetail(
        site: SiteSummary.fromJson(json),
        description: json['description'] as String,
        takeoffAltitudeM: json['takeoff_altitude_m'] as int,
        landingAltitudeM: json['landing_altitude_m'] as int,
        allowedDirectionRange: json['allowed_direction_range'] as String,
        rule: SiteRule.fromJson(json['rule'] as Map<String, dynamic>),
      );
}

class TrainingLog {
  const TrainingLog({
    required this.id,
    required this.userId,
    required this.siteId,
    required this.siteName,
    required this.trainingDate,
    required this.trainingType,
    required this.participated,
    required this.flightSuccess,
    required this.difficulty,
    required this.memo,
    required this.createdAt,
  });

  final int id;
  final int userId;
  final int siteId;
  final String siteName;
  final DateTime trainingDate;
  final String trainingType;
  final bool participated;
  final bool flightSuccess;
  final String difficulty;
  final String memo;
  final DateTime createdAt;

  factory TrainingLog.fromJson(Map<String, dynamic> json) => TrainingLog(
        id: json['id'] as int,
        userId: json['user_id'] as int,
        siteId: json['site_id'] as int,
        siteName: json['site_name'] as String,
        trainingDate: DateTime.parse(json['training_date'] as String),
        trainingType: json['training_type'] as String,
        participated: json['participated'] as bool,
        flightSuccess: json['flight_success'] as bool,
        difficulty: json['difficulty'] as String,
        memo: json['memo'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class TrainingLogDraft {
  const TrainingLogDraft({
    required this.userId,
    required this.siteId,
    required this.trainingDate,
    required this.trainingType,
    required this.participated,
    required this.flightSuccess,
    required this.difficulty,
    required this.memo,
  });

  final int userId;
  final int siteId;
  final DateTime trainingDate;
  final String trainingType;
  final bool participated;
  final bool flightSuccess;
  final String difficulty;
  final String memo;

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'site_id': siteId,
        'training_date': trainingDate.toIso8601String().split('T').first,
        'training_type': trainingType,
        'participated': participated,
        'flight_success': flightSuccess,
        'difficulty': difficulty,
        'memo': memo,
      };
}

class NoticeItem {
  const NoticeItem({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.isPinned,
    required this.publishedAt,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String title;
  final String body;
  final String category;
  final bool isPinned;
  final DateTime publishedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory NoticeItem.fromJson(Map<String, dynamic> json) => NoticeItem(
        id: json['id'] as int,
        title: json['title'] as String,
        body: json['body'] as String,
        category: json['category'] as String,
        isPinned: json['is_pinned'] as bool,
        publishedAt: DateTime.parse(json['published_at'] as String),
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
        updatedAt: json['updated_at'] == null
            ? null
            : DateTime.parse(json['updated_at'] as String),
      );
}

enum FlightSessionStatus { recording, paused, completed }

extension FlightSessionStatusLabel on FlightSessionStatus {
  String get value => switch (this) {
        FlightSessionStatus.recording => 'recording',
        FlightSessionStatus.paused => 'paused',
        FlightSessionStatus.completed => 'completed',
      };

  String get label => switch (this) {
        FlightSessionStatus.recording => '기록 중',
        FlightSessionStatus.paused => '일시정지',
        FlightSessionStatus.completed => '저장 완료',
      };

  static FlightSessionStatus fromString(String value) =>
      FlightSessionStatus.values.firstWhere(
        (item) => item.value == value,
        orElse: () => FlightSessionStatus.completed,
      );
}

class FlightTrackPoint {
  const FlightTrackPoint({
    required this.id,
    required this.sessionId,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    this.speed,
    this.heading,
    this.accuracy,
  });

  final String id;
  final String sessionId;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double altitude;
  final double? speed;
  final double? heading;
  final double? accuracy;

  factory FlightTrackPoint.fromJson(Map<String, dynamic> json) =>
      FlightTrackPoint(
        id: json['id'] as String,
        sessionId: json['session_id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        altitude: (json['altitude'] as num).toDouble(),
        speed: (json['speed'] as num?)?.toDouble(),
        heading: (json['heading'] as num?)?.toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'session_id': sessionId,
        'timestamp': timestamp.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'speed': speed,
        'heading': heading,
        'accuracy': accuracy,
      };
}

class FlightSession {
  static const Object _unset = Object();

  const FlightSession({
    required this.id,
    required this.userId,
    required this.startedAt,
    required this.status,
    required this.durationSeconds,
    required this.totalDistanceMeters,
    required this.minAltitudeMeters,
    required this.maxAltitudeMeters,
    required this.avgSpeedMps,
    required this.maxSpeedMps,
    required this.trackPointCount,
    required this.pausedDurationSeconds,
    required this.createdAt,
    required this.updatedAt,
    this.endedAt,
    this.siteId,
    this.siteName = '',
    this.region = '',
    this.memo = '',
    this.pausedAt,
    this.lastLatitude,
    this.lastLongitude,
    this.lastAccuracyMeters,
  });

  final String id;
  final int userId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final FlightSessionStatus status;
  final int? siteId;
  final String siteName;
  final String region;
  final int durationSeconds;
  final double totalDistanceMeters;
  final double minAltitudeMeters;
  final double maxAltitudeMeters;
  final double avgSpeedMps;
  final double maxSpeedMps;
  final String memo;
  final int trackPointCount;
  final int pausedDurationSeconds;
  final DateTime? pausedAt;
  final double? lastLatitude;
  final double? lastLongitude;
  final double? lastAccuracyMeters;
  final DateTime createdAt;
  final DateTime updatedAt;

  Duration get duration => Duration(seconds: durationSeconds);

  bool get isRecording => status == FlightSessionStatus.recording;

  bool get isPaused => status == FlightSessionStatus.paused;

  String get displaySiteName => siteName.trim().isEmpty ? '사이트 미지정' : siteName;

  String get displayRegion => region.trim().isEmpty ? '지역 정보 없음' : region;

  FlightSession copyWith({
    String? id,
    int? userId,
    DateTime? startedAt,
    DateTime? endedAt,
    FlightSessionStatus? status,
    int? siteId,
    String? siteName,
    String? region,
    int? durationSeconds,
    double? totalDistanceMeters,
    double? minAltitudeMeters,
    double? maxAltitudeMeters,
    double? avgSpeedMps,
    double? maxSpeedMps,
    String? memo,
    int? trackPointCount,
    int? pausedDurationSeconds,
    Object? pausedAt = _unset,
    double? lastLatitude,
    double? lastLongitude,
    double? lastAccuracyMeters,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      FlightSession(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
        status: status ?? this.status,
        siteId: siteId ?? this.siteId,
        siteName: siteName ?? this.siteName,
        region: region ?? this.region,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        totalDistanceMeters: totalDistanceMeters ?? this.totalDistanceMeters,
        minAltitudeMeters: minAltitudeMeters ?? this.minAltitudeMeters,
        maxAltitudeMeters: maxAltitudeMeters ?? this.maxAltitudeMeters,
        avgSpeedMps: avgSpeedMps ?? this.avgSpeedMps,
        maxSpeedMps: maxSpeedMps ?? this.maxSpeedMps,
        memo: memo ?? this.memo,
        trackPointCount: trackPointCount ?? this.trackPointCount,
        pausedDurationSeconds:
            pausedDurationSeconds ?? this.pausedDurationSeconds,
        pausedAt:
            identical(pausedAt, _unset) ? this.pausedAt : pausedAt as DateTime?,
        lastLatitude: lastLatitude ?? this.lastLatitude,
        lastLongitude: lastLongitude ?? this.lastLongitude,
        lastAccuracyMeters: lastAccuracyMeters ?? this.lastAccuracyMeters,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory FlightSession.fromJson(Map<String, dynamic> json) => FlightSession(
        id: json['id'] as String,
        userId: json['user_id'] as int,
        startedAt: DateTime.parse(json['started_at'] as String),
        endedAt: json['ended_at'] == null
            ? null
            : DateTime.parse(json['ended_at'] as String),
        status: FlightSessionStatusLabel.fromString(json['status'] as String),
        siteId: json['site_id'] as int?,
        siteName: (json['site_name'] as String?) ?? '',
        region: (json['region'] as String?) ?? '',
        durationSeconds: json['duration_seconds'] as int,
        totalDistanceMeters: (json['total_distance_meters'] as num).toDouble(),
        minAltitudeMeters:
            (json['min_altitude_meters'] as num?)?.toDouble() ?? 0,
        maxAltitudeMeters:
            (json['max_altitude_meters'] as num?)?.toDouble() ?? 0,
        avgSpeedMps: (json['avg_speed_mps'] as num?)?.toDouble() ?? 0,
        maxSpeedMps: (json['max_speed_mps'] as num?)?.toDouble() ?? 0,
        memo: (json['memo'] as String?) ?? '',
        trackPointCount: (json['track_point_count'] as int?) ?? 0,
        pausedDurationSeconds: (json['paused_duration_seconds'] as int?) ?? 0,
        pausedAt: json['paused_at'] == null
            ? null
            : DateTime.parse(json['paused_at'] as String),
        lastLatitude: (json['last_latitude'] as num?)?.toDouble(),
        lastLongitude: (json['last_longitude'] as num?)?.toDouble(),
        lastAccuracyMeters: (json['last_accuracy_meters'] as num?)?.toDouble(),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt?.toIso8601String(),
        'status': status.value,
        'site_id': siteId,
        'site_name': siteName,
        'region': region,
        'duration_seconds': durationSeconds,
        'total_distance_meters': totalDistanceMeters,
        'min_altitude_meters': minAltitudeMeters,
        'max_altitude_meters': maxAltitudeMeters,
        'avg_speed_mps': avgSpeedMps,
        'max_speed_mps': maxSpeedMps,
        'memo': memo,
        'track_point_count': trackPointCount,
        'paused_duration_seconds': pausedDurationSeconds,
        'paused_at': pausedAt?.toIso8601String(),
        'last_latitude': lastLatitude,
        'last_longitude': lastLongitude,
        'last_accuracy_meters': lastAccuracyMeters,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

class FlightSessionDetail {
  const FlightSessionDetail({
    required this.session,
    required this.points,
  });

  final FlightSession session;
  final List<FlightTrackPoint> points;
}

class HomeData {
  const HomeData({
    required this.date,
    required this.pilotLevel,
    required this.recommendedSite,
    required this.sites,
    required this.notices,
  });

  final DateTime date;
  final PilotLevel pilotLevel;
  final SiteSummary? recommendedSite;
  final List<SiteSummary> sites;
  final List<NoticeItem> notices;

  factory HomeData.fromJson(Map<String, dynamic> json) => HomeData(
        date: DateTime.parse(json['date'] as String),
        pilotLevel: PilotLevelLabel.fromString(json['pilot_level'] as String),
        recommendedSite: json['recommended_site'] == null
            ? null
            : SiteSummary.fromJson(
                json['recommended_site'] as Map<String, dynamic>),
        sites: (json['sites'] as List<dynamic>)
            .map((item) => SiteSummary.fromJson(item as Map<String, dynamic>))
            .toList(),
        notices: (json['notices'] as List<dynamic>)
            .map((item) => NoticeItem.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

enum CommunityVisibility { public, siteOnly, private }

extension CommunityVisibilityLabel on CommunityVisibility {
  String get value => switch (this) {
        CommunityVisibility.public => 'public',
        CommunityVisibility.siteOnly => 'site_only',
        CommunityVisibility.private => 'private',
      };

  String get label => switch (this) {
        CommunityVisibility.public => '전체 공개',
        CommunityVisibility.siteOnly => '해당 이륙장 공개',
        CommunityVisibility.private => '나만 보기',
      };

  static CommunityVisibility fromString(String value) =>
      CommunityVisibility.values.firstWhere(
        (item) => item.value == value,
        orElse: () => CommunityVisibility.siteOnly,
      );
}

enum FlightJournalMediaType { image, video }

extension FlightJournalMediaTypeLabel on FlightJournalMediaType {
  String get value => switch (this) {
        FlightJournalMediaType.image => 'image',
        FlightJournalMediaType.video => 'video',
      };

  String get label => switch (this) {
        FlightJournalMediaType.image => '사진',
        FlightJournalMediaType.video => '동영상',
      };

  static FlightJournalMediaType fromString(String value) =>
      FlightJournalMediaType.values.firstWhere(
        (item) => item.value == value,
        orElse: () => FlightJournalMediaType.image,
      );
}

class FlightJournalMedia {
  const FlightJournalMedia({
    required this.id,
    required this.type,
    required this.localPath,
    required this.fileName,
    required this.createdAt,
  });

  final String id;
  final FlightJournalMediaType type;
  final String localPath;
  final String fileName;
  final DateTime createdAt;

  factory FlightJournalMedia.fromJson(Map<String, dynamic> json) =>
      FlightJournalMedia(
        id: json['id'] as String,
        type: FlightJournalMediaTypeLabel.fromString(json['type'] as String),
        localPath: json['local_path'] as String,
        fileName: json['file_name'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.value,
        'local_path': localPath,
        'file_name': fileName,
        'created_at': createdAt.toIso8601String(),
      };
}

class FlightJournalDraft {
  const FlightJournalDraft({
    required this.userId,
    required this.authorName,
    required this.siteName,
    required this.siteRegion,
    required this.title,
    required this.body,
    required this.questionText,
    required this.visibility,
    required this.flightDate,
    required this.durationSeconds,
    required this.totalDistanceMeters,
    required this.maxAltitudeMeters,
    required this.weatherSummary,
    required this.flyabilitySummary,
    required this.summaryText,
    required this.media,
    this.postId,
    this.flightSessionId,
    this.siteId,
    this.flightStartedAt,
    this.flightEndedAt,
  });

  final String? postId;
  final int userId;
  final String authorName;
  final String? flightSessionId;
  final int? siteId;
  final String siteName;
  final String siteRegion;
  final String title;
  final String body;
  final String questionText;
  final CommunityVisibility visibility;
  final DateTime flightDate;
  final DateTime? flightStartedAt;
  final DateTime? flightEndedAt;
  final int durationSeconds;
  final double totalDistanceMeters;
  final double maxAltitudeMeters;
  final String weatherSummary;
  final String flyabilitySummary;
  final String summaryText;
  final List<FlightJournalMedia> media;
}

class FlightJournalPost {
  static const Object _unset = Object();

  const FlightJournalPost({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.siteName,
    required this.siteRegion,
    required this.title,
    required this.body,
    required this.questionText,
    required this.visibility,
    required this.flightDate,
    required this.durationSeconds,
    required this.totalDistanceMeters,
    required this.maxAltitudeMeters,
    required this.weatherSummary,
    required this.flyabilitySummary,
    required this.summaryText,
    required this.likedUserIds,
    required this.commentCount,
    required this.media,
    required this.createdAt,
    required this.updatedAt,
    this.flightSessionId,
    this.siteId,
    this.flightStartedAt,
    this.flightEndedAt,
  });

  final String id;
  final int userId;
  final String authorName;
  final String? flightSessionId;
  final int? siteId;
  final String siteName;
  final String siteRegion;
  final String title;
  final String body;
  final String questionText;
  final CommunityVisibility visibility;
  final DateTime flightDate;
  final DateTime? flightStartedAt;
  final DateTime? flightEndedAt;
  final int durationSeconds;
  final double totalDistanceMeters;
  final double maxAltitudeMeters;
  final String weatherSummary;
  final String flyabilitySummary;
  final String summaryText;
  final List<int> likedUserIds;
  final int commentCount;
  final List<FlightJournalMedia> media;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get likeCount => likedUserIds.length;

  bool get hasQuestion => questionText.trim().isNotEmpty;

  bool get hasMedia => media.isNotEmpty;

  int get imageCount =>
      media.where((item) => item.type == FlightJournalMediaType.image).length;

  int get videoCount =>
      media.where((item) => item.type == FlightJournalMediaType.video).length;

  bool isLikedBy(int userId) => likedUserIds.contains(userId);

  FlightJournalPost copyWith({
    String? id,
    int? userId,
    String? authorName,
    Object? flightSessionId = _unset,
    Object? siteId = _unset,
    String? siteName,
    String? siteRegion,
    String? title,
    String? body,
    String? questionText,
    CommunityVisibility? visibility,
    DateTime? flightDate,
    Object? flightStartedAt = _unset,
    Object? flightEndedAt = _unset,
    int? durationSeconds,
    double? totalDistanceMeters,
    double? maxAltitudeMeters,
    String? weatherSummary,
    String? flyabilitySummary,
    String? summaryText,
    List<int>? likedUserIds,
    int? commentCount,
    List<FlightJournalMedia>? media,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      FlightJournalPost(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        authorName: authorName ?? this.authorName,
        flightSessionId: identical(flightSessionId, _unset)
            ? this.flightSessionId
            : flightSessionId as String?,
        siteId: identical(siteId, _unset) ? this.siteId : siteId as int?,
        siteName: siteName ?? this.siteName,
        siteRegion: siteRegion ?? this.siteRegion,
        title: title ?? this.title,
        body: body ?? this.body,
        questionText: questionText ?? this.questionText,
        visibility: visibility ?? this.visibility,
        flightDate: flightDate ?? this.flightDate,
        flightStartedAt: identical(flightStartedAt, _unset)
            ? this.flightStartedAt
            : flightStartedAt as DateTime?,
        flightEndedAt: identical(flightEndedAt, _unset)
            ? this.flightEndedAt
            : flightEndedAt as DateTime?,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        totalDistanceMeters: totalDistanceMeters ?? this.totalDistanceMeters,
        maxAltitudeMeters: maxAltitudeMeters ?? this.maxAltitudeMeters,
        weatherSummary: weatherSummary ?? this.weatherSummary,
        flyabilitySummary: flyabilitySummary ?? this.flyabilitySummary,
        summaryText: summaryText ?? this.summaryText,
        likedUserIds: likedUserIds ?? this.likedUserIds,
        commentCount: commentCount ?? this.commentCount,
        media: media ?? this.media,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory FlightJournalPost.fromJson(Map<String, dynamic> json) =>
      FlightJournalPost(
        id: json['id'] as String,
        userId: json['user_id'] as int,
        authorName: json['author_name'] as String,
        flightSessionId: json['flight_session_id'] as String?,
        siteId: json['site_id'] as int?,
        siteName: json['site_name'] as String? ?? '',
        siteRegion: json['site_region'] as String? ?? '',
        title: json['title'] as String,
        body: json['body'] as String? ?? '',
        questionText: json['question_text'] as String? ?? '',
        visibility:
            CommunityVisibilityLabel.fromString(json['visibility'] as String),
        flightDate: DateTime.parse(json['flight_date'] as String),
        flightStartedAt: json['flight_started_at'] == null
            ? null
            : DateTime.parse(json['flight_started_at'] as String),
        flightEndedAt: json['flight_ended_at'] == null
            ? null
            : DateTime.parse(json['flight_ended_at'] as String),
        durationSeconds: json['duration_seconds'] as int? ?? 0,
        totalDistanceMeters:
            (json['total_distance_meters'] as num?)?.toDouble() ?? 0,
        maxAltitudeMeters:
            (json['max_altitude_meters'] as num?)?.toDouble() ?? 0,
        weatherSummary: json['weather_summary'] as String? ?? '',
        flyabilitySummary: json['flyability_summary'] as String? ?? '',
        summaryText: json['summary_text'] as String? ?? '',
        likedUserIds: (json['liked_user_ids'] as List<dynamic>? ?? const [])
            .map((item) => item as int)
            .toList(growable: false),
        commentCount: json['comment_count'] as int? ?? 0,
        media: (json['media'] as List<dynamic>? ?? const [])
            .map((item) =>
                FlightJournalMedia.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'author_name': authorName,
        'flight_session_id': flightSessionId,
        'site_id': siteId,
        'site_name': siteName,
        'site_region': siteRegion,
        'title': title,
        'body': body,
        'question_text': questionText,
        'visibility': visibility.value,
        'flight_date': flightDate.toIso8601String(),
        'flight_started_at': flightStartedAt?.toIso8601String(),
        'flight_ended_at': flightEndedAt?.toIso8601String(),
        'duration_seconds': durationSeconds,
        'total_distance_meters': totalDistanceMeters,
        'max_altitude_meters': maxAltitudeMeters,
        'weather_summary': weatherSummary,
        'flyability_summary': flyabilitySummary,
        'summary_text': summaryText,
        'liked_user_ids': likedUserIds,
        'comment_count': commentCount,
        'media': media.map((item) => item.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

class PostComment {
  const PostComment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.authorName,
    required this.body,
    required this.createdAt,
    this.isFeedback = false,
  });

  final String id;
  final String postId;
  final int userId;
  final String authorName;
  final String body;
  final DateTime createdAt;
  final bool isFeedback;

  factory PostComment.fromJson(Map<String, dynamic> json) => PostComment(
        id: json['id'] as String,
        postId: json['post_id'] as String,
        userId: json['user_id'] as int,
        authorName: json['author_name'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        isFeedback: json['is_feedback'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'post_id': postId,
        'user_id': userId,
        'author_name': authorName,
        'body': body,
        'created_at': createdAt.toIso8601String(),
        'is_feedback': isFeedback,
      };
}
