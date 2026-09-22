/// Mode de défilement d'un document.
enum DocumentLayout {
  /// Pages à la suite, défilement continu (défaut).
  continuous,

  /// Une page à la fois.
  paged;

  DocumentLayout get other =>
      this == DocumentLayout.continuous ? DocumentLayout.paged : DocumentLayout.continuous;

  static DocumentLayout fromJson(Object? value) => values.firstWhere(
        (e) => e.name == value,
        orElse: () => DocumentLayout.continuous,
      );
}

/// Ajustement automatique du zoom d'un document.
enum FitMode {
  /// La page occupe toute la largeur disponible.
  width,

  /// La page entière tient dans la vue.
  page;

  static FitMode fromJson(Object? value) => values.firstWhere(
        (e) => e.name == value,
        orElse: () => FitMode.width,
      );
}
