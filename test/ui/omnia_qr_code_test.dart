import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/ui/theme/omnia_colors.dart';
import 'package:omnia_mobile/ui/widgets/omnia_qr_code.dart';

/// Un QR code juste peut rester illisible à cause de son seul rendu. Ces tests
/// couvrent les quatre façons dont l'affichage tuait le code d'appairage :
/// polarité inversée, modules arrondis, modules à cheval sur les pixels
/// physiques, et zone de silence absente ou trop étroite.
void main() {
  group('Polarité : sombre sur clair, toujours', () {
    test('le code inversé du dialogue d\'appairage est remis à l\'endroit', () {
      // Le dialogue passait `color: colors.screen` (texte clair) sur
      // `backgroundColor: colors.velvet` (fond sombre) : des modules clairs
      // sur fond sombre. ML Kit, le décodeur du téléphone, ne lit pas un code
      // inversé — la caméra voyait le code sans jamais rien en tirer.
      final polarity = OmniaQrPainter.resolvePolarity(
        OmniaColors.dark.screen,
        OmniaColors.dark.velvet,
      );
      expect(polarity.dark, OmniaColors.dark.velvet);
      expect(polarity.light, OmniaColors.dark.screen);
    });

    test('l\'ordre des couleurs reçues n\'y change rien', () {
      final direct = OmniaQrPainter.resolvePolarity(
        OmniaColors.dark.velvet,
        Colors.white,
      );
      final reversed = OmniaQrPainter.resolvePolarity(
        Colors.white,
        OmniaColors.dark.velvet,
      );
      expect(direct.dark, reversed.dark);
      expect(direct.light, reversed.light);
    });

    test('un contraste insuffisant repasse au noir sur blanc', () {
      // Deux gris voisins : l'appareil photo ne sépare plus les modules. Mieux
      // vaut perdre la teinte du thème que la lisibilité.
      final polarity = OmniaQrPainter.resolvePolarity(
        const Color(0xFF555555),
        const Color(0xFF777777),
      );
      expect(polarity.dark, const Color(0xFF000000));
      expect(polarity.light, const Color(0xFFFFFFFF));
    });

    test('un contraste franc garde les couleurs du thème', () {
      final polarity = OmniaQrPainter.resolvePolarity(
        OmniaColors.dark.velvet,
        Colors.white,
      );
      expect(polarity.dark, OmniaColors.dark.velvet);
      expect(polarity.light, Colors.white);
    });
  });

  group('Géométrie : des modules entiers, une vraie zone de silence', () {
    test('la taille de module est un nombre entier de pixels physiques', () {
      // Une taille fractionnaire fait baver l'anticrénelage d'un module sur
      // l'autre : la frontière clair/sombre dont vit le décodeur disparaît.
      for (final dpr in [1.0, 1.25, 1.5, 2.0, 3.0]) {
        for (final side in [130.0, 200.0, 210.0, 263.0, 320.0]) {
          for (final modules in [21, 25, 33, 49, 57]) {
            final metrics = QrPaintMetrics.resolve(
              logicalSide: side,
              moduleCount: modules,
              devicePixelRatio: dpr,
            );
            expect(metrics.modulePixels, greaterThanOrEqualTo(1));
            expect(metrics.moduleLogical * dpr, closeTo(metrics.modulePixels, 1e-9),
                reason: 'module de ${metrics.modulePixels} px à dpr $dpr');
            // L'origine aussi tombe sur la grille physique, sinon le premier
            // module est décalé d'une fraction de pixel et bave à son tour.
            final originPixels = metrics.originLogical * dpr;
            expect(originPixels, closeTo(originPixels.roundToDouble(), 1e-9));
          }
        }
      }
    });

    test('la zone de silence fait au moins les quatre modules de la norme', () {
      for (final dpr in [1.0, 2.0]) {
        final metrics = QrPaintMetrics.resolve(
          logicalSide: 210,
          moduleCount: 49,
          devicePixelRatio: dpr,
        );
        expect(
          metrics.originLogical,
          greaterThanOrEqualTo(
            OmniaQrPainter.quietZoneModules * metrics.moduleLogical - 1e-9,
          ),
        );
      }
    });

    test('le code et sa zone de silence tiennent dans la place donnée', () {
      for (final modules in [21, 41, 57]) {
        const side = 200.0;
        const dpr = 2.0;
        final metrics = QrPaintMetrics.resolve(
          logicalSide: side,
          moduleCount: modules,
          devicePixelRatio: dpr,
        );
        final usedLogical =
            2 * metrics.originLogical + modules * metrics.moduleLogical;
        expect(usedLogical, lessThanOrEqualTo(side + 1e-9),
            reason: '$modules modules dans $side px');
      }
    });

    test('la taille conseillée suit la densité de données du payload', () {
      final court = OmniaQrCode.recommendedSize('omnia');
      final long = OmniaQrCode.recommendedSize('A' * 150);
      expect(long, greaterThan(court));
      // Et elle garantit bien le nombre de pixels par module demandé.
      final metrics = QrPaintMetrics.resolve(
        logicalSide: OmniaQrCode.recommendedSize('A' * 150, minModulePixels: 4),
        moduleCount: 49,
        devicePixelRatio: 1.0,
      );
      expect(metrics.modulePixels, greaterThanOrEqualTo(4));
    });
  });

  group('Tracé', () {
    testWidgets('les modules sont des carrés pleins, jamais arrondis',
        (tester) async {
      // Le coin arrondi casse les proportions 1:1:3:1:1 des motifs de
      // détection et sépare deux modules sombres voisins : le lecteur n'y
      // retrouve plus les plages de même teinte qu'il mesure.
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: OmniaQrCode(
              data: 'omnia-connect',
              size: 240,
              color: OmniaColors.dark.screen,
              backgroundColor: OmniaColors.dark.velvet,
            ),
          ),
        ),
      );

      final painted = find.descendant(
        of: find.byType(OmniaQrCode),
        matching: find.byType(CustomPaint),
      );
      expect(painted, findsOneWidget);
      expect(tester.widget(painted), isA<CustomPaint>());
      expect(painted, paintsExactlyCountTimes(#drawRRect, 0));
      // Le fond clair, plus un rectangle par module sombre de la matrice de
      // « omnia-connect » — 242, comptés sur la matrice de référence.
      expect(painted, paintsExactlyCountTimes(#drawRect, 243));
    });

    testWidgets('les modules sont peints dans la couleur sombre, pas la claire',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: OmniaQrCode(
              data: 'omnia-connect',
              size: 240,
              color: OmniaColors.dark.screen,
              backgroundColor: OmniaColors.dark.velvet,
            ),
          ),
        ),
      );

      final painted = find.descendant(
        of: find.byType(OmniaQrCode),
        matching: find.byType(CustomPaint),
      );
      expect(
        painted,
        paints
          ..rect(color: OmniaColors.dark.screen)
          ..rect(color: OmniaColors.dark.velvet),
      );
    });

    testWidgets('un payload trop long n\'affiche pas de fausse mire',
        (tester) async {
      // Mieux vaut un cadre vide qu'un dessin que l'utilisateur essaierait de
      // scanner en vain.
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: OmniaQrCode(
              data: 'A' * 500,
              size: 240,
              color: OmniaColors.dark.velvet,
              backgroundColor: Colors.white,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final painted = find.descendant(
        of: find.byType(OmniaQrCode),
        matching: find.byType(CustomPaint),
      );
      expect(painted, paintsExactlyCountTimes(#drawRect, 1));
    });
  });
}
