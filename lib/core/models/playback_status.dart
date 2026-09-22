/// Statut courant du lecteur.
enum PlaybackStatus {
  /// Aucun fichier ouvert.
  idle,

  /// Ouverture en cours.
  loading,

  /// Lecture en cours (ou document affiché).
  playing,

  /// En pause.
  paused,

  /// Fin du fichier atteinte.
  ended,

  /// Erreur : voir [PlaybackError].
  error;

  static PlaybackStatus fromJson(Object? value) => values.firstWhere(
        (e) => e.name == value,
        orElse: () => PlaybackStatus.idle,
      );
}

/// Code d'erreur de lecture. L'interface le traduit en message lisible.
enum PlaybackErrorCode {
  fileNotFound,
  unsupportedFormat,
  decodeFailed,
  permissionDenied,

  /// Dossier ouvert mais ne contenant aucun fichier lisible.
  emptyFolder,

  /// Document protégé par un mot de passe.
  protectedDocument,
  unknown;

  static PlaybackErrorCode fromJson(Object? value) => values.firstWhere(
        (e) => e.name == value,
        orElse: () => PlaybackErrorCode.unknown,
      );
}

/// Erreur de lecture : un code stable + un détail technique optionnel.
class PlaybackError {
  const PlaybackError(this.code, {this.detail});

  final PlaybackErrorCode code;

  /// Message brut du moteur (journalisation, jamais affiché tel quel).
  final String? detail;

  Map<String, Object?> toJson() => {
        'code': code.name,
        if (detail != null) 'detail': detail,
      };

  factory PlaybackError.fromJson(Map<String, Object?> json) => PlaybackError(
        PlaybackErrorCode.fromJson(json['code']),
        detail: json['detail'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is PlaybackError && other.code == code && other.detail == detail;

  @override
  int get hashCode => Object.hash(code, detail);

  @override
  String toString() => 'PlaybackError(${code.name}${detail == null ? '' : ': $detail'})';
}
