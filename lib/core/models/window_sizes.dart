import 'dart:math' as math;
import 'dart:ui';

/// Tailles de fenêtre d'OMNIA, en pixels logiques.
///
/// Source unique : `main.dart` ouvre la fenêtre avec ces valeurs, et
/// `PlaybackService` s'en sert pour dimensionner le mini-lecteur.
abstract final class WindowSizes {
  /// Fenêtre principale au premier lancement.
  static const Size mainDefault = Size(1200, 760);

  /// Plancher de la fenêtre principale : une vidéo tient encore dans un coin
  /// d'écran, avec ses commandes essentielles.
  static const Size mainMinimum = Size(360, 240);

  /// Mini-lecteur vidéo : grand côté par défaut, et plancher. L'autre côté
  /// suit le ratio de l'image.
  static const double miniDefaultLongSide = 400.0;
  static const double miniMinimumLongSide = 200.0;

  /// Mini-lecteur sans image (son seul, ou vidéo dont l'image n'est pas encore
  /// connue) : un bandeau de commandes.
  static const Size miniAudio = Size(400, 132);
  static const Size miniAudioMinimum = Size(300, 96);

  /// Mini-lecteur d'une image de ratio [aspect] (largeur / hauteur) :
  /// [longSide] sur le grand côté, [miniDefaultLongSide] par défaut, jamais
  /// moins de [miniMinimumLongSide].
  static Size miniVideoSize(double aspect, {double? longSide}) {
    // Un réglage illisible (NaN, infini) ne doit pas donner une fenêtre
    // sans taille : on revient au défaut.
    final side = longSide != null && longSide.isFinite ? longSide : miniDefaultLongSide;
    return _fit(aspect, math.max(side, miniMinimumLongSide));
  }

  /// Plancher du mini-lecteur d'une image de ratio [aspect].
  static Size miniVideoMinimum(double aspect) => _fit(aspect, miniMinimumLongSide);

  /// Paysage : la largeur porte le grand côté ; portrait : la hauteur. Un
  /// ratio inexploitable (nul, négatif, infini) donne un carré plutôt qu'une
  /// fenêtre de taille nulle.
  static Size _fit(double aspect, double longSide) {
    final ratio = aspect.isFinite && aspect > 0 ? aspect : 1.0;
    return ratio >= 1
        ? Size(longSide, longSide / ratio)
        : Size(longSide * ratio, longSide);
  }
}
