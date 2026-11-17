import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/commands/player_command.dart';
import '../../core/controllers/media_router.dart';
import '../../core/models/media_type.dart';
import '../../core/providers.dart';
import '../../core/services/media_library.dart';
import '../home_navigation.dart';
import '../recent_files.dart';
import '../theme/omnia_theme.dart';
import '../widgets/desktop_promo_banner.dart';
import '../widgets/file_actions.dart';
import '../widgets/media_thumbnail.dart';

/// L'onglet Accueil : ce qui vient d'arriver sur le téléphone, et ce qu'on a
/// ouvert dernièrement.
///
/// Avant, l'accueil ne montrait qu'une liste de noms, chacun suivi de son
/// chemin complet et d'une même icône : on n'y reconnaissait rien. Chaque
/// fichier a maintenant son aperçu, le chemin est rangé dans son menu, et
/// les fichiers récemment ajoutés au téléphone ont leur bande à part.
class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  late Future<List<LibraryFile>> _added;
  bool _allAdded = false;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _added = _loadAdded();
    // Au retour dans l'application — après avoir accordé une autorisation,
    // ou reçu un fichier — la bande se remet à jour d'elle-même.
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<List<LibraryFile>> _loadAdded() =>
      ref.read(mediaLibraryProvider).recentlyAdded(limit: 60);

  Future<void> _refresh() async {
    if (!mounted) return;
    final next = _loadAdded();
    setState(() => _added = next);
    ref.read(recentFilesProvider.notifier).refresh();
    await next;
  }

  /// Demande au système les autorisations de lecture des médias.
  Future<void> _askPermissions() async {
    try {
      await const MethodChannel('dev.omnia.mobile/permissions')
          .invokeMethod<void>('requestPermissions');
    } on Object {
      // Canal absent : rien à demander.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_allAdded) {
      return _AllAdded(
        files: _added,
        onClose: () => setState(() => _allAdded = false),
      );
    }

    final colors = context.colors;
    final recents = ref.watch(recentFilesProvider);

    return RefreshIndicator(
      color: colors.projector,
      backgroundColor: colors.curtain,
      onRefresh: _refresh,
      child: CustomScrollView(
        // Toujours défilable : sans cela, tirer pour actualiser ne marche pas
        // tant que la page est plus courte que l'écran.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: DesktopPromoBanner()),
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'Ajoutés récemment',
              actionLabel: 'Tout afficher',
              onAction: () => setState(() => _allAdded = true),
            ),
          ),
          SliverToBoxAdapter(
            child: _AddedStrip(files: _added, onAskPermissions: _askPermissions),
          ),
          const SliverToBoxAdapter(child: _SectionHeader(title: 'Ouverts récemment')),
          if (recents.isEmpty)
            const SliverToBoxAdapter(child: _NoRecents())
          else
            SliverList.builder(
              itemCount: recents.length,
              itemBuilder: (_, index) => _RecentTile(recent: recents[index]),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: OmniaMetrics.space5)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OmniaMetrics.space4,
        OmniaMetrics.space4,
        OmniaMetrics.space2,
        OmniaMetrics.space2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: type.caption.copyWith(
                color: colors.dust,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: type.secondary.copyWith(color: colors.projector),
              ),
            ),
        ],
      ),
    );
  }
}

/// La bande horizontale des fichiers récemment ajoutés au téléphone.
class _AddedStrip extends StatelessWidget {
  const _AddedStrip({required this.files, required this.onAskPermissions});

  final Future<List<LibraryFile>> files;
  final VoidCallback onAskPermissions;

  static const double _cardWidth = 148;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return SizedBox(
      height: 168,
      child: FutureBuilder<List<LibraryFile>>(
        future: files,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            // Des cases vides à la bonne taille : la page ne saute pas quand
            // la liste arrive.
            return ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: OmniaMetrics.space4),
              itemCount: 4,
              separatorBuilder: (_, __) => const SizedBox(width: OmniaMetrics.space3),
              itemBuilder: (_, __) => Align(
                alignment: Alignment.topCenter,
                child: Container(
                  width: _cardWidth,
                  height: 96,
                  decoration: BoxDecoration(
                    color: colors.curtain,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            );
          }

          final list = snapshot.data ?? const <LibraryFile>[];
          if (list.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: OmniaMetrics.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aucun fichier récent trouvé sur le téléphone.',
                    style: type.body.copyWith(color: colors.screen),
                  ),
                  const SizedBox(height: OmniaMetrics.space1),
                  Text(
                    "Si OMNIA n'a pas encore le droit de lire vos fichiers, "
                    "autorisez-le : la liste apparaîtra à votre retour.",
                    style: type.secondary.copyWith(color: colors.dust),
                  ),
                  TextButton.icon(
                    onPressed: onAskPermissions,
                    icon: Icon(Icons.lock_open_rounded, size: 18, color: colors.projector),
                    label: Text(
                      "Autoriser l'accès aux fichiers",
                      style: type.secondary.copyWith(color: colors.projector),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: OmniaMetrics.space4),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: OmniaMetrics.space3),
            itemBuilder: (_, index) => _AddedCard(file: list[index], width: _cardWidth),
          );
        },
      ),
    );
  }
}

class _AddedCard extends ConsumerWidget {
  const _AddedCard({required this.file, required this.width});

  final LibraryFile file;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => ref.dispatch(OpenFile(file.path)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: width,
                height: 96,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MediaThumbnail(path: file.path),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: _TypeBadge(type: file.type),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: OmniaMetrics.space1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: OmniaMetrics.space2),
                  child: Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: type.secondary.copyWith(color: colors.screen),
                  ),
                ),
              ),
              FileActionsButton(
                path: file.path,
                size: file.size,
                added: file.added,
                modified: file.modified,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final MediaType type;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(iconForMediaType(type), size: 14, color: colors.projector),
    );
  }
}

/// Un fichier ouvert récemment : son aperçu, où on en était, son menu.
class _RecentTile extends ConsumerWidget {
  const _RecentTile({required this.recent});

  final RecentFile recent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final entry = recent.entry;
    final enabled = recent.exists;
    final mediaType = MediaRouter.typeForPath(recent.path);

    // Où on en était, dit en clair, et la même chose en barre sur l'aperçu.
    String progressLabel;
    double fraction = 0;
    if (entry.completed) {
      progressLabel = 'Terminé';
      fraction = 1;
    } else if (mediaType.isAv && entry.duration > Duration.zero) {
      fraction = entry.position.inMilliseconds / entry.duration.inMilliseconds;
      progressLabel = entry.position > Duration.zero
          ? 'Reprise à ${_clock(entry.position)} sur ${_clock(entry.duration)}'
          : _clock(entry.duration);
    } else if (entry.pageCount > 0) {
      fraction = entry.page / entry.pageCount;
      progressLabel = 'Page ${entry.page} sur ${entry.pageCount}';
    } else if (entry.scrollFraction > 0) {
      fraction = entry.scrollFraction;
      progressLabel = 'Lu à ${(entry.scrollFraction * 100).round()} %';
    } else {
      progressLabel = 'Ouvert le ${formatFileDate(entry.lastOpened)}';
    }
    fraction = fraction.clamp(0.0, 1.0);

    return InkWell(
      onTap: enabled ? () => ref.dispatch(OpenFile(recent.path)) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          OmniaMetrics.space4,
          OmniaMetrics.space2,
          OmniaMetrics.space1,
          OmniaMetrics.space2,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 112,
                height: 68,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: enabled ? 1 : 0.35,
                      child: MediaThumbnail(path: recent.path),
                    ),
                    if (fraction > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 3,
                          color: colors.projector,
                          backgroundColor: Colors.black.withValues(alpha: 0.55),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: OmniaMetrics.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.basename(recent.path),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: type.bodyStrong.copyWith(
                      color: enabled ? colors.screen : colors.dust,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enabled ? progressLabel : "N'est plus à son emplacement",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.caption.copyWith(
                      color: enabled ? colors.dust : colors.alert,
                    ),
                  ),
                ],
              ),
            ),
            FileActionsButton(path: recent.path, enabled: enabled),
          ],
        ),
      ),
    );
  }

  static String _clock(Duration d) {
    final hours = d.inHours;
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '${d.inMinutes}:$seconds';
  }
}

class _NoRecents extends StatelessWidget {
  const _NoRecents();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: OmniaMetrics.space4,
        vertical: OmniaMetrics.space3,
      ),
      child: Text(
        "Les fichiers que vous ouvrez apparaîtront ici, avec l'endroit où vous "
        "vous étiez arrêté.",
        style: type.secondary.copyWith(color: colors.dust),
      ),
    );
  }
}

/// Tous les fichiers récemment ajoutés, sur toute la page.
class _AllAdded extends ConsumerWidget {
  const _AllAdded({required this.files, required this.onClose});

  final Future<List<LibraryFile>> files;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    // Le retour du système referme la liste — mais seulement quand l'accueil
    // est l'onglet affiché : un onglet caché ne doit pas retenir le retour.
    final visible = ref.watch(homeSectionProvider) == HomeSection.home;

    return PopScope(
      canPop: !visible,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onClose();
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              OmniaMetrics.space1,
              OmniaMetrics.space1,
              OmniaMetrics.space4,
              OmniaMetrics.space1,
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Retour',
                  icon: Icon(Icons.arrow_back_rounded, color: colors.screen),
                  onPressed: onClose,
                ),
                Text('Ajoutés récemment', style: type.bodyStrong.copyWith(color: colors.screen)),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<LibraryFile>>(
              future: files,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return Center(child: CircularProgressIndicator(color: colors.projector));
                }
                final list = snapshot.data ?? const <LibraryFile>[];
                if (list.isEmpty) {
                  return Center(
                    child: Text(
                      'Aucun fichier récent trouvé.',
                      style: type.secondary.copyWith(color: colors.dust),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, index) => _AddedRow(file: list[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AddedRow extends ConsumerWidget {
  const _AddedRow({required this.file});

  final LibraryFile file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final details = [
      if (file.added != null) 'Ajouté le ${formatFileDate(file.added!)}',
      if (file.size != null) formatFileSize(file.size!),
    ].join('  ·  ');

    return InkWell(
      onTap: () => ref.dispatch(OpenFile(file.path)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          OmniaMetrics.space4,
          OmniaMetrics.space2,
          OmniaMetrics.space1,
          OmniaMetrics.space2,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 112, height: 68, child: MediaThumbnail(path: file.path)),
            ),
            const SizedBox(width: OmniaMetrics.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: type.bodyStrong.copyWith(color: colors.screen),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(details, style: type.caption.copyWith(color: colors.dust)),
                  ],
                ],
              ),
            ),
            FileActionsButton(
              path: file.path,
              size: file.size,
              added: file.added,
              modified: file.modified,
            ),
          ],
        ),
      ),
    );
  }
}
