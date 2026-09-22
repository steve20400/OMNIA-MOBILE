import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/services/omnia_connect_service.dart';
import 'package:omnia_mobile/l10n/app_localizations.dart';
import 'package:omnia_mobile/ui/theme/omnia_theme.dart';
import 'package:omnia_mobile/ui/widgets/omnia_connect_modal.dart';
import 'package:omnia_mobile/ui/widgets/omnia_qr_code.dart';

void main() {
  testWidgets('OmniaConnectModal renders QR code and connection status', (tester) async {
    final service = OmniaConnectService(port: 0);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          omniaConnectServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
          theme: buildOmniaTheme(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('fr'),
          home: const Scaffold(
            body: OmniaConnectModal(),
          ),
        ),
      ),
    );

    // Initial pump
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Vérifie le titre
    expect(find.text('OMNIA Connect (Zero-Internet)'), findsOneWidget);

    // Vérifie le QR code
    expect(find.byType(OmniaQrCode), findsOneWidget);

    // Vérifie le bouton Fermer
    expect(find.text('Fermer'), findsOneWidget);

    await service.stop();
  });
}
