/// Transforme les événements de molette en crans.
///
/// Une molette classique donne un événement par cran ; une molette libre ou
/// haute résolution, et certains pavés tactiles, envoient une rafale de petits
/// déplacements. Sans regroupement, un seul geste ferait avancer la lecture
/// de plusieurs minutes. On additionne donc les déplacements jusqu'à un seuil,
/// et une pause remet le compte à zéro.
class WheelSteps {
  WheelSteps({this.threshold = 30, this.idleReset = const Duration(milliseconds: 300)});

  /// Déplacement cumulé, en pixels logiques, qui vaut un cran.
  final double threshold;

  /// Au-delà de cette pause, un déplacement partiel est oublié.
  final Duration idleReset;

  double _accumulated = 0;
  DateTime? _last;

  /// Ajoute un déplacement vertical ([dy] Flutter : négatif vers le haut).
  /// Retourne 1 pour un cran vers le haut, -1 vers le bas, 0 si le seuil
  /// n'est pas encore atteint.
  int add(double dy, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final last = _last;
    if (last != null && t.difference(last) > idleReset) _accumulated = 0;
    _last = t;
    _accumulated += dy;
    if (_accumulated.abs() < threshold) return 0;
    final step = _accumulated < 0 ? 1 : -1;
    _accumulated = 0;
    return step;
  }
}
