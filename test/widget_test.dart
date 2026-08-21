import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:etf_reminder/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Home page shows reminder settings', (WidgetTester tester) async {
    await tester.pumpWidget(const ETFReminderApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Rappel ETF'), findsOneWidget);
    expect(find.text('Activer le rappel'), findsOneWidget);
    expect(find.text('Enregistrer'), findsOneWidget);
  });
}
