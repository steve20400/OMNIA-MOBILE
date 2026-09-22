import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/l10n/app_localizations.dart';
import 'package:omnia_mobile/ui/theme/omnia_theme.dart';
import 'package:omnia_mobile/ui/widgets/omnia_connect_modal.dart';
import 'package:omnia_mobile/ui/widgets/omnia_qr_code.dart';

void main() {
  testWidgets('OmniaConnectModal renders QR code and connection status', (tester) async {
    const testPayload = '{"protocol":"omnia-connect","name":"Test Mobile","port":41530}';

    await tester.pumpWidget(
      MaterialApp(
        theme: buildOmniaTheme(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('fr'),
        home: const Scaffold(
          body: OmniaConnectModal(
            initialPairingData: testPayload,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Vérifie le titre
    expect(find.text('OMNIA Connect (Zero-Internet)'), findsOneWidget);

    // Vérifie le QR code
    expect(find.byType(OmniaQrCode), findsOneWidget);

    // Vérifie le bouton Fermer
    expect(find.text('Fermer'), findsOneWidget);
  });
}
