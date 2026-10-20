import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/utils/connect_mode.dart';
import 'package:omnia_mobile/ui/theme/omnia_theme.dart';
import 'package:omnia_mobile/ui/widgets/connect_mode_notice.dart';

/// Le diagnostic ne sert à rien s'il ne monte pas à l'écran : les boutons de
/// mode étaient sans effet visible au clic, c'est cet encart qui y répond.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildOmniaTheme(Brightness.dark),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  testWidgets('un mode prêt montre l\'adresse à annoncer', (tester) async {
    await pump(
      tester,
      const ConnectModeNotice(
        report: ConnectModeReport(
          mode: ConnectMode.wifi,
          address: '192.168.1.42',
        ),
      ),
    );
    expect(find.text('Mode Wi-Fi local'), findsOneWidget);
    expect(find.textContaining('192.168.1.42'), findsOneWidget);
  });

  testWidgets('un prérequis manquant dit quoi faire, en français',
      (tester) async {
    final report = ConnectModeInspector.inspect(
      mode: ConnectMode.bluetooth,
      interfaces: const [],
    );
    await pump(tester, ConnectModeNotice(report: report));

    expect(find.text('Mode Bluetooth'), findsOneWidget);
    // Le constat **et** la marche à suivre, pas seulement « ça ne marche pas ».
    expect(find.textContaining('Aucun lien réseau Bluetooth'), findsOneWidget);
    expect(
      find.textContaining('partage de connexion par Bluetooth'),
      findsOneWidget,
    );
  });

  testWidgets('le contrôle en cours est annoncé sans animation sans fin',
      (tester) async {
    await pump(tester, const ConnectModeNotice(report: null, checking: true));
    expect(find.text('Vérification des prérequis…'), findsOneWidget);
    // Un indicateur de progression animé tourne indéfiniment : l'écran ne se
    // stabilise jamais, ni pour l'utilisateur ni pour `pumpAndSettle`.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('une sonde sans réponse finit par dire quoi faire',
      (tester) async {
    await pump(
      tester,
      ConnectModeNotice(
        report: ConnectModeInspector.unavailable(ConnectMode.hotspot),
      ),
    );
    expect(find.textContaining('cartes réseau'), findsOneWidget);
    expect(find.textContaining('relancez la vérification'), findsOneWidget);
  });

  testWidgets('sans contrôle lancé, l\'encart ne prend pas de place',
      (tester) async {
    await pump(tester, const ConnectModeNotice(report: null));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getSize(find.byType(ConnectModeNotice)).height, 0);
  });
}
