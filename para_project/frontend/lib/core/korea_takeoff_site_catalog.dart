class KoreaCuratedTakeoffSite {
  const KoreaCuratedTakeoffSite({
    required this.name,
    required this.regionHint,
    required this.statusText,
    this.windNote,
    this.isDomestic = true,
  });

  final String name;
  final String regionHint;
  final String statusText;
  final String? windNote;
  final bool isDomestic;
}

class KoreaTakeoffSiteCatalog {
  static List<KoreaCuratedTakeoffSite> search(String query) {
    final normalizedQuery = _normalize(query);
    return entries.where((item) {
      if (normalizedQuery.isEmpty) {
        return true;
      }
      return _normalize(item.name).contains(normalizedQuery) ||
          _normalize(item.regionHint).contains(normalizedQuery) ||
          _normalize(item.windNote ?? '').contains(normalizedQuery);
    }).toList();
  }

  static final List<KoreaCuratedTakeoffSite> entries = _buildEntries();

  static List<KoreaCuratedTakeoffSite> _buildEntries() {
    final seen = <String>{};
    final results = <KoreaCuratedTakeoffSite>[];

    for (final rawLine in _rawTakeoffSites.trim().split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      final parts = line.split('-');
      final rawName = parts.first.trim();
      final name = rawName.replaceAll(RegExp(r'\s+'), ' ');
      if (!seen.add(name)) {
        continue;
      }

      final note = parts.length > 1 ? parts.sublist(1).join('-').trim() : null;
      final isDomestic = !name.startsWith('대만 ');

      results.add(
        KoreaCuratedTakeoffSite(
          name: name,
          regionHint: _inferRegionHint(name, isDomestic),
          statusText: isDomestic ? '지도 좌표 보강 예정' : '해외 이륙장 보류',
          windNote: note == null || note.isEmpty ? null : note,
          isDomestic: isDomestic,
        ),
      );
    }

    return results;
  }

  static String _inferRegionHint(String name, bool isDomestic) {
    if (!isDomestic) {
      return '해외';
    }

    const prefixHints = <String, String>{
      '제주시 ': '제주 제주시',
      '연천군 ': '경기 연천',
      '안동 ': '경북 안동',
      '김해 ': '경남 김해',
      '정읍 ': '전북 정읍',
      '임실군 ': '전북 임실',
      '삼척 ': '강원 삼척',
      '태백 ': '강원 태백',
      '완도 ': '전남 완도',
      '영월 ': '강원 영월',
      '남양주 ': '경기 남양주',
      '구봉산대부도': '경기 안산 대부도',
      '대부도': '경기 안산 대부도',
      '문경활공랜드': '경북 문경',
    };

    for (final entry in prefixHints.entries) {
      if (name.startsWith(entry.key)) {
        return entry.value;
      }
    }

    return '지역 정보 보강 예정';
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }
}

const String _rawTakeoffSites = '''
자양산 이륙장
바람재 이륙장
한우산 이륙장
음달산 이륙장
대암산 이륙장
원정산 이륙장
대니산 이륙장
깃대봉 이륙장
월아산 이륙장
계룡산 이륙장
진례 이륙장
봉화산 이륙장
와룡산 이륙장
각산 이륙장
구제봉 이륙장
형제봉 이륙장
특리 이륙장
망실봉 이륙장
논개 이륙장
황금산 이륙장
문경 이륙장
오산 이륙장
경각산 이륙장
미륵산 이륙장
두산 이륙장
간월재 이륙장
주월산 이륙장
비봉산 이륙장
방광산 이륙장
사곡 이륙장
사곡 이륙장
사곡 이륙장
감악산 이륙장
식장산 이륙장
옥마봉 이륙장
무주 이륙장
향적봉 이륙장
매산리 이륙장
유명산 이륙장
정광산 이륙장
어섬 이륙장
대룡산 이륙장
괘방산 이륙장
흑성산 이륙장
곰돌이 이륙장
방장산 이륙장
장등산 이륙장
사자산 이륙장
월랑봉 이륙장
군산 이륙장
새별오름 이륙장
고근산 이륙장
금악오름 이륙장
황령산 이륙장
봉래산 이륙장
것대산 이륙장
불탄산 이륙장
장암산 이륙장
달마산 이륙장
마복산 이륙장
장암산 이륙장
도비산 이륙장
봉수대 이륙장
칠포 이륙장
오서산 이륙장
양백산 이륙장
백화산 이륙장
벽도산 이륙장
비학산 이륙장
국당 이륙장
화순 이륙장
노안 이륙장
오성산 이륙장
진천 이륙장
창평 이륙장
호락산 이륙장
오봉대 이륙장
덕기봉 이륙장
남산 이륙장
사명산 이륙장
기룡산 이륙장
대관령 이륙장
초록봉 이륙장
망운산 이륙장
제주시 서우봉 이륙장
서독산 이륙장
원적산 이륙장
송라산 이륙장
서운산 이륙장
가례비 이륙장
운천 이륙장
연천군 갈말 이륙장
봉화산 이륙장
금오산 이륙장
와우정사 이륙장
구봉산대부도 이륙장
동막골 이륙장
대부도연습장
대부도수련원 이륙장
남양주 패러연습장
은봉산 이륙장
혜음령 이륙장
광교산 이륙장
연화산 이륙장
송공산 이륙장
한우산 이륙장
금정산 이륙장
발례 이륙장
관모산 이륙장
광의 이륙장
마래산 이륙장 - 남풍
백월산 이륙장
난함산 이륙장
박달산 이륙장
왜목 이륙장
왕방산 이륙장
재석산 이륙장
흑성산 이륙장
예봉산 이륙장
딸각산 이륙장
문경활공랜드-서풍
미악산 이륙장
미시령 이륙장 - 동풍
대만 핑퉁 이륙장
주작산 이륙장
무릉이륙장
대만 이란이륙장 - 남서
남포 이륙장
안동 길안이륙장
김해 임호산이륙장
정읍 칠보산 이륙장
임실군 옥정호 나래산
삼척 용화 이륙장-동풍
태백 귀네미마을 이륙장-동풍
완도 신지이륙장-남서&서풍
영월 마추픽추 이륙장-남풍&북풍
무척산이륙장-서풍
신어산이륙장-서풍
단호활공장-동풍
음달서풍이륙장-서풍
''';
