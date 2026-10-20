import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/utils/qr_code.dart';

/// Rendu d'un QR code destiné à être lu par un appareil photo.
///
/// Le style cède ici devant la lisibilité machine : un QR code n'est pas un
/// ornement, c'est une mire optique. Trois libertés prises par la version
/// précédente suffisaient à rendre le code indéchiffrable même avec un
/// encodeur juste, et elles sont toutes reprises ici :
///
/// - **modules arrondis** : le coin arrondi casse les proportions 1:1:3:1:1
///   des motifs de recherche et sépare deux modules sombres voisins. Le
///   lecteur n'y retrouve plus les plages de même teinte qu'il mesure. Les
///   modules sont donc des carrés pleins.
/// - **modules à cheval sur les pixels** : une taille de module fractionnaire
///   fait baver l'anticrénelage d'un module sur l'autre et brouille la
///   frontière clair/sombre. La taille est donc arrondie à un nombre entier de
///   pixels physiques, l'anticrénelage coupé.
/// - **code inversé** : le dialogue d'appairage dessinait des modules clairs
///   sur fond sombre. ML Kit — le décodeur du téléphone — ne lit pas un code
///   inversé. La polarité est désormais imposée : sombre sur clair.
///
/// S'y ajoute la zone de silence, que la norme exige sur quatre modules : sans
/// elle le lecteur ne sait pas où s'arrête le code.
class OmniaQrPainter extends CustomPainter {
  OmniaQrPainter({
    required this.data,
    required this.primaryColor,
    required this.backgroundColor,
    this.devicePixelRatio = 1.0,
  });

  final String data;
  final Color primaryColor;
  final Color backgroundColor;

  /// Densité de l'écran, pour aligner les modules sur la grille physique.
  final double devicePixelRatio;

  /// Zone de silence imposée par la norme, en modules.
  static const int quietZoneModules = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final polarity = resolvePolarity(primaryColor, backgroundColor);

    // La zone de silence fait partie du code : tout le fond est clair.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = polarity.light
        ..isAntiAlias = false,
    );

    final QrCode code;
    try {
      code = QrCode.encode(data);
    } on ArgumentError {
      // Payload trop long : mieux vaut un cadre vide qu'une mire fausse que
      // l'utilisateur essaierait de scanner en vain.
      return;
    }

    final metrics = QrPaintMetrics.resolve(
      logicalSide: math.min(size.width, size.height),
      moduleCount: code.size,
      devicePixelRatio: devicePixelRatio,
    );

    final paint = Paint()
      ..color = polarity.dark
      ..isAntiAlias = false
      ..style = PaintingStyle.fill;

    for (var row = 0; row < code.size; row++) {
      for (var col = 0; col < code.size; col++) {
        if (!code.isDark(row, col)) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            metrics.originLogical + col * metrics.moduleLogical,
            metrics.originLogical + row * metrics.moduleLogical,
            metrics.moduleLogical,
            metrics.moduleLogical,
          ),
          paint,
        );
      }
    }
  }

  /// Impose la polarité d'un QR code lisible : modules sombres, fond clair.
  ///
  /// Les deux couleurs du thème sont triées par luminance plutôt que prises
  /// dans l'ordre reçu, et remplacées par du noir sur blanc quand leur
  /// contraste tombe sous le seuil où un appareil photo décroche.
  static ({Color dark, Color light}) resolvePolarity(Color a, Color b) {
    final la = _relativeLuminance(a);
    final lb = _relativeLuminance(b);
    final dark = la <= lb ? a : b;
    final light = la <= lb ? b : a;

    final lighter = math.max(la, lb);
    final darker = math.min(la, lb);
    final ratio = (lighter + 0.05) / (darker + 0.05);
    if (ratio < minContrastRatio) {
      return (dark: const Color(0xFF000000), light: const Color(0xFFFFFFFF));
    }
    return (dark: dark, light: light);
  }

  /// Contraste minimal accepté. En dessous, l'appareil photo confond les
  /// modules : on repasse au noir sur blanc plutôt que d'afficher une mire
  /// que personne ne pourra scanner.
  static const double minContrastRatio = 7.0;

  static double _relativeLuminance(Color color) {
    double channel(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  @override
  bool shouldRepaint(covariant OmniaQrPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.devicePixelRatio != devicePixelRatio;
  }
}

/// Géométrie de tracé d'une matrice QR, zone de silence comprise.
///
/// Isolée du tracé pour être vérifiable : c'est ici que se joue la netteté des
/// modules, donc la lisibilité du code par un appareil photo.
class QrPaintMetrics {
  const QrPaintMetrics({
    required this.modulePixels,
    required this.moduleLogical,
    required this.originLogical,
  });

  /// Côté d'un module en pixels physiques : un entier, jamais une fraction.
  final int modulePixels;

  /// Côté d'un module en pixels logiques, pour le tracé.
  final double moduleLogical;

  /// Décalage du premier module, zone de silence comprise, en pixels
  /// logiques. Aligné lui aussi sur la grille physique.
  final double originLogical;

  /// Répartit [logicalSide] entre la matrice et sa zone de silence.
  ///
  /// La taille de module est arrondie *vers le bas* à un nombre entier de
  /// pixels physiques : un module de 3,7 px se dessinerait à cheval sur la
  /// grille et l'anticrénelage le ferait baver sur son voisin, ce qui brouille
  /// la frontière clair/sombre dont vit le décodeur. Le reste de la place part
  /// dans la zone de silence, qui ne peut qu'y gagner.
  static QrPaintMetrics resolve({
    required double logicalSide,
    required int moduleCount,
    required double devicePixelRatio,
  }) {
    final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
    final total = moduleCount + 2 * OmniaQrPainter.quietZoneModules;
    final availablePixels = logicalSide * dpr;
    // Au moins un pixel par module : en deçà il n'y a plus de code, mais mieux
    // vaut une mire trop petite qu'une division par zéro.
    final modulePixels = math.max(1, (availablePixels / total).floor());
    final usedPixels = modulePixels * total;
    final quietPixels = OmniaQrPainter.quietZoneModules * modulePixels +
        ((availablePixels - usedPixels) / 2).floorToDouble();
    return QrPaintMetrics(
      modulePixels: modulePixels,
      moduleLogical: modulePixels / dpr,
      originLogical: quietPixels / dpr,
    );
  }
}

/// Widget affichant un QR code OMNIA Connect.
class OmniaQrCode extends StatelessWidget {
  const OmniaQrCode({
    super.key,
    required this.data,
    this.size = 200,
    required this.color,
    required this.backgroundColor,
  });

  final String data;
  final double size;
  final Color color;
  final Color backgroundColor;

  /// Côté à réserver pour que [data] se dessine avec au moins
  /// [minModulePixels] pixels physiques par module.
  ///
  /// Un QR code trop petit pour la densité de données qu'il porte est
  /// illisible même parfaitement encodé : le payload d'appairage, avec son
  /// jeton, demande une version élevée donc beaucoup de modules.
  static double recommendedSize(
    String data, {
    double minModulePixels = 4,
    double devicePixelRatio = 1.0,
    double maxSize = 320,
  }) {
    final version = QrCode.versionFor(utf8.encode(data).length);
    final moduleCount = 17 + 4 * (version ?? QrCode.maxVersion);
    final total = moduleCount + 2 * OmniaQrPainter.quietZoneModules;
    final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
    return math.min(maxSize, total * minModulePixels / dpr);
  }

  @override
  Widget build(BuildContext context) {
    // Le fond du cadre reprend la couleur claire du code : la zone de silence
    // se prolonge ainsi jusqu'au bord, au lieu de buter sur une bordure
    // sombre que le lecteur prendrait pour un module.
    final polarity = OmniaQrPainter.resolvePolarity(color, backgroundColor);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: polarity.light,
        borderRadius: BorderRadius.circular(16),
      ),
      child: CustomPaint(
        size: Size(size, size),
        isComplex: true,
        willChange: false,
        painter: OmniaQrPainter(
          data: data,
          primaryColor: color,
          backgroundColor: backgroundColor,
          devicePixelRatio: dpr,
        ),
      ),
    );
  }
}
