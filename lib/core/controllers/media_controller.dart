import '../commands/player_command.dart';
import '../models/media_file.dart';
import '../models/media_type.dart';
import '../models/playback_state.dart';

/// Point d'écriture de l'état de lecture, fourni à chaque contrôleur.
///
/// Les contrôleurs ne possèdent pas l'état : ils le font évoluer par
/// réductions pures. Cela garde un seul [PlaybackState] pour toute l'app et
/// rend les contrôleurs testables avec un faux puits.
abstract interface class PlaybackStateSink {
  PlaybackState get state;

  /// Applique [reducer] à l'état courant et notifie les observateurs.
  void update(PlaybackState Function(PlaybackState current) reducer);
}

/// Interface commune à tous les contrôleurs de média.
///
/// Un contrôleur sait ouvrir certains [MediaType], réagit aux commandes qui le
/// concernent et publie ses changements via le [PlaybackStateSink] reçu à
/// l'ouverture. Le [MediaRouter] choisit le contrôleur adapté à chaque fichier.
abstract interface class MediaController {
  /// Types de média que ce contrôleur sait ouvrir.
  Set<MediaType> get supportedTypes;

  /// Ouvre [file] et commence la lecture (ou l'affichage).
  ///
  /// Ne lève jamais : toute erreur est reportée dans l'état
  /// (`status = error`, `error = …`).
  Future<void> open(MediaFile file, PlaybackStateSink sink);

  /// Traite une commande. Retourne `true` si elle a été consommée.
  Future<bool> handle(PlayerCommand command);

  /// Ferme le fichier courant sans libérer le contrôleur.
  Future<void> close();

  /// Libère définitivement les ressources natives.
  Future<void> dispose();
}
