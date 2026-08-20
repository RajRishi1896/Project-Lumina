import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:edumesh_android/main.dart';

void main() {
  testWidgets('App renders smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: LuminaApp(isLoggedIn: false),
      ),
    );
    expect(find.byType(LuminaApp), findsOneWidget);
  });
}
