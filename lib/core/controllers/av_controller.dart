import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../commands/player_command.dart';
import '../models/app_preferences.dart';
import '../models/equalizer.dart';
import '../models/media_file.dart';
import '../models/media_type.dart';
import '../models/playback_state.dart';
import '../models/playback_status.dart';
import '../models/track_info.dart';
import '../models/video_adjust.dart';
import '../utils/os_errors.dart';
import 'frame_capturer.dart';
import 'media_controller.dart';
import 'stream_recorder.dart';

/// Contrôleur audio/vidéo basé sur media_kit (libmpv).
///
/// Un seul [Player] pour toute la vie de l'application : ouvrir un nouveau
/// fichier remplace le précédent sans recréer le moteur (ouverture < 1 s).
///
/// Tout ce que media_kit n'expose pas directement (sourdine, sous-titres
/// externes automatiques, boucle A-B, image, égaliseur) passe par les
/// propriétés mpv, derrière [_setProperty] qui n'échoue jamais bruyamment :
/// une propriété refusée par une version de mpv laisse la lecture intacte.
class AvController implements MediaController, FrameCapturer, StreamRecorder {
  /// [withVideoOutput] à `false` : aucune surface de rendu n'est créée, et
  /// [videoController] reste inutilisable. Réservé aux tests qui pilotent
  /// libmpv sans interface : la surface attend le moteur Flutter et ses canaux
  /// de plateforme, et sans eux tout appel à mpv resterait en attente.
  AvController({
    Player? player,
    AppPreferences Function()? preferences,
    bool withVideoOutput = true,
  })
      // libass : mpv dessine les sous-titres dans l'image, et media_kit retire
      // sa propre couche de texte. Sans cela, activer une piste les
      // affichait deux fois, et « masquer » laissait la copie de media_kit.
      : player = player ?? Player(configuration: const PlayerConfiguration(libass: true)),
        _preferences = preferences ?? (() => AppPreferences.defaults) {
    if (withVideoOutput) videoController = VideoController(this.player);
    _listen();
    unawaited(_applyBaseProperties());
  }

  /// Moteur mpv.
  final Player player;

  /// Préférences lues à chaque ouverture (sous-titres automatiques, décalage
  /// par défaut) : un changement dans les paramètres vaut dès le fichier suivant.
  final AppPreferences Function() _preferences;

  /// Surface de rendu vidéo, consommée par le widget `Video` de l'interface.
  /// Non initialisée quand le contrôleur est créé sans sortie vidéo.
  late final VideoController videoController;

  PlaybackStateSink? _sink;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  /// Vrai entre `open()` et le premier événement de lecture, pour ne pas
  /// afficher « en pause » pendant le chargement.
  bool _opening = false;

  /// Pistes rapportées par mpv pour le fichier courant, pour retrouver un
  /// objet piste à partir de son identifiant.
  Tracks _tracks = const Tracks();

  @override
  Set<MediaType> get supportedTypes => const {MediaType.video, MediaType.audio};

  /// Réglages mpv valables pour toute la session.
  ///
  /// media_kit impose des réglages de rendu économiques (mise à l'échelle
  /// bilinéaire, aucun tramage). On rétablit ceux d'un mpv autonome : le
  /// tramage évite les dégradés en escalier (ciel, scènes sombres) des vidéos
  /// 10 bits affichées en 8 bits, et les filtres de mise à l'échelle ne
  /// coûtent rien tant que l'image est rendue à sa taille d'origine.
  Future<void> _applyBaseProperties() async {
    // Une seule image demandée à la capture, pas de bande-son de clic.
    await _setProperty('screenshot-format', 'png');
    await _setProperty('dither', 'fruit');
    await _setProperty('dither-depth', 'auto');
    await _setProperty('scale', 'spline36');
    await _setProperty('dscale', 'mitchell');
    await _setProperty('correct-downscaling', 'yes');
    await _setProperty('demuxer-max-back-bytes', '50M');
  }

  // Position : mpv la publie à chaque image affichée, soit 25 à 60 fois par
  // seconde (et deux fois plus à 2×). L'interface n'en a pas besoin d'autant,
  // et chaque mise à jour la reconstruit : on en garde six par seconde au
  // plus. Un saut (recherche, nouveau fichier) passe tout de suite.
  final Stopwatch _positionClock = Stopwatch()..start();
  Duration _lastPosition = Duration.zero;

  void _onPosition(Duration position) {
    final jump = (position - _lastPosition).abs() > const Duration(milliseconds: 900);
    if (!jump && _positionClock.elapsedMilliseconds < 150) return;
    _publishPosition(position);
  }

  void _publishPosition(Duration position) {
    _positionClock.reset();
    _lastPosition = position;
    _update((st) => st.copyWith(position: position));
  }

  void _listen() {
    final s = player.stream;
    _subscriptions.addAll([
      s.position.listen(_onPosition),
      s.duration.listen((duration) => _update((st) => st.copyWith(duration: duration))),
      s.buffering.listen((buffering) => _update((st) => st.copyWith(buffering: buffering))),
      s.volume.listen((volume) => _update((st) => st.copyWith(volume: volume))),
      s.rate.listen((rate) => _update((st) => st.copyWith(speed: rate))),
      // Dimensions d'affichage de l'image : media_kit les tire de
      // `video-out-params` (dw, dh), rapport d'aspect et rotation compris.
      // Largeur et hauteur arrivent sur deux flux, mais l'état du moteur tient
      // déjà les deux : on publie la paire, sans ratio intermédiaire (nouvelle
      // largeur, ancienne hauteur) qui redimensionnerait le mini-lecteur pour
      // rien. `null` : moteur remis à zéro entre deux fichiers, ce que
      // `open()` et `close()` ont déjà reporté dans l'état.
      s.width.listen((width) {
        if (width == null) return;
        _update(
          (st) => st.copyWith(
            hasVideo: width > 0,
            videoWidth: width,
            videoHeight: player.state.height ?? st.videoHeight,
          ),
        );
      }),
      s.height.listen((height) {
        if (height == null) return;
        _update(
          (st) => st.copyWith(
            videoWidth: player.state.width ?? st.videoWidth,
            videoHeight: height,
          ),
        );
      }),
      s.tracks.listen((tracks) {
        _tracks = tracks;
        _update(
          (st) => st.copyWith(
            subtitleTracks: tracks.subtitle.where(_isRealTrack).map(_toInfo).toList(),
            audioTracks: tracks.audio.where(_isRealTrack).map(_toInfo).toList(),
          ),
        );
      }),
      s.track.listen((track) {
        _update(
          (st) => st.copyWith(
            subtitleTrackId: _isRealTrack(track.subtitle) ? track.subtitle.id : null,
            clearSubtitleTrack: !_isRealTrack(track.subtitle),
            audioTrackId: _isRealTrack(track.audio) ? track.audio.id : null,
            clearAudioTrack: !_isRealTrack(track.audio),
          ),
        );
      }),
      s.playing.listen((playing) {
        if (playing) _opening = false;
        // À la pause, la position affichée est l'exacte, pas la dernière
        // retenue par le filtre de fréquence.
        if (!playing) _publishPosition(player.state.position);
        _update((st) {
          if (st.status == PlaybackStatus.error) return st;
          if (!playing && _opening) return st;
          return st.copyWith(
            status: playing ? PlaybackStatus.playing : PlaybackStatus.paused,
          );
        });
      }),
      s.completed.listen((completed) {
        if (!completed) return;
        _update((st) => st.copyWith(status: PlaybackStatus.ended));
      }),
      s.error.listen((message) {
        // mpv émet aussi des erreurs non fatales en cours de lecture (une
        // piste de sous-titres illisible, un paquet corrompu). Interrompre la
        // lecture pour cela remplacerait une image qui s'affiche par un écran
        // d'erreur. On ne bascule en erreur que si rien ne joue encore.
        final st = _sink?.state;
        final fatal = _opening ||
            st == null ||
            st.status == PlaybackStatus.loading ||
            st.duration <= Duration.zero;
        if (!fatal) return;
        _opening = false;
        _update(
          (state) => state.copyWith(
            status: PlaybackStatus.error,
            error: PlaybackError(PlaybackErrorCode.decodeFailed, detail: message),
          ),
        );
      }),
    ]);
  }

  /// media_kit liste aussi les pseudo-pistes « auto » et « no ».
  static bool _isRealTrack(Object track) {
    final id = switch (track) {
      SubtitleTrack(:final id) => id,
      AudioTrack(:final id) => id,
      VideoTrack(:final id) => id,
      _ => '',
    };
    return id != 'auto' && id != 'no';
  }

  static TrackInfo _toInfo(Object track) => switch (track) {
        SubtitleTrack(:final id, :final title, :final language, :final uri) => TrackInfo(
            id: id,
            title: title ?? (uri ? p.basename(id) : null),
            language: language,
            external: uri,
          ),
        AudioTrack(:final id, :final title, :final language, :final uri) =>
          TrackInfo(id: id, title: title, language: language, external: uri),
        _ => const TrackInfo(id: '?'),
      };

  void _update(PlaybackState Function(PlaybackState) reducer) {
    _sink?.update(reducer);
  }

  /// Écrit une propriété mpv. Une propriété inconnue ou refusée ne doit pas
  /// interrompre la lecture : on l'ignore.
  Future<void> _setProperty(String name, String value) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty(name, value);
    } on Object {
      // Propriété absente de cette version de mpv, ou moteur déjà libéré.
    }
  }

  @override
  Future<void> open(MediaFile file, PlaybackStateSink sink) async {
    _sink = sink;
    _opening = true;

    if (!File(file.path).existsSync()) {
      _opening = false;
      // Remettre position, durée et présence vidéo à zéro : sans cela, l'état
      // garderait celles du fichier précédent, et la sauvegarde de position
      // les attribuerait au nouveau fichier.
      sink.update(
        (st) => st.copyWith(
          file: file,
          status: PlaybackStatus.error,
          position: Duration.zero,
          duration: Duration.zero,
          hasVideo: false,
          videoWidth: 0,
          videoHeight: 0,
          error: const PlaybackError(PlaybackErrorCode.fileNotFound),
        ),
      );
      return;
    }

    final prefs = _preferences();
    // Vitesse, volume, sourdine, sous-titres, image et égaliseur sont
    // conservés d'un fichier à l'autre. On les relève AVANT d'ouvrir : le
    // moteur peut publier ses propres valeurs pendant l'ouverture, qui
    // écraseraient celles de l'utilisateur.
    final state = sink.state;

    sink.update(
      (st) => st.copyWith(
        file: file,
        status: PlaybackStatus.loading,
        position: Duration.zero,
        duration: Duration.zero,
        hasVideo: file.type == MediaType.video,
        // Dimensions de l'image : connues seulement une fois la première image
        // décodée. Jusque-là, le mini-lecteur garde sa forme.
        videoWidth: 0,
        videoHeight: 0,
        // Propres à chaque fichier : pistes, boucle A-B, décalage des
        // sous-titres, zoom et rotation de l'image.
        subtitleTracks: const [],
        audioTracks: const [],
        clearSubtitleTrack: true,
        clearAudioTrack: true,
        clearLoop: true,
        subtitleDelay: prefs.subtitleDelay,
        videoZoom: 0,
        videoRotation: 0,
        clearError: true,
      ),
    );

    try {
      // Sous-titres voisins chargés automatiquement : même nom de base, avec
      // ou sans suffixe de langue (`film.srt`, `film.fr.srt`).
      await _setProperty('sub-auto', prefs.subtitleAutoLoad ? 'fuzzy' : 'no');
      await _setProperty('ab-loop-a', 'no');
      await _setProperty('ab-loop-b', 'no');
      await _setProperty('sub-delay', prefs.subtitleDelay.toStringAsFixed(2));
      await _setProperty('video-zoom', '0');
      await _setProperty('video-rotate', '0');

      await player.open(Media(file.path), play: true);

      await player.setRate(state.speed);
      await player.setVolume(state.volume);
      await _setMuted(state.muted);
      await _setProperty('sub-visibility', state.subtitlesVisible ? 'yes' : 'no');
      await _setProperty('sub-scale', state.subtitleScale.toStringAsFixed(2));
      await _applyNeutralAspect();
      await _applyAdjust(state.videoAdjust);
      await _applyEqualizer(state.equalizerEnabled ? state.equalizerGains : Equalizer.flat);
    } on Object catch (e) {
      _opening = false;
      sink.update(
        (st) => st.copyWith(
          status: PlaybackStatus.error,
          error: PlaybackError(_classify(e), detail: e.toString()),
        ),
      );
    }
  }

  PlaybackErrorCode _classify(Object error) {
    if (error is FileSystemException) return classifyFileSystemError(error);
    return PlaybackErrorCode.decodeFailed;
  }

  @override
  Future<bool> handle(PlayerCommand command) async {
    final state = _sink?.state;
    if (state == null || !state.hasFile) return false;

    switch (command) {
      case Play():
        await player.play();
      case Pause():
        await player.pause();
      case TogglePlay():
        if (state.status == PlaybackStatus.ended) {
          await player.seek(Duration.zero);
          await player.play();
        } else {
          await player.playOrPause();
        }
      case SeekRelative(:final seconds):
        await _seekTo(state.position + Duration(milliseconds: (seconds * 1000).round()));
      case SeekAbsolute(:final position):
        await _seekTo(position);
      case SetVolume(:final volume):
        await _setVolume(volume);
      case VolumeRelative(:final delta):
        await _setVolume(state.volume + delta);
      case ToggleMute():
        await _setMuted(!state.muted);
      case SetSpeed(:final speed):
        await _setSpeed(speed);
      case SpeedRelative(:final delta):
        await _setSpeed(state.speed + delta);

      // Sous-titres
      case SetSubtitleTrack(:final id):
        await _selectSubtitle(id);
      case ToggleSubtitles():
        final visible = !state.subtitlesVisible;
        await _setProperty('sub-visibility', visible ? 'yes' : 'no');
        _update((st) => st.copyWith(subtitlesVisible: visible));
      case LoadSubtitleFile(:final path):
        await player.setSubtitleTrack(SubtitleTrack.uri(path, title: p.basename(path)));
        await _setProperty('sub-visibility', 'yes');
        _update((st) => st.copyWith(subtitlesVisible: true));
      case SetSubtitleDelay(:final seconds):
        await _setSubtitleDelay(seconds);
      case SubtitleDelayRelative(:final delta):
        await _setSubtitleDelay(state.subtitleDelay + delta);
      case SetSubtitleScale(:final scale):
        final s = scale.clamp(PlaybackState.minSubtitleScale, PlaybackState.maxSubtitleScale);
        await _setProperty('sub-scale', s.toStringAsFixed(2));
        _update((st) => st.copyWith(subtitleScale: s));

      // Pistes audio
      case SetAudioTrack(:final id):
        await _selectAudio(id);

      // Boucle A-B
      case CycleAbLoop():
        await _cycleAbLoop(state);
      case ClearAbLoop():
        await _clearAbLoop();

      // Image
      case SetAspectMode(:final mode):
        // Appliqué par l'interface (ajustement du widget vidéo) : la texture
        // garde sa taille, et « Remplir » fonctionne réellement.
        _update((st) => st.copyWith(aspectMode: mode));
      case VideoZoomRelative(:final delta):
        final z = (state.videoZoom + delta)
            .clamp(PlaybackState.minVideoZoom, PlaybackState.maxVideoZoom);
        await _setProperty('video-zoom', z.toStringAsFixed(3));
        _update((st) => st.copyWith(videoZoom: z));
      case ResetVideoZoom():
        await _setProperty('video-zoom', '0');
        _update((st) => st.copyWith(videoZoom: 0));
      case RotateVideo(:final quarterTurns):
        final r = (state.videoRotation + quarterTurns) % 4;
        await _setProperty('video-rotate', '${r * 90}');
        _update((st) => st.copyWith(videoRotation: r));
      case SetVideoAdjust(:final adjust):
        final a = adjust.copyWith();
        await _applyAdjust(a);
        _update((st) => st.copyWith(videoAdjust: a));
      case ResetVideoAdjust():
        await _applyAdjust(VideoAdjust.neutral);
        _update((st) => st.copyWith(videoAdjust: VideoAdjust.neutral));

      // Égaliseur
      case SetEqualizerGains(:final gains):
        final g = Equalizer.normalise(gains);
        await _applyEqualizer(state.equalizerEnabled ? g : Equalizer.flat);
        _update((st) => st.copyWith(equalizerGains: g));
      case SetEqualizerPreset(:final preset):
        final g = Equalizer.presets[preset];
        if (g == null) return false;
        await _applyEqualizer(g);
        _update((st) => st.copyWith(equalizerGains: g, equalizerEnabled: true));
      case ToggleEqualizer():
        final enabled = !state.equalizerEnabled;
        await _applyEqualizer(enabled ? state.equalizerGains : Equalizer.flat);
        _update((st) => st.copyWith(equalizerEnabled: enabled));

      default:
        return false;
    }
    return true;
  }

  // --- Capture ----------------------------------------------------------------

  @override
  Future<Uint8List?> captureFrame() async {
    final state = _sink?.state;
    if (state == null || !state.hasVideo) return null;
    try {
      return await player.screenshot(format: 'image/png');
    } on Object {
      return null;
    }
  }

  // --- Transport --------------------------------------------------------------

  Future<void> _seekTo(Duration target) async {
    final duration = _sink?.state.duration ?? Duration.zero;
    var clamped = target.isNegative ? Duration.zero : target;
    if (duration > Duration.zero && clamped > duration) clamped = duration;
    // Retour visuel immédiat : la position est mise à jour avant que mpv confirme.
    _update((st) => st.copyWith(position: clamped));
    await player.seek(clamped);
    // Reprendre après un seek depuis la fin.
    if (_sink?.state.status == PlaybackStatus.ended) await player.play();
  }

  Future<void> _setVolume(double volume) async {
    final v = volume.clamp(PlaybackState.minVolume, PlaybackState.maxVolume);
    if (_sink?.state.muted ?? false) await _setMuted(false);
    await player.setVolume(v);
    _update((st) => st.copyWith(volume: v));
  }

  Future<void> _setMuted(bool muted) async {
    await _setProperty('mute', muted ? 'yes' : 'no');
    _update((st) => st.copyWith(muted: muted));
  }

  Future<void> _setSpeed(double speed) async {
    // Arrondi au pas de 0,25 puis bornage 0,25×–4×.
    final steps = (speed / PlaybackState.speedStep).round();
    final s = (steps * PlaybackState.speedStep)
        .clamp(PlaybackState.minSpeed, PlaybackState.maxSpeed);
    await player.setRate(s);
    // En lecture rapide, mpv peut sauter des images en retard dès le
    // décodage : le mouvement est moins fluide, mais l'image ne décroche pas.
    await _setProperty('framedrop', s >= 1.75 ? 'decoder+vo' : 'vo');
    _update((st) => st.copyWith(speed: s));
  }

  // --- Sous-titres et pistes --------------------------------------------------

  Future<void> _selectSubtitle(String? id) async {
    if (id == null) {
      await player.setSubtitleTrack(SubtitleTrack.no());
      _update((st) => st.copyWith(clearSubtitleTrack: true));
      return;
    }
    final track = _tracks.subtitle.where((t) => t.id == id).firstOrNull;
    if (track != null) {
      await player.setSubtitleTrack(track);
    } else if (File(id).existsSync()) {
      // Identifiant qui est un chemin : sous-titre externe pas encore chargé.
      await player.setSubtitleTrack(SubtitleTrack.uri(id, title: p.basename(id)));
    } else {
      return;
    }
    await _setProperty('sub-visibility', 'yes');
    _update((st) => st.copyWith(subtitleTrackId: id, subtitlesVisible: true));
  }

  Future<void> _selectAudio(String? id) async {
    if (id == null) {
      await player.setAudioTrack(AudioTrack.auto());
      _update((st) => st.copyWith(clearAudioTrack: true));
      return;
    }
    final track = _tracks.audio.where((t) => t.id == id).firstOrNull;
    if (track == null) return;
    await player.setAudioTrack(track);
    _update((st) => st.copyWith(audioTrackId: id));
  }

  Future<void> _setSubtitleDelay(double seconds) async {
    final d = seconds.clamp(PlaybackState.minSubtitleDelay, PlaybackState.maxSubtitleDelay);
    await _setProperty('sub-delay', d.toStringAsFixed(2));
    _update((st) => st.copyWith(subtitleDelay: d));
  }

  // --- Boucle A-B -------------------------------------------------------------

  /// A absent → A = position ; B absent → B = position ; les deux → effacer.
  /// mpv boucle lui-même entre `ab-loop-a` et `ab-loop-b`, à l'image près.
  Future<void> _cycleAbLoop(PlaybackState state) async {
    // Position exacte du moteur : celle de l'état est filtrée (six par seconde).
    if (state.loopA == null) {
      final a = player.state.position;
      await _setProperty('ab-loop-a', _seconds(a));
      _update((st) => st.copyWith(loopA: a));
    } else if (state.loopB == null) {
      final b = player.state.position;
      if (b <= state.loopA! + const Duration(milliseconds: 500)) {
        // Un point B avant A (ou collé à A) ne ferait pas une boucle.
        return;
      }
      await _setProperty('ab-loop-b', _seconds(b));
      _update((st) => st.copyWith(loopB: b));
    } else {
      await _clearAbLoop();
    }
  }

  Future<void> _clearAbLoop() async {
    await _setProperty('ab-loop-a', 'no');
    await _setProperty('ab-loop-b', 'no');
    _update((st) => st.copyWith(clearLoop: true));
  }

  static String _seconds(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(3);

  // --- Image ------------------------------------------------------------------

  /// Le ratio et le remplissage sont appliqués par l'interface. Côté mpv, on
  /// garde l'image telle quelle : changer le ratio y recréerait la texture
  /// (un éclair noir), et `panscan` n'a rien à rogner dans une texture qui a
  /// déjà le ratio de la vidéo.
  Future<void> _applyNeutralAspect() async {
    await _setProperty('video-aspect-override', AspectMode.auto.mpvAspect);
    await _setProperty('panscan', AspectMode.auto.mpvPanscan);
  }

  Future<void> _applyAdjust(VideoAdjust adjust) async {
    await _setProperty('brightness', adjust.brightness.round().toString());
    await _setProperty('contrast', adjust.contrast.round().toString());
    await _setProperty('saturation', adjust.saturation.round().toString());
  }

  // --- Égaliseur --------------------------------------------------------------

  /// Remplace la chaîne de filtres audio. Une chaîne vide retire tout filtre.
  Future<void> _applyEqualizer(List<double> gains) async {
    await _setProperty('af', Equalizer.filterFor(gains));
  }

  // --- Extraits ---------------------------------------------------------------

  /// Position du média au début de l'extrait en cours, point de départ du
  /// repli par le cache. `null` : aucun extrait commencé.
  Duration? _recordingFrom;

  /// Enregistrement d'extrait : propriété `stream-record` de mpv. Elle
  /// recopie les paquets lus par le démultiplexeur dans un fichier dont
  /// l'extension fixe le format, sans réencoder : qualité intacte et presque
  /// aucun coût processeur.
  ///
  /// La propriété est relue avant de répondre `true` : media_kit appelle
  /// `mpv_set_property_string` sans regarder son code de retour, si bien
  /// qu'une propriété refusée (version de mpv sans enregistrement, moteur
  /// libéré) passerait pour un succès et allumerait un voyant qui n'enregistre
  /// rien.
  @override
  Future<bool> startRecording(String path) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return false;
    final normalizedPath = path.replaceAll('\\', '/');
    try {
      await platform.setProperty('stream-record', normalizedPath);
      if ((await platform.getProperty('stream-record')).trim().isEmpty) return false;
      // Point de départ du repli : la position exacte du moteur, et non celle
      // de l'état, filtrée à six mises à jour par seconde.
      _recordingFrom = player.state.position;
      return true;
    } on Object {
      return false;
    }
  }

  /// Une chaîne vide ferme l'enregistreur, qui finalise le fichier.
  @override
  Future<void> stopRecording() => _setProperty('stream-record', '');

  /// Repli quand l'écriture au fil de l'eau n'a rien donné : `dump-cache`
  /// recopie dans [path] les paquets que le démultiplexeur garde en mémoire
  /// entre le début de l'extrait et la position actuelle.
  ///
  /// C'est le cas courant d'un fichier local : mpv le lit d'avance, la
  /// séquence est déjà en cache quand l'utilisateur lance l'extrait, et
  /// `stream-record` n'a plus aucun paquet neuf à recopier. La commande écrase
  /// le fichier et ne rend la main qu'une fois l'écriture finie.
  @override
  Future<bool> dumpRecording(String path) async {
    final platform = player.platform;
    final from = _recordingFrom;
    _recordingFrom = null;
    if (platform is! NativePlayer || from == null) return false;
    final to = player.state.position;
    // Rien ne s'est écoulé : il n'y a aucune séquence à écrire.
    if (to <= from) return false;
    final normalizedPath = path.replaceAll('\\', '/');
    try {
      await platform.command(['dump-cache', _seconds(from), _seconds(to), normalizedPath]);
      return true;
    } on Object {
      return false;
    }
  }



  @override
  Future<void> close() async {
    _opening = false;
    // Un extrait en cours ne doit pas continuer sur le fichier suivant.
    await stopRecording();
    await player.stop();
    _tracks = const Tracks();
    _sink?.update(
      (st) => st.copyWith(
        clearFile: true,
        status: PlaybackStatus.idle,
        position: Duration.zero,
        duration: Duration.zero,
        hasVideo: false,
        videoWidth: 0,
        videoHeight: 0,
        subtitleTracks: const [],
        audioTracks: const [],
        clearSubtitleTrack: true,
        clearAudioTrack: true,
        clearLoop: true,
        clearError: true,
      ),
    );
    _sink = null;
  }

  @override
  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await player.dispose();
  }
}
