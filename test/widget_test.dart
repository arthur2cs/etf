import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:etf_reminder/screens/home_screen.dart';
import 'package:etf_reminder/services/portfolio_repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Home page shows the Google sign-in CTA when signed out', (WidgetTester tester) async {
    // Pumping HomeScreen directly (instead of the full app) avoids exercising
    // google_sign_in / flutter_local_notifications platform channels, which
    // aren't available in the widget test environment.
    final repository = PortfolioRepository();

    await tester.pumpWidget(MaterialApp(home: HomeScreen(repository: repository)));
    await tester.pump();

    expect(find.text('Suivi PEA'), findsOneWidget);
    expect(find.text('Se connecter avec Google'), findsOneWidget);
  });
}
