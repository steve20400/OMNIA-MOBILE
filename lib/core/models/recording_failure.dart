/// Raison pour laquelle le dernier extrait n'a pas été enregistré.
///
/// L'échec seul ne suffit pas à l'utilisateur : « rien n'a été écrit » et
/// « le dossier est inaccessible » n'appellent pas le même geste. La raison
/// voyage dans [PlaybackState], donc aussi vers la future télécommande.
enum RecordingFailure {
  /// Aucun échec : le dernier extrait s'est bien passé (ou il n'y en a pas eu).
  none,

  /// Ce média ne sait pas être enregistré : document, ou contrôleur sans
  /// enregistreur de flux.
  unsupportedMedia,

  /// Rien ne défile (pause, fin de fichier, ouverture en cours) : un extrait
  /// suit la lecture, et n'aurait aucun contenu.
  notPlaying,

  /// Dossier de destination inaccessible (droits, disque retiré).
  folderUnavailable,

  /// Le moteur a refusé de commencer : propriété d'enregistrement absente de
  /// cette version de mpv, ou moteur déjà libéré.
  engineRefused,

  /// Arrêt sans rien à garder : le moteur n'a écrit aucun paquet, et son cache
  /// n'a rien donné non plus (format que le conteneur Matroska refuse,
  /// enregistrement trop court).
  nothingRecorded;

  /// Désérialisation tolérante : une valeur inconnue devient [none].
  static RecordingFailure fromJson(Object? value) => values.firstWhere(
        (e) => e.name == value,
        orElse: () => RecordingFailure.none,
      );
}
