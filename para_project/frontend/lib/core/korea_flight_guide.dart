import 'package:geolocator/geolocator.dart';

import '../models/app_models.dart';

enum KoreaZoneStatus {
  flyable,
  caution,
  confirmationRequired,
  potentiallyRestricted,
}

extension KoreaZoneStatusLabel on KoreaZoneStatus {
  String get label => switch (this) {
        KoreaZoneStatus.flyable => '비행 가능',
        KoreaZoneStatus.caution => '주의 구역',
        KoreaZoneStatus.confirmationRequired => '확인 필요',
        KoreaZoneStatus.potentiallyRestricted => '제한 가능성 있음',
      };
}

enum KoreaZoneConfidence {
  verified,
  curated,
  inferred,
}

extension KoreaZoneConfidenceLabel on KoreaZoneConfidence {
  String get label => switch (this) {
        KoreaZoneConfidence.verified => '명확한 구역 정보',
        KoreaZoneConfidence.curated => '등록된 비행장 기준 참고 정보',
        KoreaZoneConfidence.inferred => '현재는 참고용 추정 정보',
      };
}

class KoreaFlightSiteMetadata {
  const KoreaFlightSiteMetadata({
    required this.siteId,
    required this.name,
    required this.region,
    required this.latitude,
    required this.longitude,
    required this.flyableRadiusMeters,
    required this.cautionRadiusMeters,
    required this.note,
    required this.safetyText,
  });

  final int siteId;
  final String name;
  final String region;
  final double latitude;
  final double longitude;
  final double flyableRadiusMeters;
  final double cautionRadiusMeters;
  final String note;
  final String safetyText;
}

class KoreaZoneAdvisory {
  const KoreaZoneAdvisory({
    required this.status,
    required this.confidence,
    required this.title,
    required this.summary,
    required this.detail,
    required this.disclaimer,
    this.nearbySite,
    this.distanceMeters,
  });

  final KoreaZoneStatus status;
  final KoreaZoneConfidence confidence;
  final String title;
  final String summary;
  final String detail;
  final String disclaimer;
  final KoreaFlightSiteMetadata? nearbySite;
  final double? distanceMeters;
}

class KoreaFlightGuide {
  const KoreaFlightGuide();

  static const List<KoreaFlightSiteMetadata> siteMetadata = [
    KoreaFlightSiteMetadata(
      siteId: 1,
      name: '양평 패러밸리',
      region: '경기 양평',
      latitude: 37.5420,
      longitude: 127.5168,
      flyableRadiusMeters: 4500,
      cautionRadiusMeters: 9000,
      note: '양평 등록 비행장 반경 기준 참고 구역입니다.',
      safetyText: '수도권 인접 지역은 현장 브리핑과 당일 공지, 회수 동선을 함께 확인해 주세요.',
    ),
    KoreaFlightSiteMetadata(
      siteId: 2,
      name: '단양 리지포인트',
      region: '충북 단양',
      latitude: 36.9805,
      longitude: 128.3652,
      flyableRadiusMeters: 5000,
      cautionRadiusMeters: 11000,
      note: '단양 능선 비행권 참고 반경입니다.',
      safetyText: '계곡풍과 능선 바람 변화가 빠를 수 있으므로 풍향 변화와 회수 포인트를 함께 확인해 주세요.',
    ),
    KoreaFlightSiteMetadata(
      siteId: 3,
      name: '제주 오름릿지',
      region: '제주',
      latitude: 33.3618,
      longitude: 126.5292,
      flyableRadiusMeters: 4000,
      cautionRadiusMeters: 8500,
      note: '제주 오름 비행 참고 반경입니다.',
      safetyText: '해풍과 구름 생성 변화가 빠르므로 고도 확보와 착륙 대안을 보수적으로 잡는 것이 좋습니다.',
    ),
    KoreaFlightSiteMetadata(
      siteId: 4,
      name: '문경 활공랜드',
      region: '경북 문경',
      latitude: 36.5860,
      longitude: 128.1860,
      flyableRadiusMeters: 5000,
      cautionRadiusMeters: 10000,
      note: '문경 등록 비행장 반경 기준 참고 구역입니다.',
      safetyText: '산악 지형 특성상 국지 풍 변화가 있을 수 있어 이륙장 공지와 현장 브리핑을 함께 확인해 주세요.',
    ),
  ];

  KoreaFlightSiteMetadata? metadataForSite({
    int? siteId,
    String? siteName,
  }) {
    for (final item in siteMetadata) {
      if (siteId != null && item.siteId == siteId) {
        return item;
      }
      if (siteName != null && item.name == siteName) {
        return item;
      }
    }
    return null;
  }

  KoreaZoneAdvisory assess({
    required double latitude,
    required double longitude,
    SiteSummary? selectedSite,
    String? selectedSiteName,
  }) {
    final preferredSite = metadataForSite(
      siteId: selectedSite?.id,
      siteName: selectedSiteName,
    );
    final nearbySite = _findNearestSite(
      latitude: latitude,
      longitude: longitude,
      preferredSite: preferredSite,
    );

    if (nearbySite == null) {
      return const KoreaZoneAdvisory(
        status: KoreaZoneStatus.potentiallyRestricted,
        confidence: KoreaZoneConfidence.inferred,
        title: '현재 위치 기준 참고용 구역 상태',
        summary: '등록된 비행장 정보와 연결되지 않은 위치입니다.',
        detail:
            '현재 저장소에는 이 위치의 공식 공역 데이터가 없습니다. 등록된 비행장 반경 밖에서는 제한 가능성을 배제할 수 없으므로 현장 공지와 공역 정보를 추가 확인해 주세요.',
        disclaimer: '정확한 공역 정보는 추가 확인이 필요합니다.',
      );
    }

    final distanceMeters = Geolocator.distanceBetween(
      latitude,
      longitude,
      nearbySite.latitude,
      nearbySite.longitude,
    );

    if (distanceMeters <= nearbySite.flyableRadiusMeters) {
      return KoreaZoneAdvisory(
        status: KoreaZoneStatus.flyable,
        confidence: KoreaZoneConfidence.curated,
        title: '현재 위치 기준 참고용 구역 상태',
        summary: '${nearbySite.name} 기준 비행 가능 반경 안에 있습니다.',
        detail: '${nearbySite.note} ${nearbySite.safetyText}',
        disclaimer: '공식 허가를 보장하는 기능은 아니며, 현장 브리핑과 공역 공지를 함께 확인해 주세요.',
        nearbySite: nearbySite,
        distanceMeters: distanceMeters,
      );
    }

    if (distanceMeters <= nearbySite.cautionRadiusMeters) {
      return KoreaZoneAdvisory(
        status: KoreaZoneStatus.caution,
        confidence: KoreaZoneConfidence.curated,
        title: '현재 위치 기준 참고용 구역 상태',
        summary: '${nearbySite.name} 접근 구간으로 보입니다.',
        detail:
            '등록된 비행장 중심 반경 기준으로는 주의 구간입니다. 회수 동선, 착륙장 접근, 현장 통제 여부를 확인한 뒤 비행 판단을 이어가는 편이 안전합니다.',
        disclaimer: '정확한 공역 정보는 추가 확인이 필요합니다.',
        nearbySite: nearbySite,
        distanceMeters: distanceMeters,
      );
    }

    if (distanceMeters <= nearbySite.cautionRadiusMeters * 2) {
      return KoreaZoneAdvisory(
        status: KoreaZoneStatus.confirmationRequired,
        confidence: KoreaZoneConfidence.inferred,
        title: '현재 위치 기준 참고용 구역 상태',
        summary: '${nearbySite.name} 기준 참고 반경 밖입니다.',
        detail:
            '등록된 비행장과 어느 정도 가까운 위치지만 현재 저장소에는 공식 공역 경계가 없습니다. 현장 공지, 공역 지도, 회수 가능 여부를 꼭 함께 확인해 주세요.',
        disclaimer: '정확한 공역 정보는 추가 확인이 필요합니다.',
        nearbySite: nearbySite,
        distanceMeters: distanceMeters,
      );
    }

    return KoreaZoneAdvisory(
      status: KoreaZoneStatus.potentiallyRestricted,
      confidence: KoreaZoneConfidence.inferred,
      title: '현재 위치 기준 참고용 구역 상태',
      summary: '등록된 비행장 반경 밖의 위치입니다.',
      detail:
          '현재 위치는 등록된 한국 비행장 참고 반경과 충분히 떨어져 있습니다. 안전하게 비행 가능한 구역인지 확신할 수 없으므로 제한 가능성을 염두에 두고 추가 확인이 필요합니다.',
      disclaimer: '정확한 공역 정보는 추가 확인이 필요합니다.',
      nearbySite: nearbySite,
      distanceMeters: distanceMeters,
    );
  }

  KoreaFlightSiteMetadata? nearestSiteMetadata({
    required double latitude,
    required double longitude,
  }) {
    return _findNearestSite(
      latitude: latitude,
      longitude: longitude,
      preferredSite: null,
    );
  }

  KoreaFlightSiteMetadata? _findNearestSite({
    required double latitude,
    required double longitude,
    KoreaFlightSiteMetadata? preferredSite,
  }) {
    if (preferredSite != null) {
      return preferredSite;
    }

    KoreaFlightSiteMetadata? result;
    double? bestDistance;

    for (final item in siteMetadata) {
      final distance = Geolocator.distanceBetween(
        latitude,
        longitude,
        item.latitude,
        item.longitude,
      );
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        result = item;
      }
    }

    return result;
  }
}
