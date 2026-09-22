import 'package:collection/collection.dart';

import '../models/app_preferences.dart';
import '../models/document_layout.dart';
import '../models/end_of_playback_mode.dart';
import '../models/playlist_sort.dart';
import '../models/video_adjust.dart';

/// Commandes du lecteur.
///
/// Règle d'or d'OMNIA : l'interface n'appelle jamais un contrôleur directement.
/// Chaque action utilisateur devient une [PlayerCommand] publiée sur le
/// [PlayerCommandBus]. Les commandes sont sérialisables en JSON pour qu'une
/// future télécommande (WebSocket) puisse émettre exactement les mêmes.
sealed class PlayerCommand {
  const PlayerCommand();

  /// Identifiant stable de la commande (clé `type` du JSON).
  String get type;

  /// Arguments de la commande, fusionnés dans le JSON.
  Map<String, Object?> get arguments => const {};

  Map<String, Object?> toJson() => {'type': type, ...arguments};

  /// Reconstruit une commande depuis son JSON.
  ///
  /// Lève une [FormatException] si le type est inconnu ou un argument absent.
  static PlayerCommand fromJson(Map<String, Object?> json) {
    final type = json['type'];
    return switch (type) {
      'play' => const Play(),
      'pause' => const Pause(),
      'togglePlay' => const TogglePlay(),
      'stop' => const Stop(),
      'seekRelative' => SeekRelative(_num(json, 'seconds').toDouble()),
      'seekAbsolute' =>
        SeekAbsolute(Duration(milliseconds: _num(json, 'positionMs').toInt())),
      'setVolume' => SetVolume(_num(json, 'volume').toDouble()),
      'volumeRelative' => VolumeRelative(_num(json, 'delta').toDouble()),
      'toggleMute' => const ToggleMute(),
      'nextFile' => const NextFile(),
      'previousFile' => const PreviousFile(),
      'setSpeed' => SetSpeed(_num(json, 'speed').toDouble()),
      'speedRelative' => SpeedRelative(_num(json, 'delta').toDouble()),
      'nextPage' => const NextPage(),
      'previousPage' => const PreviousPage(),
      'goToPage' => GoToPage(_num(json, 'page').toInt()),
      'setZoom' => SetZoom(_num(json, 'zoom').toDouble()),
      'toggleFullscreen' => const ToggleFullscreen(),
      'exitFullscreen' => const ExitFullscreen(),
      'takeScreenshot' => const TakeScreenshot(),
      'toggleRecording' => const ToggleRecording(),
      'setLoopMode' => SetLoopMode(EndOfPlaybackMode.fromJson(json['mode'])),
      'cycleLoopMode' => const CycleLoopMode(),
      'toggleAlwaysOnTop' => ToggleAlwaysOnTop(
          forMiniPlayer: json['forMiniPlayer'] as bool?,
        ),
      'toggleSidePanel' => const ToggleSidePanel(),

      'setSidePanelVisible' => SetSidePanelVisible(_bool(json, 'visible')),
      'setSidePanelWidth' => SetSidePanelWidth(_num(json, 'width').toDouble()),
      'setControlBarWidth' => SetControlBarWidth(_num(json, 'width').toDouble()),
      'openFile' => OpenFile(_string(json, 'path')),
      'openFolder' => OpenFolder(_string(json, 'path')),
      'setPlaylistSort' => SetPlaylistSort(
          PlaylistSort.fromJson(json['sort']),
          descending: json['descending'] as bool? ?? false,
        ),
      'setPlaylistFilter' =>
        SetPlaylistFilter(PlaylistFilter.fromJson(json['filter'])),
      'setPlaylistQuery' => SetPlaylistQuery(_string(json, 'query')),
      'removeFromPlaylist' => RemoveFromPlaylist(_string(json, 'path')),
      'rescanFolder' => const RescanFolder(),
      'revealInFolder' => RevealInFolder(_string(json, 'path')),
      'clearHistory' => const ClearHistory(),
      'clearRecentFiles' => const ClearRecentFiles(),
      'clearResumePositions' => const ClearResumePositions(),
      'acceptResume' => const AcceptResume(),
      'declineResume' => const DeclineResume(),
      'updatePreferences' => UpdatePreferences(
          Map<String, Object?>.from(
            json['changes'] as Map? ??
                (throw const FormatException('Argument manquant : changes')),
          ),
        ),
      'setScreenshotFolder' => SetScreenshotFolder(json['path'] as String?),
      'setRecordingFolder' => SetRecordingFolder(json['path'] as String?),
      'zoomRelative' => ZoomRelative(_num(json, 'factor').toDouble()),

      'fitZoom' => FitZoom(FitMode.fromJson(json['mode'])),
      'rotateDocument' => RotateDocument(_num(json, 'quarterTurns').toInt()),
      'toggleReadingDarkMode' => const ToggleReadingDarkMode(),
      'setDocumentLayout' =>
        SetDocumentLayout(DocumentLayout.fromJson(json['layout'])),
      'toggleDocumentLayout' => const ToggleDocumentLayout(),
      'scrollTo' => ScrollTo(_num(json, 'fraction').toDouble()),
      'scrollDocument' => ScrollDocument(_num(json, 'delta').toDouble()),
      'setSubtitleTrack' => SetSubtitleTrack(json['id'] as String?),
      'toggleSubtitles' => const ToggleSubtitles(),
      'loadSubtitleFile' => LoadSubtitleFile(_string(json, 'path')),
      'setSubtitleDelay' => SetSubtitleDelay(_num(json, 'seconds').toDouble()),
      'subtitleDelayRelative' => SubtitleDelayRelative(_num(json, 'delta').toDouble()),
      'setSubtitleScale' => SetSubtitleScale(_num(json, 'scale').toDouble()),
      'setAudioTrack' => SetAudioTrack(json['id'] as String?),
      'cycleAbLoop' => const CycleAbLoop(),
      'clearAbLoop' => const ClearAbLoop(),
      'setAspectMode' => SetAspectMode(AspectMode.fromJson(json['mode'])),
      'videoZoomRelative' => VideoZoomRelative(_num(json, 'delta').toDouble()),
      'resetVideoZoom' => const ResetVideoZoom(),
      'rotateVideo' => RotateVideo(_num(json, 'quarterTurns').toInt()),
      'setVideoAdjust' => SetVideoAdjust(
          VideoAdjust.fromJson(Map<String, Object?>.from(json['adjust'] as Map)),
        ),
      'resetVideoAdjust' => const ResetVideoAdjust(),
      'setEqualizerGains' => SetEqualizerGains(
          (json['gains'] as List).whereType<num>().map((n) => n.toDouble()).toList(),
        ),
      'setEqualizerPreset' => SetEqualizerPreset(_string(json, 'preset')),
      'toggleEqualizer' => const ToggleEqualizer(),
      'toggleMiniPlayer' => const ToggleMiniPlayer(),
      _ => throw FormatException('Commande inconnue : $type'),
    };
  }

  static num _num(Map<String, Object?> json, String key) {
    final v = json[key];
    if (v is num) return v;
    throw FormatException('Argument numérique manquant : $key');
  }

  static String _string(Map<String, Object?> json, String key) {
    final v = json[key];
    if (v is String) return v;
    throw FormatException('Argument texte manquant : $key');
  }

  static bool _bool(Map<String, Object?> json, String key) {
    final v = json[key];
    if (v is bool) return v;
    throw FormatException('Argument booléen manquant : $key');
  }

  static const _equality = DeepCollectionEquality();

  @override
  bool operator ==(Object other) =>
      other is PlayerCommand &&
      other.runtimeType == runtimeType &&
      _equality.equals(other.toJson(), toJson());

  @override
  int get hashCode => _equality.hash(toJson());

  @override
  String toString() => 'PlayerCommand${toJson()}';
}

// --- Transport -------------------------------------------------------------

final class Play extends PlayerCommand {
  const Play();
  @override
  String get type => 'play';
}

final class Pause extends PlayerCommand {
  const Pause();
  @override
  String get type => 'pause';
}

final class TogglePlay extends PlayerCommand {
  const TogglePlay();
  @override
  String get type => 'togglePlay';
}

/// Arrête la lecture et ferme le fichier courant.
final class Stop extends PlayerCommand {
  const Stop();
  @override
  String get type => 'stop';
}

/// Avance (positif) ou recule (négatif) de [seconds] secondes.
final class SeekRelative extends PlayerCommand {
  const SeekRelative(this.seconds);
  final double seconds;
  @override
  String get type => 'seekRelative';
  @override
  Map<String, Object?> get arguments => {'seconds': seconds};
}

final class SeekAbsolute extends PlayerCommand {
  const SeekAbsolute(this.position);
  final Duration position;
  @override
  String get type => 'seekAbsolute';
  @override
  Map<String, Object?> get arguments =>
      {'positionMs': position.inMilliseconds};
}

// --- Volume ---------------------------------------------------------------

/// Volume absolu, 0–100.
final class SetVolume extends PlayerCommand {
  const SetVolume(this.volume);
  final double volume;
  @override
  String get type => 'setVolume';
  @override
  Map<String, Object?> get arguments => {'volume': volume};
}

final class VolumeRelative extends PlayerCommand {
  const VolumeRelative(this.delta);
  final double delta;
  @override
  String get type => 'volumeRelative';
  @override
  Map<String, Object?> get arguments => {'delta': delta};
}

final class ToggleMute extends PlayerCommand {
  const ToggleMute();
  @override
  String get type => 'toggleMute';
}

// --- Playlist -------------------------------------------------------------

final class NextFile extends PlayerCommand {
  const NextFile();
  @override
  String get type => 'nextFile';
}

final class PreviousFile extends PlayerCommand {
  const PreviousFile();
  @override
  String get type => 'previousFile';
}

// --- Vitesse --------------------------------------------------------------

final class SetSpeed extends PlayerCommand {
  const SetSpeed(this.speed);
  final double speed;
  @override
  String get type => 'setSpeed';
  @override
  Map<String, Object?> get arguments => {'speed': speed};
}

final class SpeedRelative extends PlayerCommand {
  const SpeedRelative(this.delta);
  final double delta;
  @override
  String get type => 'speedRelative';
  @override
  Map<String, Object?> get arguments => {'delta': delta};
}

// --- Documents ------------------------------------------------------------

final class NextPage extends PlayerCommand {
  const NextPage();
  @override
  String get type => 'nextPage';
}

final class PreviousPage extends PlayerCommand {
  const PreviousPage();
  @override
  String get type => 'previousPage';
}

/// Page 1-based.
final class GoToPage extends PlayerCommand {
  const GoToPage(this.page);
  final int page;
  @override
  String get type => 'goToPage';
  @override
  Map<String, Object?> get arguments => {'page': page};
}

final class SetZoom extends PlayerCommand {
  const SetZoom(this.zoom);
  final double zoom;
  @override
  String get type => 'setZoom';
  @override
  Map<String, Object?> get arguments => {'zoom': zoom};
}

// --- Fenêtre & divers -----------------------------------------------------

final class ToggleFullscreen extends PlayerCommand {
  const ToggleFullscreen();
  @override
  String get type => 'toggleFullscreen';
}

final class ExitFullscreen extends PlayerCommand {
  const ExitFullscreen();
  @override
  String get type => 'exitFullscreen';
}

final class TakeScreenshot extends PlayerCommand {
  const TakeScreenshot();
  @override
  String get type => 'takeScreenshot';
}

/// Démarre ou arrête l'enregistrement d'un extrait du média en cours : le
/// flux lu est recopié tel quel dans un fichier, sans réencodage.
final class ToggleRecording extends PlayerCommand {
  const ToggleRecording();
  @override
  String get type => 'toggleRecording';
}

final class SetLoopMode extends PlayerCommand {
  const SetLoopMode(this.mode);
  final EndOfPlaybackMode mode;
  @override
  String get type => 'setLoopMode';
  @override
  Map<String, Object?> get arguments => {'mode': mode.name};
}

final class CycleLoopMode extends PlayerCommand {
  const CycleLoopMode();
  @override
  String get type => 'cycleLoopMode';
}

final class ToggleAlwaysOnTop extends PlayerCommand {
  const ToggleAlwaysOnTop({this.forMiniPlayer});
  final bool? forMiniPlayer;
  @override
  String get type => 'toggleAlwaysOnTop';
  @override
  Map<String, Object?> get arguments => {'forMiniPlayer': forMiniPlayer};
}


final class ToggleSidePanel extends PlayerCommand {
  const ToggleSidePanel();
  @override
  String get type => 'toggleSidePanel';
}

final class SetSidePanelVisible extends PlayerCommand {
  const SetSidePanelVisible(this.visible);
  final bool visible;
  @override
  String get type => 'setSidePanelVisible';
  @override
  Map<String, Object?> get arguments => {'visible': visible};
}

final class SetSidePanelWidth extends PlayerCommand {
  const SetSidePanelWidth(this.width);
  final double width;
  @override
  String get type => 'setSidePanelWidth';
  @override
  Map<String, Object?> get arguments => {'width': width};
}

/// Largeur de la barre de contrôles, en pixels logiques. 0 rend la largeur
/// automatique (toute la place disponible, dans la limite du design).
final class SetControlBarWidth extends PlayerCommand {
  const SetControlBarWidth(this.width);
  final double width;
  @override
  String get type => 'setControlBarWidth';
  @override
  Map<String, Object?> get arguments => {'width': width};
}

// --- Ouverture ------------------------------------------------------------

/// Ouvre un fichier par son chemin absolu (déclenche le scan du dossier).
final class OpenFile extends PlayerCommand {
  const OpenFile(this.path);
  final String path;
  @override
  String get type => 'openFile';
  @override
  Map<String, Object?> get arguments => {'path': path};
}

/// Ouvre un dossier : scan, puis lecture du premier fichier lisible.
final class OpenFolder extends PlayerCommand {
  const OpenFolder(this.path);
  final String path;
  @override
  String get type => 'openFolder';
  @override
  Map<String, Object?> get arguments => {'path': path};
}

// --- Panneau de dossier ---------------------------------------------------

final class SetPlaylistSort extends PlayerCommand {
  const SetPlaylistSort(this.sort, {this.descending = false});
  final PlaylistSort sort;
  final bool descending;
  @override
  String get type => 'setPlaylistSort';
  @override
  Map<String, Object?> get arguments =>
      {'sort': sort.name, 'descending': descending};
}

final class SetPlaylistFilter extends PlayerCommand {
  const SetPlaylistFilter(this.filter);
  final PlaylistFilter filter;
  @override
  String get type => 'setPlaylistFilter';
  @override
  Map<String, Object?> get arguments => {'filter': filter.name};
}

/// Recherche instantanée dans le panneau.
final class SetPlaylistQuery extends PlayerCommand {
  const SetPlaylistQuery(this.query);
  final String query;
  @override
  String get type => 'setPlaylistQuery';
  @override
  Map<String, Object?> get arguments => {'query': query};
}

/// Retire un élément de la liste affichée, sans toucher au fichier sur disque.
final class RemoveFromPlaylist extends PlayerCommand {
  const RemoveFromPlaylist(this.path);
  final String path;
  @override
  String get type => 'removeFromPlaylist';
  @override
  Map<String, Object?> get arguments => {'path': path};
}

/// Relance le scan du dossier courant.
final class RescanFolder extends PlayerCommand {
  const RescanFolder();
  @override
  String get type => 'rescanFolder';
}

/// Ouvre l'emplacement du fichier dans le gestionnaire de fichiers du système.
final class RevealInFolder extends PlayerCommand {
  const RevealInFolder(this.path);
  final String path;
  @override
  String get type => 'revealInFolder';
  @override
  Map<String, Object?> get arguments => {'path': path};
}

/// Efface l'historique : fichiers récents et positions mémorisées.
final class ClearHistory extends PlayerCommand {
  const ClearHistory();
  @override
  String get type => 'clearHistory';
}

/// Vide la liste des fichiers récents, sans oublier les positions.
final class ClearRecentFiles extends PlayerCommand {
  const ClearRecentFiles();
  @override
  String get type => 'clearRecentFiles';
}

/// Oublie toutes les positions de lecture, sans toucher aux récents.
final class ClearResumePositions extends PlayerCommand {
  const ClearResumePositions();
  @override
  String get type => 'clearResumePositions';
}

/// Accepte la reprise proposée (politique « demander »).
final class AcceptResume extends PlayerCommand {
  const AcceptResume();
  @override
  String get type => 'acceptResume';
}

/// Refuse la reprise proposée : le fichier continue depuis le début.
final class DeclineResume extends PlayerCommand {
  const DeclineResume();
  @override
  String get type => 'declineResume';
}

// --- Paramètres --------------------------------------------------------------

/// Modifie des préférences. L'écran Paramètres passe par le bus comme le
/// reste : le service de lecture enregistre, et aligne ce qui est en cours
/// (taille des sous-titres, égaliseur, mode sombre de lecture…).
///
/// [changes] ne contient que les réglages modifiés, au format JSON de
/// [AppPreferences] (`{'seekStepSeconds': 10}`) : deux changements rapprochés
/// ne peuvent pas s'écraser l'un l'autre, et une télécommande n'a pas besoin
/// de connaître tous les réglages pour en changer un.
final class UpdatePreferences extends PlayerCommand {
  const UpdatePreferences(this.changes);

  /// Construit la commande à partir de deux états : seules les différences
  /// sont transmises.
  factory UpdatePreferences.between(AppPreferences before, AppPreferences after) =>
      UpdatePreferences(preferencesDiff(before, after));

  final Map<String, Object?> changes;
  @override
  String get type => 'updatePreferences';
  @override
  Map<String, Object?> get arguments => {'changes': changes};
}

/// Dossier des captures d'écran ; `null` revient au dossier par défaut.
final class SetScreenshotFolder extends PlayerCommand {
  const SetScreenshotFolder(this.path);
  final String? path;
  @override
  String get type => 'setScreenshotFolder';
  @override
  Map<String, Object?> get arguments => {'path': path};
}

/// Dossier des extraits / enregistrements audio ; `null` revient au dossier par défaut.
final class SetRecordingFolder extends PlayerCommand {
  const SetRecordingFolder(this.path);
  final String? path;
  @override
  String get type => 'setRecordingFolder';
  @override
  Map<String, Object?> get arguments => {'path': path};
}


// --- Documents -------------------------------------------------------------

/// Multiplie le zoom par [factor] (`Ctrl+molette`).
final class ZoomRelative extends PlayerCommand {
  const ZoomRelative(this.factor);
  final double factor;
  @override
  String get type => 'zoomRelative';
  @override
  Map<String, Object?> get arguments => {'factor': factor};
}

/// Ajuste le zoom à la largeur ou à la page (`Ctrl+0`).
final class FitZoom extends PlayerCommand {
  const FitZoom(this.mode);
  final FitMode mode;
  @override
  String get type => 'fitZoom';
  @override
  Map<String, Object?> get arguments => {'mode': mode.name};
}

/// Tourne le document de [quarterTurns] quarts de tour (1 = 90° horaire).
final class RotateDocument extends PlayerCommand {
  const RotateDocument([this.quarterTurns = 1]);
  final int quarterTurns;
  @override
  String get type => 'rotateDocument';
  @override
  Map<String, Object?> get arguments => {'quarterTurns': quarterTurns};
}

/// Mode sombre de lecture (inversion douce des couleurs du document).
final class ToggleReadingDarkMode extends PlayerCommand {
  const ToggleReadingDarkMode();
  @override
  String get type => 'toggleReadingDarkMode';
}

final class SetDocumentLayout extends PlayerCommand {
  const SetDocumentLayout(this.layout);
  final DocumentLayout layout;
  @override
  String get type => 'setDocumentLayout';
  @override
  Map<String, Object?> get arguments => {'layout': layout.name};
}

final class ToggleDocumentLayout extends PlayerCommand {
  const ToggleDocumentLayout();
  @override
  String get type => 'toggleDocumentLayout';
}

/// Fait défiler un texte à [fraction] (0 = début, 1 = fin).
///
/// Émise par la vue quand l'utilisateur fait défiler (pour la mémorisation),
/// et utilisable par une télécommande pour se déplacer dans le document.
final class ScrollTo extends PlayerCommand {
  const ScrollTo(this.fraction);
  final double fraction;
  @override
  String get type => 'scrollTo';
  @override
  Map<String, Object?> get arguments => {'fraction': fraction};
}

/// Émise pour faire défiler le document d'une distance en pixels (positif vers le bas).
final class ScrollDocument extends PlayerCommand {
  const ScrollDocument(this.delta);
  final double delta;
  @override
  String get type => 'scrollDocument';
  @override
  Map<String, Object?> get arguments => {'delta': delta};
}

// --- Sous-titres et pistes audio ------------------------------------------

/// Sélectionne une piste de sous-titres ; `null` pour aucune.
final class SetSubtitleTrack extends PlayerCommand {
  const SetSubtitleTrack(this.id);
  final String? id;
  @override
  String get type => 'setSubtitleTrack';
  @override
  Map<String, Object?> get arguments => {'id': id};
}

/// Affiche / masque les sous-titres sans changer la piste choisie (`V`).
final class ToggleSubtitles extends PlayerCommand {
  const ToggleSubtitles();
  @override
  String get type => 'toggleSubtitles';
}

/// Charge un fichier de sous-titres externe et le sélectionne.
final class LoadSubtitleFile extends PlayerCommand {
  const LoadSubtitleFile(this.path);
  final String path;
  @override
  String get type => 'loadSubtitleFile';
  @override
  Map<String, Object?> get arguments => {'path': path};
}

final class SetSubtitleDelay extends PlayerCommand {
  const SetSubtitleDelay(this.seconds);
  final double seconds;
  @override
  String get type => 'setSubtitleDelay';
  @override
  Map<String, Object?> get arguments => {'seconds': seconds};
}

final class SubtitleDelayRelative extends PlayerCommand {
  const SubtitleDelayRelative(this.delta);
  final double delta;
  @override
  String get type => 'subtitleDelayRelative';
  @override
  Map<String, Object?> get arguments => {'delta': delta};
}

final class SetSubtitleScale extends PlayerCommand {
  const SetSubtitleScale(this.scale);
  final double scale;
  @override
  String get type => 'setSubtitleScale';
  @override
  Map<String, Object?> get arguments => {'scale': scale};
}

/// Sélectionne une piste audio ; `null` pour « automatique ».
final class SetAudioTrack extends PlayerCommand {
  const SetAudioTrack(this.id);
  final String? id;
  @override
  String get type => 'setAudioTrack';
  @override
  Map<String, Object?> get arguments => {'id': id};
}

// --- Boucle A-B -------------------------------------------------------------

/// Touche `A` : pose A, puis B (boucle active), puis efface.
final class CycleAbLoop extends PlayerCommand {
  const CycleAbLoop();
  @override
  String get type => 'cycleAbLoop';
}

final class ClearAbLoop extends PlayerCommand {
  const ClearAbLoop();
  @override
  String get type => 'clearAbLoop';
}

// --- Image ------------------------------------------------------------------

final class SetAspectMode extends PlayerCommand {
  const SetAspectMode(this.mode);
  final AspectMode mode;
  @override
  String get type => 'setAspectMode';
  @override
  Map<String, Object?> get arguments => {'mode': mode.name};
}

/// Zoom vidéo relatif, sur l'échelle logarithmique de mpv (0.1 ≈ +7 %).
final class VideoZoomRelative extends PlayerCommand {
  const VideoZoomRelative(this.delta);
  final double delta;
  @override
  String get type => 'videoZoomRelative';
  @override
  Map<String, Object?> get arguments => {'delta': delta};
}

final class ResetVideoZoom extends PlayerCommand {
  const ResetVideoZoom();
  @override
  String get type => 'resetVideoZoom';
}

/// Pivote la vidéo de [quarterTurns] quarts de tour (1 = 90° horaire).
final class RotateVideo extends PlayerCommand {
  const RotateVideo([this.quarterTurns = 1]);
  final int quarterTurns;
  @override
  String get type => 'rotateVideo';
  @override
  Map<String, Object?> get arguments => {'quarterTurns': quarterTurns};
}

final class SetVideoAdjust extends PlayerCommand {
  const SetVideoAdjust(this.adjust);
  final VideoAdjust adjust;
  @override
  String get type => 'setVideoAdjust';
  @override
  Map<String, Object?> get arguments => {'adjust': adjust.toJson()};
}

final class ResetVideoAdjust extends PlayerCommand {
  const ResetVideoAdjust();
  @override
  String get type => 'resetVideoAdjust';
}

// --- Égaliseur --------------------------------------------------------------

final class SetEqualizerGains extends PlayerCommand {
  const SetEqualizerGains(this.gains);
  final List<double> gains;
  @override
  String get type => 'setEqualizerGains';
  @override
  Map<String, Object?> get arguments => {'gains': gains};
}

final class SetEqualizerPreset extends PlayerCommand {
  const SetEqualizerPreset(this.preset);
  final String preset;
  @override
  String get type => 'setEqualizerPreset';
  @override
  Map<String, Object?> get arguments => {'preset': preset};
}

final class ToggleEqualizer extends PlayerCommand {
  const ToggleEqualizer();
  @override
  String get type => 'toggleEqualizer';
}

// --- Fenêtre ---------------------------------------------------------------

/// Bascule le mode mini-lecteur (fenêtre compacte au premier plan).
final class ToggleMiniPlayer extends PlayerCommand {
  const ToggleMiniPlayer();
  @override
  String get type => 'toggleMiniPlayer';
}
