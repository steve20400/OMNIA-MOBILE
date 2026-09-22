import 'package:collection/collection.dart';

import '../../core/commands/player_command.dart';
import '../../core/commands/player_command_bus.dart';
import '../../core/models/end_of_playback_mode.dart';
import '../../core/models/playback_state.dart';
import '../../core/models/video_adjust.dart';

/// Ce que l'OSD (affichage à l'écran) doit montrer après une action.
///
/// Données structurées, sans texte ni icône : la mise en forme et la
/// traduction appartiennent au widget. Ce modèle est ainsi testable seul.
sealed class OsdMessage {
  const OsdMessage();
}

/// Avance ou recul, avec la position atteinte.
final class OsdSeek extends OsdMessage {
  const OsdSeek({
    required this.deltaSeconds,
    required this.position,
    required this.duration,
  });
  final double deltaSeconds;
  final Duration position;
  final Duration duration;
}

/// Volume après réglage, 0–100, et état de la sourdine.
final class OsdVolume extends OsdMessage {
  const OsdVolume({required this.volume, required this.muted});
  final double volume;
  final bool muted;
}

final class OsdSpeed extends OsdMessage {
  const OsdSpeed(this.speed);
  final double speed;
}

final class OsdPlayState extends OsdMessage {
  const OsdPlayState({required this.playing});
  final bool playing;
}

/// Changement de fichier par la playlist.
final class OsdFileChanged extends OsdMessage {
  const OsdFileChanged({required this.name, required this.forward});
  final String name;
  final bool forward;
}

final class OsdEndMode extends OsdMessage {
  const OsdEndMode(this.mode);
  final EndOfPlaybackMode mode;
}

final class OsdAlwaysOnTop extends OsdMessage {
  const OsdAlwaysOnTop({required this.enabled});
  final bool enabled;
}

final class OsdFullscreen extends OsdMessage {
  const OsdFullscreen({required this.enabled});
  final bool enabled;
}

/// Sous-titres affichés / masqués, ou piste changée.
final class OsdSubtitles extends OsdMessage {
  const OsdSubtitles({required this.visible, this.trackLabel});
  final bool visible;
  final String? trackLabel;
}

/// Décalage des sous-titres, en secondes.
final class OsdSubtitleDelay extends OsdMessage {
  const OsdSubtitleDelay(this.seconds);
  final double seconds;
}

final class OsdAudioTrack extends OsdMessage {
  const OsdAudioTrack(this.label);
  final String label;
}

/// Boucle A-B : étape atteinte.
final class OsdAbLoop extends OsdMessage {
  const OsdAbLoop({required this.a, required this.b});
  final Duration? a;
  final Duration? b;
}

final class OsdScreenshot extends OsdMessage {
  const OsdScreenshot(this.path);
  final String path;
}

/// La capture n'a pas pu être enregistrée (dossier inaccessible).
final class OsdScreenshotFailed extends OsdMessage {
  const OsdScreenshotFailed();
}

/// Un extrait commence à s'enregistrer.
final class OsdRecordingStarted extends OsdMessage {
  const OsdRecordingStarted();
}

/// Extrait enregistré : fichier et durée approximative.
final class OsdRecordingSaved extends OsdMessage {
  const OsdRecordingSaved(this.path, {this.length});
  final String path;
  final Duration? length;
}

/// Rien n'a pu être enregistré (lecture restée en pause, dossier
/// inaccessible, format refusé).
final class OsdRecordingFailed extends OsdMessage {
  const OsdRecordingFailed();
}

final class OsdAspect extends OsdMessage {
  const OsdAspect(this.mode);
  final AspectMode mode;
}

final class OsdVideoZoom extends OsdMessage {
  const OsdVideoZoom(this.zoom);

  /// Échelle mpv (logarithmique) ; 0 = 1×.
  final double zoom;
}

final class OsdVideoRotation extends OsdMessage {
  const OsdVideoRotation(this.quarterTurns);
  final int quarterTurns;
}

final class OsdEqualizer extends OsdMessage {
  const OsdEqualizer({required this.enabled, this.preset});
  final bool enabled;
  final String? preset;
}

final class OsdMiniPlayer extends OsdMessage {
  const OsdMiniPlayer({required this.enabled});
  final bool enabled;
}

/// Actions dont l'affichage à l'écran est le SEUL retour possible.
///
/// Le volume : l'utilisateur veut le voir comme il voit l'avance rapide, et
/// la molette agit le plus souvent au-dessus de l'image, loin du curseur de
/// la barre. La capture et l'extrait : ils écrivent un fichier ailleurs sur
/// le disque, et rien dans la fenêtre ne dit qu'ils ont réussi — ni qu'ils
/// ont échoué. Sans message, le bouton a l'air de ne rien faire.
bool osdAlwaysAnnounced(PlayerCommand command) => switch (command) {
      SetVolume() || VolumeRelative() || ToggleMute() => true,
      TakeScreenshot() || ToggleRecording() => true,
      _ => false,
    };

/// Décide si une action mérite un retour à l'écran.
///
/// Trois familles, et non deux :
///
/// 1. Les origines sans contrôle visible — clavier, ligne de commande,
///    système, télécommande : rien ne bouge à l'écran, l'OSD est leur seul
///    retour, il s'affiche toujours.
/// 2. Les actions d'[osdAlwaysAnnounced] : annoncées quelle que soit
///    l'origine et que la barre soit visible ou non.
/// 3. Le reste, à la souris : le contrôle que l'on vient de manipuler montre
///    déjà le résultat (la vitesse dans son menu, la piste dans le sien), donc
///    rien tant que la barre est visible ; masquée ([controlsHidden]), l'OSD
///    reprend son rôle.
///
/// Gestes continus : un glissement sur le faisceau de progression ou sur le
/// curseur de volume envoie une commande par pixel. Aucune origine nouvelle
/// n'est nécessaire pour empêcher l'OSD de clignoter — un glissement suppose
/// un contrôle sous le pointeur, donc une barre affichée (elle est même
/// retenue visible pendant le geste), et la règle 3 laisse alors l'écran
/// tranquille : c'est le cas du faisceau, dont la lampe suit déjà le doigt.
/// Le volume, lui, reste annoncé exprès : deux messages de même nature
/// réutilisent la même pastille et le même délai d'effacement — seul le
/// chiffre change, la pastille suit le geste au lieu de battre.
bool osdWantedFor(
  PlayerCommand command,
  CommandSource source, {
  required bool controlsHidden,
}) {
  if (osdAlwaysAnnounced(command)) return true;
  return switch (source) {
    CommandSource.ui => controlsHidden,
    CommandSource.keyboard ||
    CommandSource.cli ||
    CommandSource.system ||
    CommandSource.remote =>
      true,
  };
}

/// Message à afficher pour [command], sachant l'état [after] une fois la
/// commande traitée. `null` si l'action ne mérite pas de retour visuel.
OsdMessage? osdFor(PlayerCommand command, PlaybackState after) {
  // Sans fichier, la plupart des actions ne changent rien de visible.
  final hasMedia = after.hasFile && after.mediaType.isAv;

  return switch (command) {
    SeekRelative(:final seconds) when hasMedia => OsdSeek(
        deltaSeconds: seconds,
        position: after.position,
        duration: after.duration,
      ),
    SeekAbsolute() when hasMedia => OsdSeek(
        deltaSeconds: 0,
        position: after.position,
        duration: after.duration,
      ),
    SetVolume() || VolumeRelative() || ToggleMute() when after.mediaType.isAv || !after.hasFile => OsdVolume(
        volume: after.volume,
        muted: after.muted,
      ),
    SetSpeed() || SpeedRelative() when hasMedia => OsdSpeed(after.speed),
    Play() || Pause() || TogglePlay() when hasMedia => OsdPlayState(
        playing: after.isPlaying,
      ),
    NextFile() when after.file != null => OsdFileChanged(
        name: after.file!.name,
        forward: true,
      ),
    PreviousFile() when after.file != null => OsdFileChanged(
        name: after.file!.name,
        forward: false,
      ),
    SetLoopMode() || CycleLoopMode() => OsdEndMode(after.endMode),
    ToggleAlwaysOnTop() => OsdAlwaysOnTop(enabled: after.alwaysOnTop),
    ToggleFullscreen() || ExitFullscreen() => OsdFullscreen(
        enabled: after.fullscreen,
      ),
    ToggleSubtitles() || SetSubtitleTrack() || LoadSubtitleFile() when hasMedia => OsdSubtitles(
        visible: after.subtitlesVisible && after.subtitleTrackId != null,
        trackLabel: after.subtitleTracks
            .where((t) => t.id == after.subtitleTrackId)
            .map((t) => t.label)
            .firstOrNull,
      ),
    SetSubtitleDelay() || SubtitleDelayRelative() when hasMedia =>
      OsdSubtitleDelay(after.subtitleDelay),
    SetAudioTrack() when hasMedia => OsdAudioTrack(
        after.audioTracks
                .where((t) => t.id == after.audioTrackId)
                .map((t) => t.label)
                .firstOrNull ??
            '',
      ),
    CycleAbLoop() || ClearAbLoop() when hasMedia => OsdAbLoop(a: after.loopA, b: after.loopB),
    TakeScreenshot() when after.screenshotFailed => const OsdScreenshotFailed(),
    TakeScreenshot() when after.lastScreenshot != null => OsdScreenshot(after.lastScreenshot!),
    // Devant une image, ni chemin ni drapeau veut dire qu'aucune image n'a été
    // obtenue (moteur sans trame prête, contrôleur sans capture). L'état décrit
    // CETTE tentative — il est remis à zéro au début de chacune —, donc ce
    // silence est un échec : sans message, le bouton a l'air inerte.
    TakeScreenshot() when after.hasVideo => const OsdScreenshotFailed(),
    // L'arrêt réussi est annoncé par OsdController, qui suit l'état : un
    // extrait s'arrête aussi tout seul, en changeant de fichier.
    ToggleRecording() when after.recording => const OsdRecordingStarted(),
    // L'échec, lui, se dit ici. Deux tentatives impossibles de suite (lecture
    // en pause, document, dossier perdu) laissent le même état, avec la même
    // raison : le suivi d'état ne voit aucun front et resterait muet au second
    // appui. La commande, elle, arrive à chaque appui.
    ToggleRecording() when after.hasFile && after.recordingFailed =>
      const OsdRecordingFailed(),
    SetAspectMode() when hasMedia => OsdAspect(after.aspectMode),
    VideoZoomRelative() || ResetVideoZoom() when hasMedia => OsdVideoZoom(after.videoZoom),
    RotateVideo() when hasMedia => OsdVideoRotation(after.videoRotation),
    ToggleEqualizer() || SetEqualizerPreset() => OsdEqualizer(
        enabled: after.equalizerEnabled,
        preset: after.equalizerPreset,
      ),
    ToggleMiniPlayer() => OsdMiniPlayer(enabled: after.miniPlayer),
    _ => null,
  };
}
