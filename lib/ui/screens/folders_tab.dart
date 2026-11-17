import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/commands/player_command.dart';
import '../../core/controllers/media_router.dart';
import '../../core/models/media_type.dart';
import '../../core/providers.dart';
import '../home_navigation.dart';
import '../theme/omnia_theme.dart';
import '../widgets/file_actions.dart';
import '../widgets/media_thumbnail.dart';

/// Une entrée de dossier : un sous-dossier, ou un fichier qu'OMNIA sait lire.
class FolderEntry {
  const FolderEntry({required this.path, required this.isDirectory, this.label});

  final String path;
  final bool isDirectory;

  /// Nom à afficher quand ce n'est pas celui du dossier — « Mémoire interne »
  /// plutôt que « 0 ».
  final String? label;

  String get name => label ?? p.basename(path);
}

/// Les stockages du téléphone : la mémoire interne d'abord, puis les cartes
/// et clés montées.
List<FolderEntry> storageRoots() {
  const internal = '/storage/emulated/0';
  final roots = <FolderEntry>[
    const FolderEntry(path: internal, isDirectory: true, label: 'Mémoire interne'),
  ];
  try {
    for (final entity in Directory('/storage').listSync(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is! Directory || name == 'emulated' || name == 'self') continue;
      roots.add(FolderEntry(path: entity.path, isDirectory: true, label: 'Carte ($name)'));
    }
  } on FileSystemException {
    // Liste des volumes refusée : la mémoire interne suffit.
  }
  return roots;
}

/// Le contenu d'un dossier : sous-dossiers d'abord, puis les fichiers
/// qu'OMNIA sait lire, chacun dans l'ordre alphabétique.
///
/// Les éléments cachés restent cachés, et les fichiers qu'OMNIA ne sait pas
/// ouvrir ne sont pas montrés : un fichier qu'on ne peut que regarder ne fait
/// qu'allonger la liste.
Future<List<FolderEntry>> listFolder(String path) async {
  final folders = <FolderEntry>[];
  final files = <FolderEntry>[];
  await for (final entity in Directory(path).list(followLinks: false)) {
    final name = p.basename(entity.path);
    if (name.startsWith('.')) continue;
    if (entity is Directory) {
      folders.add(FolderEntry(path: entity.path, isDirectory: true));
    } else if (entity is File && MediaRouter.typeForPath(entity.path) != MediaType.unknown) {
      files.add(FolderEntry(path: entity.path, isDirectory: false));
    }
  }
  int byName(FolderEntry a, FolderEntry b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  folders.sort(byName);
  files.sort(byName);
  return [...folders, ...files];
}

/// Cherche [query] dans les noms, sous [root] et ses sous-dossiers.
///
/// Bornée en profondeur, en nombre et en durée : parcourir tout un téléphone
/// prendrait des minutes, et une recherche qui ne répond pas est pire qu'une
/// recherche incomplète.
Future<List<FolderEntry>> searchFolder(
  String root,
  String query, {
  int maxDepth = 5,
  int maxResults = 200,
  Duration budget = const Duration(seconds: 4),
}) async {
  final needle = query.toLowerCase();
  final results = <FolderEntry>[];
  final watch = Stopwatch()..start();
  final queue = <(String, int)>[(root, 0)];
  while (queue.isNotEmpty && results.length < maxResults && watch.elapsed < budget) {
    final (dir, depth) = queue.removeAt(0);
    try {
      await for (final entity in Directory(dir).list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        final isDirectory = entity is Directory;
        if (isDirectory && depth < maxDepth) queue.add((entity.path, depth + 1));
        final readable = isDirectory ||
            (entity is File && MediaRouter.typeForPath(entity.path) != MediaType.unknown);
        if (readable && name.toLowerCase().contains(needle)) {
          results.add(FolderEntry(path: entity.path, isDirectory: isDirectory));
          if (results.length >= maxResults) break;
        }
      }
    } on FileSystemException {
      // Dossier protégé (données d'une autre application) : on passe.
    }
  }
  return results;
}

/// L'onglet Dossiers : parcourir le téléphone depuis OMNIA, chercher un
/// fichier, l'ouvrir d'un toucher — sans repasser à chaque fois par le
/// sélecteur de fichiers du système.
class FoldersTab extends ConsumerStatefulWidget {
  const FoldersTab({super.key});

  @override
  ConsumerState<FoldersTab> createState() => _FoldersTabState();
}

class _FoldersTabState extends ConsumerState<FoldersTab> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;

  String? _listedPath;
  Future<List<FolderEntry>>? _listing;
  String _search = '';
  Future<List<FolderEntry>>? _deepSearch;

  /// Vrai quand Android refuse à OMNIA la lecture de tous les fichiers :
  /// les documents ne seraient alors pas visibles dans les dossiers.
  bool _missingAllFiles = false;

  static const _permissions = MethodChannel('dev.omnia.mobile/permissions');

  @override
  void initState() {
    super.initState();
    unawaited(_checkAccess());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _checkAccess() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await _permissions.invokeMapMethod<String, Object?>('checkStatus');
      if (!mounted) return;
      setState(() => _missingAllFiles = status?['isAllFilesManager'] == false);
    } on Object {
      // Canal absent : on ne sait pas, on ne dit rien.
    }
  }

  Future<void> _grantAllFiles() async {
    try {
      await _permissions.invokeMethod<bool>('openAllFilesSettings');
    } on Object {
      // Page des réglages injoignable : rien d'autre à proposer.
    }
  }

  void _open(String? path) {
    _query.clear();
    _search = '';
    _deepSearch = null;
    ref.read(folderLocationProvider.notifier).open(path);
  }

  /// Remonte d'un dossier ; au sommet d'un stockage, revient à leur liste.
  void _goUp(String location) {
    final isRoot = storageRoots().any((root) => root.path == location);
    _open(isRoot ? null : p.dirname(location));
  }

  void _onQueryChanged(String value, String? location) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final query = value.trim();
      setState(() {
        _search = query;
        // La recherche dans les sous-dossiers ne part qu'à partir de deux
        // lettres : une seule en trouverait des milliers.
        _deepSearch = location != null && query.length >= 2
            ? searchFolder(location, query)
            : null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final location = ref.watch(folderLocationProvider);
    // Le retour du système remonte d'un dossier — seulement quand cet onglet
    // est celui qu'on regarde : un onglet caché ne doit pas retenir le retour.
    final visible = ref.watch(homeSectionProvider) == HomeSection.folders;

    if (_listing == null || location != _listedPath) {
      _listedPath = location;
      _listing = location == null
          ? Future.value(storageRoots())
          : listFolder(location);
    }

    return PopScope(
      canPop: location == null || !visible,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && location != null) _goUp(location);
      },
      child: Column(
        children: [
          _LocationBar(
            location: location,
            onUp: location == null ? null : () => _goUp(location),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              OmniaMetrics.space4,
              OmniaMetrics.space1,
              OmniaMetrics.space4,
              OmniaMetrics.space2,
            ),
            child: TextField(
              controller: _query,
              onChanged: (value) => _onQueryChanged(value, location),
              style: type.body.copyWith(color: colors.screen),
              decoration: InputDecoration(
                isDense: true,
                hintText: location == null
                    ? 'Choisissez un stockage pour y chercher'
                    : 'Chercher dans ce dossier',
                hintStyle: type.body.copyWith(color: colors.dust),
                prefixIcon: Icon(Icons.search_rounded, color: colors.dust),
                filled: true,
                fillColor: colors.curtain,
                border: OutlineInputBorder(
                  borderRadius: OmniaMetrics.controlRadius,
                  borderSide: BorderSide(color: colors.seam),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: OmniaMetrics.controlRadius,
                  borderSide: BorderSide(color: colors.seam),
                ),
              ),
            ),
          ),
          if (_missingAllFiles && location == null)
            _AccessBanner(onGrant: _grantAllFiles),
          Expanded(
            child: FutureBuilder<List<FolderEntry>>(
              future: _listing,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return Center(child: CircularProgressIndicator(color: colors.projector));
                }
                if (snapshot.hasError) {
                  return const _Message(
                    "Ce dossier n'est pas accessible : Android réserve certains "
                    'dossiers aux applications qui les ont créés.',
                  );
                }
                final needle = _search.toLowerCase();
                final entries = (snapshot.data ?? const <FolderEntry>[])
                    .where((e) => needle.isEmpty || e.name.toLowerCase().contains(needle))
                    .toList();

                return ListView(
                  children: [
                    if (entries.isEmpty && _search.isEmpty)
                      const _Message('Ce dossier ne contient rien qu’OMNIA sache lire.'),
                    for (final entry in entries) _EntryTile(entry: entry, onOpenFolder: _open),
                    if (_deepSearch != null)
                      _DeepResults(
                        results: _deepSearch!,
                        shown: entries.map((e) => e.path).toSet(),
                        onOpenFolder: _open,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationBar extends StatelessWidget {
  const _LocationBar({required this.location, required this.onUp});

  final String? location;
  final VoidCallback? onUp;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final title = location == null ? 'Stockages du téléphone' : p.basename(location!);
    final subtitle = location == null
        ? null
        : location!.replaceFirst('/storage/emulated/0', 'Mémoire interne');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OmniaMetrics.space1,
        OmniaMetrics.space1,
        OmniaMetrics.space4,
        0,
      ),
      child: Row(
        children: [
          if (onUp != null)
            IconButton(
              tooltip: 'Dossier parent',
              icon: Icon(Icons.arrow_upward_rounded, color: colors.screen),
              onPressed: onUp,
            )
          else
            const SizedBox(width: OmniaMetrics.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.bodyStrong.copyWith(color: colors.screen),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.caption.copyWith(color: colors.dust),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessBanner extends StatelessWidget {
  const _AccessBanner({required this.onGrant});

  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        OmniaMetrics.space4,
        0,
        OmniaMetrics.space4,
        OmniaMetrics.space2,
      ),
      padding: const EdgeInsets.all(OmniaMetrics.space3),
      decoration: BoxDecoration(
        color: colors.projector.withValues(alpha: 0.1),
        borderRadius: OmniaMetrics.controlRadius,
        border: Border.all(color: colors.projector.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sans l’accès à tous les fichiers, Android ne montre à OMNIA que les '
            'vidéos, musiques et images : les documents resteront invisibles '
            'dans les dossiers.',
            style: type.secondary.copyWith(color: colors.screen),
          ),
          TextButton(
            onPressed: onGrant,
            child: Text(
              'Autoriser l’accès à tous les fichiers',
              style: type.secondary.copyWith(color: colors.projector),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Padding(
      padding: const EdgeInsets.all(OmniaMetrics.space5),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: type.secondary.copyWith(color: colors.dust),
      ),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry, required this.onOpenFolder});

  final FolderEntry entry;
  final void Function(String path) onOpenFolder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;

    if (entry.isDirectory) {
      return ListTile(
        leading: Icon(Icons.folder_rounded, color: colors.projector, size: 30),
        title: Text(
          entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: type.body.copyWith(color: colors.screen),
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Options du dossier',
          icon: Icon(Icons.more_vert_rounded, size: 20, color: colors.dust),
          color: colors.curtain,
          onSelected: (_) => ref.dispatch(OpenFolder(entry.path)),
          itemBuilder: (_) => [
            PopupMenuItem<String>(
              value: 'play',
              child: Row(
                children: [
                  Icon(Icons.playlist_play_rounded, size: 20, color: colors.projector),
                  const SizedBox(width: OmniaMetrics.space3),
                  Text('Lire tout le dossier', style: type.body.copyWith(color: colors.screen)),
                ],
              ),
            ),
          ],
        ),
        onTap: () => onOpenFolder(entry.path),
      );
    }

    return InkWell(
      onTap: () => ref.dispatch(OpenFile(entry.path)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          OmniaMetrics.space4,
          OmniaMetrics.space1,
          OmniaMetrics.space1,
          OmniaMetrics.space1,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(width: 72, height: 46, child: MediaThumbnail(path: entry.path, size: 200)),
            ),
            const SizedBox(width: OmniaMetrics.space3),
            Expanded(
              child: Text(
                entry.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: type.body.copyWith(color: colors.screen),
              ),
            ),
            FileActionsButton(path: entry.path),
          ],
        ),
      ),
    );
  }
}

/// Les résultats trouvés dans les sous-dossiers.
class _DeepResults extends StatelessWidget {
  const _DeepResults({
    required this.results,
    required this.shown,
    required this.onOpenFolder,
  });

  final Future<List<FolderEntry>> results;

  /// Déjà affichés dans le dossier courant : inutile de les répéter.
  final Set<String> shown;
  final void Function(String path) onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return FutureBuilder<List<FolderEntry>>(
      future: results,
      builder: (context, snapshot) {
        final header = Padding(
          padding: const EdgeInsets.fromLTRB(
            OmniaMetrics.space4,
            OmniaMetrics.space4,
            OmniaMetrics.space4,
            OmniaMetrics.space2,
          ),
          child: Text(
            'DANS LES SOUS-DOSSIERS',
            style: type.caption.copyWith(
              color: colors.dust,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
        if (snapshot.connectionState != ConnectionState.done) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              Padding(
                padding: const EdgeInsets.all(OmniaMetrics.space4),
                child: LinearProgressIndicator(color: colors.projector),
              ),
            ],
          );
        }
        final found = (snapshot.data ?? const <FolderEntry>[])
            .where((e) => !shown.contains(e.path))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            if (found.isEmpty)
              const _Message('Rien de plus dans les sous-dossiers.')
            else
              for (final entry in found) _EntryTile(entry: entry, onOpenFolder: onOpenFolder),
          ],
        );
      },
    );
  }
}
