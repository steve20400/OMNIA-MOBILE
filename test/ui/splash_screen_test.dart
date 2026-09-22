import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/ui/screens/splash_screen.dart';
import 'package:omnia_mobile/ui/theme/omnia_theme.dart';

void main() {
  testWidgets('SplashScreen renders OMNIA branding, wordmark, and beam', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildOmniaTheme(Brightness.dark),
        home: const SplashScreen(
          duration: Duration(milliseconds: 1000),
          targetWidget: Scaffold(body: Text('TargetDestination')),
        ),
      ),
    );

    // Premier rendu : présence du titre OMNIA et du sous-titre
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('O M N I A'), findsOneWidget);
    expect(find.text('LECTEUR UNIVERSEL'), findsOneWidget);

    // Un tap permet de passer immédiatement à l'écran cible
    await tester.tap(find.byType(SplashScreen));
    await tester.pumpAndSettle();

    expect(find.text('TargetDestination'), findsOneWidget);
  });
}
