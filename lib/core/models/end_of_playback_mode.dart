/// Comportement à la fin d'un fichier (mode de boucle).
///
/// Cyclé par la touche `L` et réglable dans les paramètres.
enum EndOfPlaybackMode {
  /// S'arrêter à la fin du fichier.
  stop,

  /// Passer au fichier suivant de la playlist (défaut).
  next,

  /// Répéter le fichier courant.
  repeatOne,

  /// Boucler sur tout le dossier.
  loopFolder,

  /// Lecture aléatoire dans le dossier.
  shuffle;

  /// Mode suivant dans le cycle (`L`).
  EndOfPlaybackMode get nextInCycle =>
      values[(index + 1) % values.length];

  /// Désérialisation tolérante : une valeur inconnue devient [next].
  static EndOfPlaybackMode fromJson(Object? value) => values.firstWhere(
        (e) => e.name == value,
        orElse: () => EndOfPlaybackMode.next,
      );
}
