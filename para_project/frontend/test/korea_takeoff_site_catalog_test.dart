import 'package:flutter_test/flutter_test.dart';
import 'package:paragliding_mvp_frontend/core/korea_takeoff_site_catalog.dart';

void main() {
  group('KoreaTakeoffSiteCatalog', () {
    test('중복 이름을 제거한다', () {
      final names =
          KoreaTakeoffSiteCatalog.entries.map((item) => item.name).toList();
      final uniqueNames = names.toSet();

      expect(names.length, uniqueNames.length);
      expect(names.where((item) => item == '사곡 이륙장').length, 1);
      expect(names.where((item) => item == '장암산 이륙장').length, 1);
      expect(names.where((item) => item == '한우산 이륙장').length, 1);
    });

    test('해외 항목은 별도로 표시한다', () {
      final overseas = KoreaTakeoffSiteCatalog.entries
          .where((item) => !item.isDomestic)
          .map((item) => item.name)
          .toList();

      expect(overseas, contains('대만 핑퉁 이륙장'));
      expect(overseas, contains('대만 이란이륙장'));
    });
  });
}
