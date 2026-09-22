import 'dart:async';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../commands/player_command.dart';
import '../commands/player_command_bus.dart';
import '../controllers/media_router.dart';
import '../models/end_of_playback_mode.dart';
import '../models/media_file.dart';
import '../models/playlist_entry.dart';
import '../models/playlist_sort.dart';
import '../models/playlist_state.dart';
import 'folder_scanner.dart';
import 'history_store.dart';
import 'settings_store.dart';

/// La fonctionnalité signature d'OMNIA : dès qu'un fichier est ouvert, le
/// dossier parent est scanné et tous ses fichiers lisibles apparaissent dans
/// le panneau latéral.
///
/// Le scan est asynchrone et hors du fil d'exécution de l'interface : la
/// lecture démarre sans l'attendre. Un compteur de génération fait qu'un scan
/// dépassé (l'utilisateur a déjà ouvert un autre dossier) est ignoré à son
/// retour au lieu d'écraser la liste courante.
class PlaylistService {
  PlaylistService({
    required PlayerCommandBus bus,
    required this.scanner,
    this.history,
    this.settings,
    this.isPlayable,
    Random? random,
  }) : _random = random ?? Random() {
    // Le tri choisi survit d'une session à l'autre.
    final storedSort = settings?.playlistSort;
    if (storedSort != null) {
      _state = _state.copyWith(
        sort: PlaylistSort.fromJson(storedSort),
        descending: settings?.playlistDescending ?? false,
      );
    }
    _subscription = bus.commands.listen(_onCommand);
  }

  /// Parcours du dossier, hors du fil de l'interface.
  final FolderScanner scanner;

  /// Positions mémorisées, pour les pastilles du panneau. `null` les désactive.
  final HistoryStore? history;

  /// Préférences persistantes (tri du panneau). `null` : rien n'est mémorisé.
  final SettingsStore? settings;

  /// Dit si un chemin peut réellement être ouvert.
  ///
  /// Le panneau montre tous les fichiers du dossier, y compris ceux dont le
  /// contrôleur n'existe pas encore (PDF, texte avant la Phase 4). La
  /// navigation, elle, doit les enjamber : enchaîner sur un fichier qu'OMNIA
  /// refuse d'ouvrir remplacerait la lecture par un message d'erreur.
  /// `null` signifie « tout est ouvrable ».
  final bool Function(String path)? isPlayable;

  final Random _random;

  /// Chemins visibles réellement ouvrables, dans l'ordre affiché.
  List<String> get _navigablePaths {
    final predicate = isPlayable;
    final visible = _state.visiblePaths;
    if (predicate == null) return visible;
    return visible.where(predicate).toList();
  }
  late final StreamSubscription<PlayerCommand> _subscription;

  final StreamController<PlaylistState> _states =
      StreamController<PlaylistState>.broadcast();

  PlaylistState _state = PlaylistState();

  /// Incrémenté à chaque nouveau scan : seul le dernier a le droit d'écrire.
  int _generation = 0;

  PlaylistState get state => _state;
  Stream<PlaylistState> get stream => _states.stream;

  void _update(PlaylistState Function(PlaylistState) reducer) {
    if (_states.isClosed) return;
    _state = reducer(_state);
    _states.add(_state);
  }

  void _onCommand(PlayerCommand command) {
    switch (command) {
      case SetPlaylistSort(:final sort, :final descending):
        _update((s) => s.copyWith(sort: sort, descending: descending));
        unawaited(settings?.setPlaylistSort(sort.name, descending));
      case SetPlaylistFilter(:final filter):
        _update((s) => s.copyWith(filter: filter));
      case SetPlaylistQuery(:final query):
        _update((s) => s.copyWith(query: query));
      case RemoveFromPlaylist(:final path):
        _update(
          (s) => s.copyWith(
            entries: s.entries.where((e) => e.path != path).toList(),
          ),
        );
      case RescanFolder():
        final folder = _state.folder;
        if (folder != null) unawaited(scanFolder(folder));
      default:
        break;
    }
  }

  // --- Scan ---------------------------------------------------------------

  /// Scanne le dossier parent de [filePath] s'il n'est pas déjà chargé.
  ///
  /// Ne bloque jamais l'appelant : le résultat arrive plus tard sur [stream].
  Future<void> ensureFolderFor(String filePath) async {
    final folder = p.dirname(filePath);
    if (_state.folder == folder && _state.entries.isNotEmpty) {
      // Déjà scanné : on marque simplement le fichier courant. Si le fichier
      // vient d'apparaître (téléchargement en cours), on l'ajoute à la volée.
      if (_state.entryFor(filePath) == null) {
        _addEntryFor(filePath);
      }
      return;
    }
    await scanFolder(folder);
  }

  /// Scanne [folder] et remplace le contenu du panneau.
  Future<void> scanFolder(String folder) async {
    final generation = ++_generation;
    // Si l'on change de dossier, la liste précédente disparaît immédiatement :
    // continuer à l'afficher sous le nom du nouveau dossier ferait croire que
    // ces fichiers s'y trouvent, et un clic ouvrirait un voisin d'ailleurs.
    // La recherche, elle aussi, est propre à un dossier : garder « ep » en
    // ouvrant un album de musique masquerait toutes les pistes sans raison
    // visible. Le tri et le filtre de type, plus généraux, sont conservés.
    final changingFolder = _state.folder != folder;
    _update(
      (s) => s.copyWith(
        folder: folder,
        scanning: true,
        entries: changingFolder ? const [] : s.entries,
        query: changingFolder ? '' : s.query,
      ),
    );

    final files = await scanner.scan(folder);
    if (generation != _generation) return; // un scan plus récent a pris la main

    _update(
      (s) => s.copyWith(
        entries: files.map(_toEntry).toList(),
        scanning: false,
      ),
    );
  }

  /// Ajoute un fichier absent du scan : créé après coup (téléchargement qui
  /// vient de se terminer) ou ouvert depuis un autre dossier.
  void _addEntryFor(String filePath) {
    final type = MediaRouter.typeForPath(filePath);
    if (!type.isSupported) return;
    final file = MediaFile(path: filePath, type: type);
    _update((s) => s.copyWith(entries: [...s.entries, _toEntry(file)]));
  }

  PlaylistEntry _toEntry(MediaFile file) {
    final entry = history?.entryFor(file.path);
    return PlaylistEntry(
      file: file,
      duration: entry != null && entry.duration > Duration.zero ? entry.duration : null,
      pageCount: entry != null && entry.pageCount > 0 ? entry.pageCount : null,
      resumePosition: entry?.resumePosition,
      resumePage: entry?.resumePage,
      resumeScroll: entry?.resumeScroll,
      completed: entry?.completed ?? false,
    );
  }

  /// Relit l'historique pour un seul fichier (après sa lecture, par exemple).
  void refreshEntry(String path) {
    final index = _state.entries.indexWhere((e) => e.path == path);
    if (index < 0) return;
    final updated = [..._state.entries];
    updated[index] = _toEntry(updated[index].file);
    _update((s) => s.copyWith(entries: updated));
  }

  // --- Fichier courant ----------------------------------------------------

  void setCurrent(String? path) {
    if (_state.currentPath == path) return;
    _update((s) => path == null
        ? s.copyWith(clearCurrentPath: true)
        : s.copyWith(currentPath: path));
  }

  // --- Navigation ---------------------------------------------------------

  /// Fichier suivant dans la liste affichée. Boucle en fin de liste, pour que
  /// `N` reste utile quand on arrive au dernier épisode.
  String? nextPath() => _relative(1);

  /// Fichier précédent dans la liste affichée. Boucle également.
  String? previousPath() => _relative(-1);

  /// Fichier suivant dans la liste sans reboucler en fin de liste.
  /// Retourne `null` si on est déjà sur le dernier fichier.
  String? nextNonLoopingPath() {
    final paths = _navigablePaths;
    if (paths.isEmpty) return null;
    final index = paths.indexOf(_state.currentPath ?? '');
    if (index < 0) return paths.first;
    return index + 1 < paths.length ? paths[index + 1] : null;
  }

  /// Fichier précédent dans la liste sans reboucler en début de liste.
  /// Retourne `null` si on est déjà sur le premier fichier.
  String? previousNonLoopingPath() {
    final paths = _navigablePaths;
    if (paths.isEmpty) return null;
    final index = paths.indexOf(_state.currentPath ?? '');
    if (index <= 0) return null;
    return paths[index - 1];
  }

  String? _relative(int step) {
    final paths = _navigablePaths;
    if (paths.isEmpty) return null;
    final index = paths.indexOf(_state.currentPath ?? '');
    if (index < 0) {
      // Le fichier courant n'est pas navigable (filtré, retiré, non lisible) :
      // on repart du bord correspondant au sens de navigation.
      return step > 0 ? paths.first : paths.last;
    }
    final next = (index + step) % paths.length;
    return paths[next < 0 ? next + paths.length : next];
  }

  /// Ce qu'il faut lire quand le fichier courant se termine, selon [mode].
  /// Retourne `null` s'il faut s'arrêter.
  String? nextForEndMode(EndOfPlaybackMode mode) {
    final paths = _navigablePaths;
    final current = _state.currentPath;

    switch (mode) {
      case EndOfPlaybackMode.stop:
        return null;
      case EndOfPlaybackMode.repeatOne:
        return current;
      case EndOfPlaybackMode.next:
        if (paths.isEmpty) return null;
        final index = paths.indexOf(current ?? '');
        if (index < 0) return paths.first;
        // Contrairement à `N`, la lecture automatique ne reboucle pas.
        return index + 1 < paths.length ? paths[index + 1] : null;
      case EndOfPlaybackMode.loopFolder:
        return nextPath();
      case EndOfPlaybackMode.shuffle:
        if (paths.isEmpty) return null;
        if (paths.length == 1) return paths.first;
        final others = paths.where((path) => path != current).toList();
        return others[_random.nextInt(others.length)];
    }
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _states.close();
  }
}
