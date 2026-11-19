// Courbe de volume. Fichier identique dans les dépôts bureau et mobile.
import 'dart:math' as math;

/// Gain d'OMNIA à 200 %, en décibels : +10 dB, ce que l'oreille entend comme
/// un son deux fois plus fort.
const double boostDecibelsAt200 = 10;

/// Le volume à confier à mpv pour le pourcentage [percent] d'OMNIA.
///
/// mpv applique une courbe cubique : son gain vaut (volume / 100)³. Jusqu'à
/// 100 %, on la garde — c'est elle qui rend les petits volumes fins. Au-delà,
/// la suivre faisait de « 200 % » un gain de 8 (+18 dB) : n'importe quel son
/// normal écrêtait, et la qualité s'effondrait. OMNIA vise un gain mesuré,
/// qui monte régulièrement jusqu'à +10 dB à 200 % (CHANTIERS R.5).
double mpvVolumeFor(double percent) {
  if (percent <= 100) return percent;
  final decibels = (percent - 100) / 100 * boostDecibelsAt200;
  final amplitude = math.pow(10, decibels / 20).toDouble();
  return 100 * math.pow(amplitude, 1 / 3).toDouble();
}

/// L'inverse : le pourcentage d'OMNIA que représente le volume [mpv] de mpv,
/// arrondi au demi-point (le moteur rend des décimales sans intérêt).
double percentForMpvVolume(double mpv) {
  if (mpv <= 100) return mpv;
  final amplitude = math.pow(mpv / 100, 3).toDouble();
  final decibels = 20 * math.log(amplitude) / math.ln10;
  final percent = 100 + decibels / boostDecibelsAt200 * 100;
  return (percent * 2).round() / 2;
}
