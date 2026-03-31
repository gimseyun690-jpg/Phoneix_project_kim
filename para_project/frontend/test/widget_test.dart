import 'package:flutter_test/flutter_test.dart';
import 'package:paragliding_mvp_frontend/app.dart';

void main() {
  testWidgets('login screen renders', (tester) async {
    await tester.pumpWidget(const ParaglidingApp());

    expect(find.text('패러글라이딩 브리핑'), findsOneWidget);
    expect(find.text('로그인'), findsOneWidget);
  });
}
