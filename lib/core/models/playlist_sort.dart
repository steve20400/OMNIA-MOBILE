/// Critère de tri du panneau de dossier.
enum PlaylistSort {
  /// Tri naturel sur le nom : `ep2` avant `ep10`. Valeur par défaut.
  name,

  /// Date de dernière modification.
  date,

  /// Taille du fichier.
  size,

  /// Type de média, puis nom.
  type;

  static PlaylistSort fromJson(Object? value) => values.firstWhere(
        (e) => e.name == value,
        orElse: () => PlaylistSort.name,
      );
}

/// Filtre par famille de média du panneau de dossier.
enum PlaylistFilter {
  all,
  video,
  audio,
  documents,
  images;

  static PlaylistFilter fromJson(Object? value) => values.firstWhere(
        (e) => e.name == value,
        orElse: () => PlaylistFilter.all,
      );
}

