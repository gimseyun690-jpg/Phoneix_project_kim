import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:paragliding_mvp_frontend/core/favorite_sites_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FavoriteSitesStore', () {
    late FavoriteSitesStore store;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      store = FavoriteSitesStore();
    });

    test('등록 비행장과 일반 이륙장을 즐겨찾기에 저장하고 해제한다', () async {
      var favorites =
          await store.toggle(const FavoriteSiteEntry.registered(12));
      expect(favorites, hasLength(1));
      expect(favorites.first.storageKey, 'registered:12');

      favorites =
          await store.toggle(const FavoriteSiteEntry.imported('takeoff_1'));
      expect(favorites, hasLength(2));
      expect(favorites.first.storageKey, 'imported:takeoff_1');

      favorites = await store.toggle(const FavoriteSiteEntry.registered(12));
      expect(favorites, hasLength(1));
      expect(favorites.first.storageKey, 'imported:takeoff_1');
    });
  });
}
