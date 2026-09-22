import 'dart:async';
import 'dart:io';
import 'dart:ui' show Offset, Rect, Size;

import 'package:collection/collection.dart';

import '../commands/player_command.dart';
import '../commands/player_command_bus.dart';
import '../controllers/frame_capturer.dart';
import '../controllers/media_controller.dart';
import '../controllers/media_router.dart';
import '../controllers/stream_recorder.dart';
import '../models/app_preferences.dart';
import '../models/end_of_playback_mode.dart';
import '../models/history_entry.dart';
import '../models/media_file.dart';
import '../models/media_type.dart';
import '../models/playback_state.dart';
import '../models/playback_status.dart';
import '../models/recording_failure.dart';
import '../models/resume_offer.dart';
import '../models/window_sizes.dart';
import 'history_store.dart';
import 'playlist_service.dart';
import 'screenshot_service.dart';
import 'settings_store.dart';
import 'system_integration.dart';
import 'window_service.dart';

/// Chef d'orchestre de la lecture.
///
/// Écoute le [PlayerCommandBus], route chaque commande vers le bon
/// destinataire (fenêtre, playlist, contrôleur de média actif, ou lui-même) et
/// possède l'unique [PlaybackState] de l'application.
class PlaybackService implements PlaybackStateSink {
  PlaybackService({
    required PlayerCommandBus bus,
    required this.router,
    required this.window,
    required this.playlist,
    this.history,
    this.settings,
    this.screenshots,
    this.system = const NoopSystemIntegration(),
    this.recordingCheckDelay = const Duration(milliseconds: 150),
    PlaybackState initialState = const PlaybackState(),
  }) : _state = initialState {
    final store = settings;
    if (store != null) {
      // Ce que l'utilisateur a choisi survit d'une session à l'autre : mode de
      // fin de lecture, volume, vitesse, sous-titres, égaliseur, documents.
      final storedMode = store.endOfPlaybackMode;
      final prefs = store.preferences;
      final volume = prefs.startupVolume == StartupVolume.fixed
          ? prefs.fixedVolume
          : (store.lastVolume ?? _state.volume);
      _state = _state.copyWith(
        endMode: storedMode == null ? null : EndOfPlaybackMode.fromJson(storedMode),
        volume: volume.clamp(PlaybackState.minVolume, PlaybackState.maxVolume),
        speed: prefs.defaultSpeed,
        subtitleScale: prefs.subtitleScale,
        equalizerEnabled: prefs.equalizerEnabled,
        equalizerGains: prefs.equalizerGains,
        readingDark: prefs.readingDark,
        documentLayout: prefs.pdfLayout,
        alwaysOnTop: prefs.normalPlayerAlwaysOnTop,
      );
      if (prefs.normalPlayerAlwaysOnTop) {
        unawaited(window.setAlwaysOnTop(true));
      }
    }

    _subscription = bus.stream.listen(_onCommand);
    _playlistSubscription = playlist.stream.listen(_onPlaylistChanged);
    unawaited(history?.pruneExpired(preferences.historyRetentionDays));
  }

  /// Préférences courantes (valeurs par défaut sans stockage).
  AppPreferences get preferences => settings?.preferences ?? AppPreferences.defaults;

  /// Émet les préférences après chaque modification enregistrée.
  Stream<AppPreferences> get preferencesChanges => _preferencesChanges.stream;

  final StreamController<AppPreferences> _preferencesChanges =
      StreamController<AppPreferences>.broadcast();

  /// Sauvegarde différée des réglages suivis en direct (volume, égaliseur…) :
  /// un glissement de curseur produit des dizaines de changements.
  Timer? _preferencesSave;

  /// Routeur type → contrôleur.
  final MediaRouter router;

  /// Fenêtre native (plein écran, premier plan).
  final WindowService window;

  /// Panneau de dossier : scan, tri, navigation suivant/précédent.
  final PlaylistService playlist;

  /// Mémoire des positions de lecture. `null` désactive la reprise.
  final HistoryStore? history;

  /// Préférences persistantes (mode de fin de lecture). `null` : rien n'est
  /// mémorisé.
  final SettingsStore? settings;

  /// Intégration système (ouvrir l'emplacement d'un fichier).
  final SystemIntegration system;

  /// Enregistrement des captures d'écran. `null` désactive la capture.
  final ScreenshotService? screenshots;

  /// Géométrie, agrandissement et premier plan à rendre en quittant le
  /// mini-lecteur.
  Rect? _boundsBeforeMini;
  bool _maximizedBeforeMini = false;
  bool _alwaysOnTopBeforeMini = false;

  /// Fenêtre telle que l'utilisateur la voyait avant le mini-lecteur (l'écran
  /// entier si elle était agrandie) : le mini-lecteur se range dans son coin.
  Rect? _miniArea;

  /// Forme appliquée au mini-lecteur : ratio de l'image, 0 pour le bandeau.
  double _miniShape = 0;

  /// Un verrou de ratio est posé sur la fenêtre.
  bool _aspectLocked = false;

  /// Une remise en forme du mini-lecteur attend son tour dans la file.
  bool _miniRefitScheduled = false;

  /// Écart entre le mini-lecteur et les bords de la fenêtre d'avant.
  static const double _miniMargin = 24;

  late final StreamSubscription<DispatchedCommand> _subscription;
  late final StreamSubscription<Object?> _playlistSubscription;

  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();

  PlaybackState _state;
  MediaController? _active;

  /// Traitement séquentiel : les commandes s'exécutent dans l'ordre reçu.
  Future<void> _queue = Future<void>.value();

  /// Évite de réagir plusieurs fois à la même fin de fichier.
  bool _endHandled = false;

  /// Position mémorisée en attente d'être appliquée à l'ouverture, et le
  /// fichier qu'elle concerne : un dernier battement de position du fichier
  /// précédent ne doit pas la consommer à sa place.
  Duration? _pendingResume;
  String? _pendingResumePath;

  /// Même chose pour les documents : page (PDF) ou défilement (texte).
  int? _pendingResumePage;
  double? _pendingResumeScroll;

  @override
  PlaybackState get state => _state;

  /// Flux des états successifs (n'émet pas l'état initial).
  Stream<PlaybackState> get stream => _states.stream;

  /// Contrôleur actuellement en charge du fichier courant.
  MediaController? get activeController => _active;

  /// Se termine quand toutes les commandes déjà reçues ont été traitées.
  ///
  /// Les tests s'en servent pour attendre la fin d'un traitement ; la future
  /// télécommande pourra s'en servir pour accuser réception d'une commande.
  Future<void> get idle => _queue;

  @override
  void update(PlaybackState Function(PlaybackState) reducer) {
    if (_states.isClosed) return;
    final previous = _state;
    _state = reducer(_state);
    _states.add(_state);
    _reactToStateChange(previous, _state);
  }

  /// Réactions déclenchées par un changement d'état, et non par une commande :
  /// reprise de lecture, sauvegarde de la position, fin de fichier, forme du
  /// mini-lecteur.
  void _reactToStateChange(PlaybackState before, PlaybackState after) {
    // Appliquer la position mémorisée dès que la durée du bon fichier est
    // connue.
    final resume = _pendingResume;
    if (resume != null &&
        after.file?.path == _pendingResumePath &&
        after.duration > Duration.zero &&
        after.status != PlaybackStatus.loading) {
      _pendingResume = null;
      _pendingResumePath = null;
      if (resume < after.duration) {
        scheduleMicrotask(() => _active?.handle(SeekAbsolute(resume)));
      }
    }

    // Documents : dès que le document est prêt, revenir à la dernière page ou
    // position lue.
    if (after.isDocument &&
        after.status == PlaybackStatus.playing &&
        after.file?.path == _pendingResumePath) {
      final page = _pendingResumePage;
      final scroll = _pendingResumeScroll;
      _pendingResumePath = null;
      _pendingResumePage = null;
      _pendingResumeScroll = null;
      if (page != null && after.totalPages > 0 && page <= after.totalPages) {
        scheduleMicrotask(() => _active?.handle(GoToPage(page)));
      } else if (scroll != null) {
        scheduleMicrotask(() => _active?.handle(ScrollTo(scroll)));
      }
    }

    // Documents : mémoriser page et défilement à chaque changement. Ce sont
    // des événements rares (un tour de page, une fin de défilement), pas un
    // battement continu.
    if (preferences.rememberPlaybackState &&
        after.isDocument &&
        after.file != null &&
        before.file?.path == after.file!.path &&
        after.status == PlaybackStatus.playing &&
        _pendingResumePath == null &&
        (before.status != PlaybackStatus.playing ||
            before.currentPage != after.currentPage ||
            before.scrollFraction != after.scrollFraction)) {
      unawaited(
        history?.saveDocumentPosition(
          after.file!.path,
          page: after.currentPage > 0 ? after.currentPage : null,
          pageCount: after.totalPages > 0 ? after.totalPages : null,
          scrollFraction: after.scrollFraction,
        ),
      );
    }

    // Sauvegarder la progression au fil de la lecture toutes les 5 secondes
    // au lieu d'une fois par minute, pour ne rien perdre en cas d'interruption.
    if (preferences.rememberPlaybackState &&
        !after.isDocument &&
        before.file?.path == after.file?.path &&
        after.file != null &&
        after.duration > Duration.zero &&
        (after.position.inSeconds - before.position.inSeconds).abs() >= 5) {
      unawaited(
        history?.savePosition(
          after.file!.path,
          position: after.position,
          duration: after.duration,
        ),
      );
    }

    // Réglages suivis en direct : ce que l'utilisateur change pendant la
    // lecture devient sa préférence (dernier volume, taille des sous-titres,
    // égaliseur, mode sombre de lecture, mise en page, taille du texte).
    if (settings != null &&
        (before.volume != after.volume ||
            before.equalizerEnabled != after.equalizerEnabled ||
            !_listEquals(before.equalizerGains, after.equalizerGains) ||
            before.subtitleScale != after.subtitleScale ||
            before.readingDark != after.readingDark ||
            before.documentLayout != after.documentLayout ||
            (after.mediaType == MediaType.text && before.zoom != after.zoom))) {
      _schedulePreferencesSave();
    }

    // On réagit à la TRANSITION vers « terminé », pas à son niveau : tant que
    // le fichier suivant n'a pas commencé, d'autres mises à jour d'état (la
    // playlist qui change de fichier courant, par exemple) arrivent avec un
    // statut encore « terminé », et ne doivent pas relancer l'enchaînement.
    final justEnded = after.status == PlaybackStatus.ended &&
        before.status != PlaybackStatus.ended;
    if (justEnded && !_endHandled) {
      _endHandled = true;
      final path = after.file?.path;
      final store = history;
      if (path != null && store != null) {
        unawaited(
          store.markCompleted(path).then((_) => playlist.refreshEntry(path)),
        );
      }
      _scheduleEndOfPlayback();
    } else if (after.status != PlaybackStatus.ended) {
      _endHandled = false;
    }

    // Mini-lecteur : la fenêtre suit la forme du média. Les dimensions de
    // l'image arrivent après l'ouverture et changent avec le fichier suivant.
    // La remise en forme attend son tour dans la file : elle ne se mêle pas à
    // une entrée, une sortie ou un plein écran en cours. Les battements de
    // position, eux, ne changent pas la forme : aucun appel à la fenêtre.
    if (after.miniPlayer && !_miniRefitScheduled) {
      final shape = _miniShapeFor(after);
      if (shape != null && !_sameShape(shape, _miniShape)) {
        _miniRefitScheduled = true;
        _queue = _queue.then((_) => _refitMiniPlayer()).catchError((Object _) {
          // Une fenêtre qui refuse sa nouvelle forme garde l'ancienne : la
          // lecture n'est pas en cause.
        });
      }
    }
  }

  void _onPlaylistChanged(Object? _) {
    // La projection playlist de PlaybackState reste synchronisée : c'est elle
    // que la future télécommande recevra.
    final visible = playlist.state.visiblePaths;
    final index = playlist.state.currentIndex;
    if (_state.playlist.length == visible.length &&
        _state.playlistIndex == index &&
        _listEquals(_state.playlist, visible)) {
      return;
    }
    update((st) => st.copyWith(playlist: visible, playlistIndex: index));
  }

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // --- Préférences -------------------------------------------------------------

  void _schedulePreferencesSave() {
    _preferencesSave?.cancel();
    _preferencesSave = Timer(const Duration(milliseconds: 500), _savePreferencesNow);
  }

  /// Recopie dans les préférences les réglages suivis en direct.
  Future<void> _savePreferencesNow() async {
    _preferencesSave?.cancel();
    _preferencesSave = null;
    final store = settings;
    if (store == null) return;

    final s = _state;
    if (store.lastVolume != s.volume) await store.setLastVolume(s.volume);

    final current = store.preferences;
    final next = current.copyWith(
      equalizerEnabled: s.equalizerEnabled,
      equalizerGains: s.equalizerGains,
      subtitleScale: s.subtitleScale,
      readingDark: s.readingDark,
      pdfLayout: s.documentLayout,
      textScale: s.mediaType == MediaType.text ? s.zoom : null,
    );
    if (next != current) {
      await store.setPreferences(next);
      if (!_preferencesChanges.isClosed) _preferencesChanges.add(next);
    }
  }

  /// Applique des préférences venues de l'écran Paramètres.
  ///
  /// Ce qui est en cours est aligné AVANT l'enregistrement : la sauvegarde
  /// différée des réglages suivis en direct recopiera alors les mêmes
  /// valeurs, au lieu d'annuler le changement.
  Future<void> _applyPreferences(AppPreferences next) async {
    await _alignLiveState(next);
    await settings?.setPreferences(next);
    if (!_preferencesChanges.isClosed) _preferencesChanges.add(next);
  }

  Future<void> _alignLiveState(AppPreferences p) async {
    final active = _active;

    Future<bool> tryHandle(PlayerCommand command) async =>
        await active?.handle(command) ?? false;

    if (_state.subtitleScale != p.subtitleScale &&
        !await tryHandle(SetSubtitleScale(p.subtitleScale))) {
      update((st) => st.copyWith(subtitleScale: p.subtitleScale));
    }

    if (!_listEquals(_state.equalizerGains, p.equalizerGains) ||
        _state.equalizerEnabled != p.equalizerEnabled) {
      var handled = await tryHandle(SetEqualizerGains(p.equalizerGains));
      if (handled && _state.equalizerEnabled != p.equalizerEnabled) {
        handled = await tryHandle(const ToggleEqualizer());
      }
      if (!handled) {
        update(
          (st) => st.copyWith(
            equalizerGains: p.equalizerGains,
            equalizerEnabled: p.equalizerEnabled,
          ),
        );
      }
    }

    if (_state.readingDark != p.readingDark &&
        !await tryHandle(const ToggleReadingDarkMode())) {
      update((st) => st.copyWith(readingDark: p.readingDark));
    }

    if (_state.documentLayout != p.pdfLayout &&
        !await tryHandle(SetDocumentLayout(p.pdfLayout))) {
      update((st) => st.copyWith(documentLayout: p.pdfLayout));
    }

    if (_state.mediaType == MediaType.text && _state.zoom != p.textScale) {
      await tryHandle(SetZoom(p.textScale));
    }

    final shouldBeOnTop = _state.miniPlayer ? p.miniPlayerAlwaysOnTop : p.normalPlayerAlwaysOnTop;
    if (_state.alwaysOnTop != shouldBeOnTop) {
      await window.setAlwaysOnTop(shouldBeOnTop);
      update((st) => st.copyWith(alwaysOnTop: shouldBeOnTop));
    }
  }


  // --- Reprise de lecture --------------------------------------------------------

  /// Ce qu'il y aurait à reprendre pour ce fichier, selon son type.
  static ResumeOffer? _offerFrom(
    MediaType type,
    HistoryEntry? entry, {
    bool remember = true,
    int retentionDays = 0,
    DateTime? now,
  }) {
    if (entry == null || !remember) return null;
    if (retentionDays > 0) {
      final days = (now ?? DateTime.now()).difference(entry.lastOpened).inDays;
      if (days >= retentionDays) return null;
    }
    if (type.isDocument) {
      final page = entry.resumePage;
      if (page != null) return ResumeOffer(page: page);
      final scroll = entry.resumeScroll;
      return scroll == null ? null : ResumeOffer(scroll: scroll);
    }
    final position = entry.resumePosition;
    return position == null ? null : ResumeOffer(position: position);
  }

  void _clearPendingResume() {
    _pendingResume = null;
    _pendingResumePath = null;
    _pendingResumePage = null;
    _pendingResumeScroll = null;
  }

  /// Applique une reprise : tout de suite si le fichier est prêt, sinon dès
  /// qu'il le sera (voir [_reactToStateChange]).
  Future<void> _resumeTo(ResumeOffer offer) async {
    final path = _state.file?.path;
    if (path == null) return;

    if (_state.isDocument) {
      if (_state.status == PlaybackStatus.playing) {
        final page = offer.page;
        final scroll = offer.scroll;
        if (page != null && (_state.totalPages == 0 || page <= _state.totalPages)) {
          await _active?.handle(GoToPage(page));
        } else if (scroll != null) {
          await _active?.handle(ScrollTo(scroll));
        }
      } else {
        _pendingResumePage = offer.page;
        _pendingResumeScroll = offer.scroll;
        _pendingResumePath = path;
      }
      return;
    }

    final position = offer.position;
    if (position == null) return;
    final ready = _state.duration > Duration.zero && _state.status != PlaybackStatus.loading;
    if (ready) {
      if (position < _state.duration) await _active?.handle(SeekAbsolute(position));
    } else {
      _pendingResume = position;
      _pendingResumePath = path;
    }
  }

  void _onCommand(DispatchedCommand dispatched) {
    _queue = _queue.then((_) => _handle(dispatched.command)).catchError((Object e) {
      update(
        (st) => st.copyWith(
          status: PlaybackStatus.error,
          error: PlaybackError(PlaybackErrorCode.unknown, detail: e.toString()),
        ),
      );
    });
  }

  Future<void> _handle(PlayerCommand command) async {
    switch (command) {
      case OpenFile(:final path):
        await openPath(path);
      case OpenFolder(:final path):
        await openFolder(path);
      case Stop():
        await _closeActive();
      case NextFile():
        final path = playlist.nextPath();
        if (path != null) await openPath(path);
      case PreviousFile():
        final path = playlist.previousPath();
        if (path != null) await openPath(path);
      case RescanFolder():
        // Traitée par PlaylistService ; rien à faire ici.
        break;
      case ToggleFullscreen():
        // Le plein écran se prend depuis la fenêtre entière : pris depuis le
        // mini-lecteur, il en garderait la mise en page compacte.
        if (_state.miniPlayer) await _setMiniPlayer(false);
        await _setFullscreen(!_state.fullscreen);
      case ExitFullscreen():
        if (_state.fullscreen) await _setFullscreen(false);
      case ToggleAlwaysOnTop(:final forMiniPlayer):
        final targetMini = forMiniPlayer ?? _state.miniPlayer;
        if (targetMini) {
          final next = !(settings?.preferences.miniPlayerAlwaysOnTop ?? true);
          await _applyPreferences(preferences.copyWith(miniPlayerAlwaysOnTop: next));
          if (_state.miniPlayer) {
            await window.setAlwaysOnTop(next);
            update((st) => st.copyWith(alwaysOnTop: next));
          }
        } else {
          final next = !(settings?.preferences.normalPlayerAlwaysOnTop ?? false);
          await _applyPreferences(preferences.copyWith(normalPlayerAlwaysOnTop: next));
          if (!_state.miniPlayer) {
            await window.setAlwaysOnTop(next);
            update((st) => st.copyWith(alwaysOnTop: next));
          }
        }
      case SetLoopMode(:final mode):

        update((st) => st.copyWith(endMode: mode));
        unawaited(settings?.setEndOfPlaybackMode(mode.name));
      case CycleLoopMode():
        final mode = _state.endMode.nextInCycle;
        update((st) => st.copyWith(endMode: mode));
        unawaited(settings?.setEndOfPlaybackMode(mode.name));
      case RevealInFolder(:final path):
        await system.revealInFileManager(path);
      case ClearHistory():
        await history?.clear();
        _refreshPlaylistBadges();
      case ClearRecentFiles():
        await history?.clearRecent();
      case ClearResumePositions():
        await history?.clearPositions();
        _refreshPlaylistBadges();
      case AcceptResume():
        final offer = _state.resumeOffer;
        if (offer != null) {
          update((st) => st.copyWith(clearResumeOffer: true));
          await _resumeTo(offer);
        }
      case DeclineResume():
        if (_state.resumeOffer != null) {
          update((st) => st.copyWith(clearResumeOffer: true));
        }
      case UpdatePreferences(:final changes):
        await _applyPreferences(preferences.merge(changes));
      case SetScreenshotFolder(:final path):
        await settings?.setScreenshotFolder(path);
      case SetRecordingFolder(:final path):
        await settings?.setRecordingFolder(path);
      case TakeScreenshot():

        await _takeScreenshot();
      case ToggleRecording():
        await (_state.recording ? _stopRecording() : _startRecording());
      case ToggleMiniPlayer():
        await _setMiniPlayer(!_state.miniPlayer);
      case SetVolume() || VolumeRelative() || ToggleMute() when _active == null:
        if (!_state.hasFile || _state.mediaType.isAv) {
          _applyVolumeWithoutController(command);
        }
      default:
        // Toute autre commande concerne le média courant.
        await _active?.handle(command);
    }
  }

  void _applyVolumeWithoutController(PlayerCommand command) {
    switch (command) {
      case SetVolume(:final volume):
        update((st) => st.copyWith(volume: _clampVolume(volume), muted: false));
      case VolumeRelative(:final delta):
        update(
          (st) => st.copyWith(
            volume: _clampVolume(st.volume + delta),
            muted: false,
          ),
        );
      case ToggleMute():
        update((st) => st.copyWith(muted: !st.muted));
      default:
        break;
    }
  }

  static double _clampVolume(double value) =>
      value.clamp(PlaybackState.minVolume, PlaybackState.maxVolume);

  /// Les pastilles du panneau reflètent l'historique : on les relit.
  void _refreshPlaylistBadges() {
    for (final entry in playlist.state.entries) {
      playlist.refreshEntry(entry.path);
    }
  }

  Future<void> _setFullscreen(bool value) async {
    await window.setFullscreen(value);
    update((st) => st.copyWith(fullscreen: value));
  }

  /// Capture l'image affichée et l'enregistre. Le chemin est publié dans
  /// l'état : c'est lui que l'OSD montre.
  Future<void> _takeScreenshot() async {
    // `FrameCapturer` n'est pas un sous-type de `MediaController` : Dart ne
    // promeut pas la variable directement, d'où le passage par `Object?`.
    final Object? capturer = _active;
    final store = screenshots;
    final file = _state.file;
    // L'état décrit le résultat de CETTE tentative : sans cela, une capture
    // impossible (fichier audio) afficherait le chemin de la précédente.
    update((st) => st.copyWith(clearLastScreenshot: true, screenshotFailed: false));
    if (capturer is! FrameCapturer || store == null || file == null) return;
    final png = await capturer.captureFrame();
    if (png == null) return;
    try {
      final path = await store.save(png, mediaPath: file.path, position: _state.position);
      update((st) => st.copyWith(lastScreenshot: path));
    } on FileSystemException {
      // Dossier inaccessible : la lecture continue, l'OSD le signale, et le
      // dossier se change dans les paramètres.
      update((st) => st.copyWith(screenshotFailed: true));
    }
  }

  /// Mini-lecteur : fenêtre compacte toujours au premier plan, à la forme de
  /// l'image (un bandeau pour un son seul). Géométrie, agrandissement et
  /// premier plan sont mémorisés pour être rendus à la sortie.
  ///
  /// Appelé depuis la file de commandes (bascule, plein écran, ouverture d'un
  /// document) : une entrée et une sortie rapprochées ne s'entremêlent pas.
  Future<void> _setMiniPlayer(bool enabled) async {
    if (enabled == _state.miniPlayer) return;
    await (enabled ? _enterMiniPlayer() : _exitMiniPlayer());
  }

  Future<void> _enterMiniPlayer() async {
    if (_state.fullscreen) await _setFullscreen(false);
    final maximized = await window.isMaximized();
    final visible = await window.getBounds();
    if (maximized) await window.setMaximized(false);
    _maximizedBeforeMini = maximized;
    // Une fenêtre agrandie est d'abord rendue à sa taille normale : c'est
    // celle-là qu'on restaure avant de l'agrandir de nouveau, pour que la
    // désagrandir plus tard la ramène à sa place.
    _boundsBeforeMini = maximized ? await window.getBounds() : visible;
    _miniArea = visible;
    _alwaysOnTopBeforeMini = _state.alwaysOnTop;

    // Sans dimensions d'image (son seul, ou vidéo qui démarre) : le bandeau.
    // Il prendra la forme de l'image dès qu'elle sera connue.
    final shape = _miniShapeFor(_state) ?? 0.0;
    final size = _miniSize(shape, longSide: settings?.miniLongSide);
    final origin = settings?.miniPosition ??
        Offset(
          visible.right - size.width - _miniMargin,
          visible.bottom - size.height - _miniMargin,
        );
    final miniOnTop = settings?.preferences.miniPlayerAlwaysOnTop ?? true;
    await _applyMiniShape(shape, origin & size);
    await window.setAlwaysOnTop(miniOnTop);
    update((st) => st.copyWith(miniPlayer: true, alwaysOnTop: miniOnTop));
  }

  Future<void> _exitMiniPlayer() async {
    // Le verrou de ratio d'abord : sous Linux, il rognerait la taille rendue.
    await window.setAspectRatio(0);
    _aspectLocked = false;
    await window.setMinimumSize(WindowSizes.mainMinimum);
    // Un mini-lecteur agrandi entre-temps par le système (Win+↑) redevient
    // d'abord normal : la géométrie rendue ne s'appliquerait pas à une
    // fenêtre agrandie.
    if (await window.isMaximized()) await window.setMaximized(false);
    final previous = _boundsBeforeMini;
    if (previous != null) await window.setBounds(previous);
    if (_maximizedBeforeMini) await window.setMaximized(true);
    final normalOnTop = settings?.preferences.normalPlayerAlwaysOnTop ?? _alwaysOnTopBeforeMini;
    await window.setAlwaysOnTop(normalOnTop);
    update((st) => st.copyWith(miniPlayer: false, alwaysOnTop: normalOnTop));
    _boundsBeforeMini = null;

    _maximizedBeforeMini = false;
    _miniArea = null;
  }

  /// Rend au mini-lecteur la forme du média courant : image d'un autre ratio,
  /// passage du son à l'image ou l'inverse.
  Future<void> _refitMiniPlayer() async {
    _miniRefitScheduled = false;
    if (_states.isClosed || !_state.miniPlayer) return;
    final shape = _miniShapeFor(_state);
    if (shape == null || _sameShape(shape, _miniShape)) return;
    final current = await window.getBounds();
    // D'une image à l'autre, le grand côté choisi à la souris est gardé ;
    // venant du bandeau, l'image reprend celui des réglages.
    final longSide = _miniShape > 0 ? current.longestSide : settings?.miniLongSide;
    final size = _miniSize(shape, longSide: longSide);
    await _applyMiniShape(shape, _resizeAnchored(current, size, _miniArea ?? current));
  }

  /// Donne au mini-lecteur la forme [shape] (voir [_miniShapeFor]) dans
  /// [bounds]. Le verrou de ratio est levé pendant le changement : sous Linux,
  /// le gestionnaire de fenêtres l'applique aussi aux tailles demandées par le
  /// programme, et rognerait la nouvelle à l'ancien ratio.
  Future<void> _applyMiniShape(double shape, Rect bounds) async {
    _miniShape = shape;
    if (_aspectLocked) {
      await window.setAspectRatio(0);
      _aspectLocked = false;
    }
    await window.setMinimumSize(_miniMinimum(shape));
    await window.setBounds(bounds);
    if (shape > 0 && _state.hasVideo && _state.videoAspect != null) {
      await window.setAspectRatio(shape);
      _aspectLocked = true;
    }
  }

  /// Forme voulue du mini-lecteur pour [s] : le ratio de l'image s'il est
  /// connu, 0 (bandeau) pour un son seul. `null` pour une vidéo dont l'image
  /// n'est pas encore connue : la forme actuelle est gardée, sans passer par
  /// le bandeau entre deux vidéos.
  static double? _miniShapeFor(PlaybackState s) {
    final aspect = s.videoAspect;
    if (aspect != null) return aspect;
    if (s.mediaType == MediaType.image) return 16.0 / 10.0;
    if (s.isDocument) return 4.0 / 3.0;
    return s.hasVideo ? null : 0.0;
  }

  /// Deux ratios qu'aucun redimensionnement ne distinguerait.
  static bool _sameShape(double a, double b) => (a - b).abs() < 1e-3;

  static Size _miniSize(double shape, {double? longSide}) => shape > 0
      ? WindowSizes.miniVideoSize(shape, longSide: longSide)
      : WindowSizes.miniAudio;

  static Size _miniMinimum(double shape) =>
      shape > 0 ? WindowSizes.miniVideoMinimum(shape) : WindowSizes.miniAudioMinimum;

  /// [current] redimensionné à [size] en gardant le coin le plus proche du
  /// coin correspondant de [area] : un mini-lecteur rangé en bas à droite y
  /// reste en changeant de forme, au lieu de déborder sous le bord de l'écran.
  static Rect _resizeAnchored(Rect current, Size size, Rect area) {
    final left = current.center.dx > area.center.dx ? current.right - size.width : current.left;
    final top = current.center.dy > area.center.dy ? current.bottom - size.height : current.top;
    return Offset(left, top) & size;
  }

  /// Ouvre un fichier : scan du dossier parent, choix du contrôleur, reprise
  /// éventuelle, puis lecture.
  ///
  /// La lecture ne dépend jamais du scan : celui-ci se poursuit en arrière-plan.
  Future<void> openPath(String path) async {
    // Un extrait en cours s'arrête avec son fichier : il ne continue pas sur
    // le suivant.
    await _stopRecording();
    await _savePositionOfCurrentFile();

    // Mémorise le chemin pour la restauration de la session au démarrage
    unawaited(settings?.setLastOpenPath(path));

    final type = MediaRouter.typeForPath(path);
    final file = MediaFile(path: path, type: type);
    final controller = router.controllerFor(type);

    // Le mini-lecteur affiche désormais vidéos, audios, images et documents :
    // seul un type inconnu ou invalide provoque la reprise de la fenêtre entière.
    if (_state.miniPlayer && type == MediaType.unknown) await _setMiniPlayer(false);

    playlist.setCurrent(path);
    if (!path.startsWith('http://') && !path.startsWith('https://')) {
      unawaited(playlist.ensureFolderFor(path));
    }

    if (controller == null) {
      await _closeActive(clearCurrent: false);
      update(
        (st) => st.copyWith(
          file: file,
          status: PlaybackStatus.error,
          error: const PlaybackError(PlaybackErrorCode.unsupportedFormat),
        ),
      );
      return;
    }

    if (_active != null && !identical(_active, controller)) {
      await _active!.close();
    }
    _active = controller;

    // Reprise : automatique, proposée, ou jamais, selon les préférences.
    final offer = _offerFrom(
      type,
      history?.entryFor(path),
      remember: preferences.rememberPlaybackState,
      retentionDays: preferences.historyRetentionDays,
    );
    final policy = preferences.resumePolicy;
    _clearPendingResume();
    final resumePage = (offer != null && policy == ResumePolicy.auto) ? offer.page : null;
    final resumeScroll = (offer != null && policy == ResumePolicy.auto) ? offer.scroll : null;
    if (offer != null && policy == ResumePolicy.auto) {
      _pendingResume = offer.position;
      _pendingResumePage = offer.page;
      _pendingResumeScroll = offer.scroll;
      _pendingResumePath = path;
    }
    update((st) => st.copyWith(
      file: file,
      status: PlaybackStatus.loading,
      position: Duration.zero,
      duration: Duration.zero,
      currentPage: resumePage ?? (type == MediaType.pdf ? 1 : 0),
      totalPages: 0,
      scrollFraction: resumeScroll ?? 0.0,
      clearResumeOffer: true,
      clearError: true,
    ));

    // Inscrit le fichier dans les récents dès maintenant, avant même que la
    // lecture ait commencé.
    await history?.touch(path);

    await controller.open(file, this);

    if (offer != null && policy == ResumePolicy.ask && _state.file?.path == path) {
      update((st) => st.copyWith(resumeOffer: offer));
    }
  }

  /// Ouvre un dossier : scan, puis lecture du premier fichier de la liste, dans
  /// l'ordre affiché par le panneau.
  ///
  /// Un dossier introuvable et un dossier sans média sont deux situations
  /// différentes pour l'utilisateur : chacune a son message.
  Future<void> openFolder(String path) async {
    await playlist.scanFolder(path);
    final first = playlist.state.visiblePaths.firstOrNull;
    if (first != null) {
      await openPath(first);
      return;
    }

    final exists = await folderExists(path);
    update(
      (st) => st.copyWith(
        status: PlaybackStatus.error,
        error: PlaybackError(
          exists ? PlaybackErrorCode.emptyFolder : PlaybackErrorCode.fileNotFound,
        ),
      ),
    );
  }

  /// Isolé pour pouvoir être remplacé dans les tests.
  Future<bool> folderExists(String path) => Directory(path).exists();

  /// Décide quoi faire quand le fichier courant se termine.
  ///
  /// Passe par la file de commandes : sans cela, l'enchaînement automatique
  /// s'exécuterait en parallèle d'une commande de l'utilisateur, et deux
  /// ouvertures pourraient se chevaucher.
  void _scheduleEndOfPlayback() {
    _queue = _queue.then((_) => _handleEndOfPlayback()).catchError((Object e) {
      update(
        (st) => st.copyWith(
          status: PlaybackStatus.error,
          error: PlaybackError(PlaybackErrorCode.unknown, detail: e.toString()),
        ),
      );
    });
  }

  Future<void> _handleEndOfPlayback() async {
    await _stopRecording();
    final mode = _state.endMode;
    final next = playlist.nextForEndMode(mode);

    // Fin de dossier, ou mode « s'arrêter » : on ne fait rien de plus.
    if (next == null) return;

    if (next == _state.file?.path && mode == EndOfPlaybackMode.repeatOne) {
      // Rejouer sans repasser par une ouverture complète.
      await _active?.handle(const SeekAbsolute(Duration.zero));
      await _active?.handle(const Play());
      _endHandled = false;
      return;
    }
    await openPath(next);
  }

  Future<void> _savePositionOfCurrentFile() async {
    final file = _state.file;
    final store = history;
    if (file == null || store == null || !preferences.rememberPlaybackState) return;
    if (_state.isDocument) {
      await store.saveDocumentPosition(
        file.path,
        page: _state.currentPage > 0 ? _state.currentPage : null,
        pageCount: _state.totalPages > 0 ? _state.totalPages : null,
        scrollFraction: _state.scrollFraction,
      );
      playlist.refreshEntry(file.path);
      return;
    }
    if (_state.status == PlaybackStatus.ended) return;
    if (_state.duration <= Duration.zero) return;
    await store.savePosition(
      file.path,
      position: _state.position,
      duration: _state.duration,
    );
    playlist.refreshEntry(file.path);
  }

  Future<void> _closeActive({bool clearCurrent = true}) async {
    await _stopRecording();
    await _savePositionOfCurrentFile();
    final active = _active;
    _active = null;
    _clearPendingResume();
    if (_state.resumeOffer != null) {
      update((st) => st.copyWith(clearResumeOffer: true));
    }
    if (clearCurrent) playlist.setCurrent(null);
    if (active != null) {
      await active.close();
    } else {
      update(
        (st) => st.copyWith(
          clearFile: true,
          status: PlaybackStatus.idle,
          clearError: true,
        ),
      );
    }
  }

  // --- Extraits ----------------------------------------------------------

  /// Délai entre deux vérifications du fichier d'un extrait arrêté.
  /// Surchargeable dans les tests.
  final Duration recordingCheckDelay;

  /// En dessous de cette taille, un fichier d'extrait ne contient que l'en-tête
  /// de son conteneur : mpv l'écrit dès qu'il ouvre le fichier, y compris quand
  /// il renonce juste après (piste qu'il ne sait pas recopier telle quelle).
  /// Un tel fichier ne s'ouvre pas ; l'annoncer serait pire que de le dire
  /// manqué, donc on tente d'abord le repli par le cache.
  static const int _headerOnlyBytes = 4096;

  /// Commence un extrait du média audio ou vidéo en cours, dans le dossier
  /// et sous le motif de nom des captures.
  ///
  /// Un extrait impossible est refusé tout de suite, avec sa raison : mieux
  /// vaut un message qu'un voyant rouge devant un fichier qui ne s'écrit pas.
  Future<void> _startRecording() async {
    // Comme pour la capture : passage par `Object?` pour la promotion de type.
    final Object? recorder = _active;
    final store = screenshots;
    final file = _state.file;
    // Sans média ouvert (ou sans dossier de destination configuré), la
    // commande n'a rien à refuser : elle ne fait rien.
    if (file == null || store == null) return;

    if (recorder is! StreamRecorder || !file.type.isAv) {
      _failRecording(RecordingFailure.unsupportedMedia);
      return;
    }
    // Un extrait avance au rythme de la lecture : à l'arrêt, en pause ou en
    // erreur, le moteur n'écrirait rien du tout.
    if (_state.status != PlaybackStatus.playing) {
      _failRecording(RecordingFailure.notPlaying);
      return;
    }

    update(
      (st) => st.copyWith(
        recordingFailure: RecordingFailure.none,
        clearLastRecording: true,
      ),
    );

    final String path;
    try {
      path = await store.recordingPath(
        mediaPath: file.path,
        audioOnly: !_state.hasVideo,
        position: _state.position,
      );
    } on FileSystemException {
      // Dossier des captures inaccessible : même message qu'une capture.
      _failRecording(RecordingFailure.folderUnavailable);
      return;
    }

    if (!await recorder.startRecording(path)) {
      _failRecording(RecordingFailure.engineRefused);
      return;
    }
    update((st) => st.copyWith(recordingPath: path, recordingStartedAt: DateTime.now()));
  }

  void _failRecording(RecordingFailure reason) {
    update((st) => st.copyWith(recordingFailure: reason, clearLastRecording: true));
  }

  /// Arrête l'extrait en cours, s'il y en a un, et vérifie qu'il a bien été
  /// écrit. Un fichier resté vide est supprimé et l'échec est signalé avec sa
  /// raison : un extrait qui n'existe pas ne doit pas être annoncé.
  ///
  /// Entre l'arrêt et la vérification, le repli : l'enregistrement au fil de
  /// l'eau ne recopie que les paquets nouvellement lus, et un fichier local
  /// déjà en cache n'en fournit aucun. L'enregistreur réécrit alors le fichier
  /// depuis ce cache. Le repli vaut aussi pour un fichier réduit à son en-tête
  /// (voir [_headerOnlyBytes]) : mpv l'écrit avant de savoir s'il saura
  /// recopier les pistes, et l'annoncer donnerait un extrait qui ne s'ouvre pas.
  Future<void> _stopRecording() async {
    final path = _state.recordingPath;
    if (path == null) return;
    final Object? recorder = _active;
    if (recorder is StreamRecorder) await recorder.stopRecording();

    var written = await _recordedBytes(path, attempts: 4);
    // Rien du tout, ou un simple en-tête : le cache du moteur tient peut-être
    // la séquence que l'écriture au fil de l'eau n'a pas eue.
    if (written <= _headerOnlyBytes &&
        recorder is StreamRecorder &&
        await recorder.dumpRecording(path)) {
      written = await _recordedBytes(path, attempts: 10);
    }
    // On ne jette que ce qui est vide : un extrait court reste un extrait.
    final saved = written > 0;
    if (!saved) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } on FileSystemException {
        // Fichier vide impossible à retirer : sans conséquence.
      }
    }
    update(
      (st) => st.copyWith(
        clearRecording: true,
        lastRecording: saved ? path : null,
        clearLastRecording: !saved,
        recordingFailure: saved ? RecordingFailure.none : RecordingFailure.nothingRecorded,
      ),
    );
  }

  /// Taille du fichier d'un extrait arrêté. mpv le finalise juste après
  /// l'arrêt : on lui laisse un court délai, et on répond dès qu'il dépasse la
  /// taille d'un simple en-tête, puisqu'il ne grandira plus que de contenu.
  Future<int> _recordedBytes(String path, {required int attempts}) async {
    var size = 0;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final f = File(path);
      if (await f.exists()) size = await f.length();
      if (size > _headerOnlyBytes) return size;
      // Aucune attente après le dernier essai : elle ne changerait rien.
      if (attempt < attempts - 1) await Future<void>.delayed(recordingCheckDelay);
    }
    return size;
  }

  /// Interrompt immédiatement et sans délai la lecture en cours.
  Future<void> stopImmediately() async {
    await _savePositionOfCurrentFile();
    final active = _active;
    if (active != null) {
      await active.close();
    }
  }

  /// Libère ce service. Les contrôleurs de média ne sont pas libérés ici :
  /// leur cycle de vie appartient au provider qui les a créés.
  Future<void> dispose() async {
    await _subscription.cancel();
    await _playlistSubscription.cancel();
    // Un extrait en cours est finalisé : le fichier resterait sinon illisible.
    await _stopRecording();
    // Une sauvegarde de réglages en attente est faite tout de suite, pour ne
    // pas perdre le dernier volume à la fermeture.
    if (_preferencesSave != null) await _savePreferencesNow();
    await _states.close();
    await _preferencesChanges.close();
  }
}
