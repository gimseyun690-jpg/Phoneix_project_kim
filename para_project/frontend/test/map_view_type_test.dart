import 'package:flutter_test/flutter_test.dart';
import 'package:paragliding_mvp_frontend/core/map_view_type.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('지도 유형 기본값은 위성이다', () async {
    SharedPreferences.setMockInitialValues({});
    final store = MapViewPreferenceStore();

    final type = await store.load();

    expect(type, ParaglidingMapViewType.satellite);
  });

  test('선택한 지도 유형을 다시 불러온다', () async {
    SharedPreferences.setMockInitialValues({});
    final store = MapViewPreferenceStore();

    await store.save(ParaglidingMapViewType.standard);
    final type = await store.load();

    expect(type, ParaglidingMapViewType.standard);
  });
}
