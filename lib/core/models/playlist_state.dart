import '../utils/natural_sort.dart';
import 'media_type.dart';
import 'playlist_entry.dart';
import 'playlist_sort.dart';

/// État du panneau de dossier : ce qui a été scanné, comment c'est trié,
/// filtré et recherché, et quel fichier est en cours.
///
/// [entries] garde l'ordre brut du scan ; [visible] applique tri, filtre et
/// recherche. La navigation `NextFile` / `PreviousFile` suit toujours
/// [visible], donc ce que l'utilisateur voit à l'écran.
class PlaylistState {
  PlaylistState({
    this.folder,
    this.entries = const [],
    this.sort = PlaylistSort.name,
    this.descending = false,
    this.filter = PlaylistFilter.all,
    this.query = '',
    this.scanning = false,
    this.currentPath,
  });

  /// Dossier scanné, `null` si aucun fichier n'a encore été ouvert.
  final String? folder;

  /// Tous les fichiers lisibles du dossier, dans l'ordre où le scan les a vus.
  final List<PlaylistEntry> entries;

  final PlaylistSort sort;
  final bool descending;
  final PlaylistFilter filter;

  /// Texte de recherche instantanée (insensible à la casse).
  final String query;

  /// Un scan est en cours : le panneau affiche un état de chargement.
  final bool scanning;

  /// Chemin du fichier en cours de lecture.
  final String? currentPath;

  bool get isEmpty => entries.isEmpty;

  /// Résultat mémoïsé de [visible].
  ///
  /// L'objet est immuable, donc la liste ne peut pas changer : la calculer une
  /// fois évite un tri complet à chaque reconstruction de l'interface, ce qui
  /// compte sur un dossier de plusieurs milliers de fichiers.
  List<PlaylistEntry>? _visibleCache;

  /// Éléments réellement affichés : filtre de type, puis recherche, puis tri.
  List<PlaylistEntry> get visible => _visibleCache ??= _computeVisible();

  List<PlaylistEntry> _computeVisible() {
    final needle = query.trim().toLowerCase();
    final result = entries.where((e) {
      if (!_matchesFilter(e.file.type)) return false;
      if (needle.isEmpty) return true;
      return e.file.name.toLowerCase().contains(needle);
    }).toList();

    result.sort(_comparator);
    return List.unmodifiable(result);
  }

  bool _matchesFilter(MediaType type) => switch (filter) {
        PlaylistFilter.all => true,
        PlaylistFilter.video => type == MediaType.video,
        PlaylistFilter.audio => type == MediaType.audio,
        PlaylistFilter.documents => type.isDocument,
        PlaylistFilter.images => type.isImage,
      };


  int _comparator(PlaylistEntry a, PlaylistEntry b) {
    final sign = descending ? -1 : 1;
    final result = switch (sort) {
      PlaylistSort.name => compareNatural(a.file.name, b.file.name),
      PlaylistSort.date => _compareNullable(
          a.file.modifiedAt?.millisecondsSinceEpoch,
          b.file.modifiedAt?.millisecondsSinceEpoch,
          a,
          b,
        ),
      PlaylistSort.size => _compareNullable(a.file.size, b.file.size, a, b),
      PlaylistSort.type => a.file.type.index != b.file.type.index
          ? a.file.type.index - b.file.type.index
          : compareNatural(a.file.name, b.file.name),
    };
    return sign * result;
  }

  /// Les valeurs inconnues passent en dernier ; à égalité, on retombe sur le
  /// tri naturel pour que l'ordre reste stable.
  int _compareNullable(num? a, num? b, PlaylistEntry ea, PlaylistEntry eb) {
    if (a == null && b == null) return compareNatural(ea.file.name, eb.file.name);
    if (a == null) return 1;
    if (b == null) return -1;
    final c = a.compareTo(b);
    return c != 0 ? c : compareNatural(ea.file.name, eb.file.name);
  }

  /// Index du fichier courant dans [visible], ou -1 s'il n'y figure pas
  /// (filtré, recherché, ou hors du dossier scanné).
  int get currentIndex {
    final path = currentPath;
    if (path == null) return -1;
    return visible.indexWhere((e) => e.path == path);
  }

  /// Chemins visibles, dans l'ordre affiché. C'est la projection envoyée à la
  /// future télécommande.
  List<String> get visiblePaths =>
      _visiblePathsCache ??= List.unmodifiable(visible.map((e) => e.path));

  List<String>? _visiblePathsCache;

  /// Entrée correspondant à un chemin, ou `null`.
  PlaylistEntry? entryFor(String path) {
    for (final e in entries) {
      if (e.path == path) return e;
    }
    return null;
  }

  PlaylistState copyWith({
    String? folder,
    bool clearFolder = false,
    List<PlaylistEntry>? entries,
    PlaylistSort? sort,
    bool? descending,
    PlaylistFilter? filter,
    String? query,
    bool? scanning,
    String? currentPath,
    bool clearCurrentPath = false,
  }) {
    return PlaylistState(
      folder: clearFolder ? null : (folder ?? this.folder),
      entries: entries ?? this.entries,
      sort: sort ?? this.sort,
      descending: descending ?? this.descending,
      filter: filter ?? this.filter,
      query: query ?? this.query,
      scanning: scanning ?? this.scanning,
      currentPath: clearCurrentPath ? null : (currentPath ?? this.currentPath),
    );
  }

  Map<String, Object?> toJson() => {
        'folder': folder,
        'entries': entries.map((e) => e.toJson()).toList(),
        'sort': sort.name,
        'descending': descending,
        'filter': filter.name,
        'query': query,
        'scanning': scanning,
        'currentPath': currentPath,
      };

  factory PlaylistState.fromJson(Map<String, Object?> json) => PlaylistState(
        folder: json['folder'] as String?,
        entries: (json['entries'] as List? ?? const [])
            .map((e) => PlaylistEntry.fromJson(e as Map<String, Object?>))
            .toList(),
        sort: PlaylistSort.fromJson(json['sort']),
        descending: json['descending'] as bool? ?? false,
        filter: PlaylistFilter.fromJson(json['filter']),
        query: json['query'] as String? ?? '',
        scanning: json['scanning'] as bool? ?? false,
        currentPath: json['currentPath'] as String?,
      );

  @override
  String toString() =>
      'PlaylistState(${entries.length} fichiers, ${visible.length} visibles)';
}
