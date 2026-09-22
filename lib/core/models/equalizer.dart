/// Égaliseur 10 bandes, appliqué par le filtre audio `equalizer` de FFmpeg
/// via mpv (`af=lavfi=[equalizer=…]`).
abstract final class Equalizer {
  /// Fréquences centrales des dix bandes, en hertz.
  static const List<int> bands = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

  /// Gain minimal et maximal par bande, en décibels.
  static const double minGain = -12;
  static const double maxGain = 12;

  static const List<double> flat = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

  /// Préréglages, gains en dB par bande, dans l'ordre de [bands].
  static const Map<String, List<double>> presets = {
    'normal': flat,
    'rock': [5, 4, 3, 1, -1, -1, 1, 3, 4, 5],
    'pop': [-1, 1, 3, 4, 3, 1, -1, -2, -2, -1],
    'jazz': [4, 3, 1, 2, -2, -2, 0, 1, 3, 4],
    'classical': [4, 3, 2, 1, -1, -1, 0, 2, 3, 4],
    'bass': [7, 6, 5, 3, 1, 0, 0, 0, 0, 0],
    'treble': [0, 0, 0, 0, 0, 1, 3, 5, 6, 7],
    'vocal': [-2, -3, -2, 1, 4, 4, 3, 1, 0, -1],
    'electronic': [5, 4, 1, 0, -2, 2, 1, 1, 4, 5],
    'acoustic': [4, 3, 2, 1, 2, 2, 3, 3, 3, 2],
  };

  /// Nom du préréglage correspondant exactement à [gains], ou `null`.
  static String? presetFor(List<double> gains) {
    for (final entry in presets.entries) {
      if (_same(entry.value, gains)) return entry.key;
    }
    return null;
  }

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.01) return false;
    }
    return true;
  }

  /// Borne et complète une liste de gains à dix valeurs.
  static List<double> normalise(List<double> gains) => List<double>.generate(
        bands.length,
        (i) => (i < gains.length ? gains[i] : 0.0).clamp(minGain, maxGain),
      );

  /// Chaîne de filtre mpv pour [gains] ; vide si tout est à zéro (aucun
  /// filtre : le son ne passe par aucun traitement).
  ///
  /// Un filtre `equalizer` par bande, largeur d'une octave (`t=o:w=1`), ce
  /// que FFmpeg recommande pour un égaliseur graphique.
  static String filterFor(List<double> gains) {
    final g = normalise(gains);
    if (g.every((v) => v == 0)) return '';
    final parts = <String>[];
    for (var i = 0; i < bands.length; i++) {
      parts.add('equalizer=f=${bands[i]}:t=o:w=1:g=${g[i].toStringAsFixed(1)}');
    }
    return 'lavfi=[${parts.join(',')}]';
  }
}
