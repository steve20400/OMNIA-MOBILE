import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/playlist_sort.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../panel_controller.dart';
import '../theme/omnia_theme.dart';
import 'omnia_icon_button.dart';
import 'playlist_tile.dart';

/// Déroulé inférieur de liste de lecture pour mobile (style compact sous le
/// lecteur). Utilisé en mode portrait ou en mode mini-lecteur.
///
/// Sa hauteur n'est plus figée : il s'ouvre d'emblée sur la moitié de l'écran,
/// l'utilisateur la règle en glissant la poignée du haut jusqu'aux quatre
/// cinquièmes, et son choix se retrouve au lancement suivant. Avant cela, le
/// tiroir faisait 240 pixels quoi qu'il arrive — quatre fichiers visibles sur
/// une saison entière.
///
/// Sur une fenêtre basse (mini-lecteur, Picture-in-Picture), c'est la réserve
/// de la scène qui l'emporte sur la moitié demandée : voir
/// [OmniaMetrics.playlistDrawerStageReserve].
class MobileBottomPlaylist extends ConsumerStatefulWidget {
  const MobileBottomPlaylist({
    super.key,
    required this.available,
    this.onClose,
  });

  /// Hauteur dont la scène et le tiroir disposent ensemble. C'est elle qui
  /// donne son sens à la part choisie par l'utilisateur.
  final double available;

  final VoidCallback? onClose;

  /// Poignée de redimensionnement. Nommée pour que le test du glissement la
  /// saisisse exactement là où le pouce la saisit.
  static const Key gripKey = Key('playlist-drawer-grip');

  @override
  ConsumerState<MobileBottomPlaylist> createState() =>
      _MobileBottomPlaylistState();
}

class _MobileBottomPlaylistState extends ConsumerState<MobileBottomPlaylist> {
  /// Hauteur suivie pendant le glissement, en pixels.
  ///
  /// Les deltas s'accumulent ici plutôt que sur la hauteur affichée : bornée,
  /// celle-ci perdrait tout ce qui dépasse, et le doigt devrait refaire le
  /// chemin à vide avant que le tiroir ne reparte dans l'autre sens.
  double? _dragHeight;

  void _onDragStart(DragStartDetails _) {
    _dragHeight = OmniaMetrics.playlistDrawerHeight(
      widget.available,
      ref.read(panelStateProvider).drawerFraction,
    );
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final from = _dragHeight;
    if (from == null || widget.available <= 0) return;
    // Vers le haut (dy négatif), le tiroir s'agrandit.
    final next = (from - details.delta.dy).clamp(
      OmniaMetrics.playlistDrawerLowest(widget.available),
      OmniaMetrics.playlistDrawerHighest(widget.available),
    );
    _dragHeight = next;
    // Règle d'or : même un geste continu passe par le bus de commandes.
    ref.dispatch(SetPlaylistDrawerHeight(next / widget.available));
  }

  void _onDragEnd(DragEndDetails _) => _dragHeight = null;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final playlist = ref.watch(playlistStateProvider);
    final state = ref.watch(playbackStateProvider);
    final fraction = ref.watch(panelStateProvider.select((s) => s.drawerFraction));
    final currentFilter = playlist.filter;
    final visibleEntries = playlist.visible;

    final currentTitle = state.file?.name ?? l10n.panelTabFolder;
    // Un fichier reçu d'« Ouvrir avec » dont MediaStore ignore le dossier : le
    // dire franchement, plutôt que de laisser croire à une liste tronquée.
    final queueInfo = playlist.isLoneShare
        ? l10n.panelSharedAlone
        : playlist.entries.isNotEmpty
            ? 'File d\'attente • ${(playlist.currentIndex >= 0 ? playlist.currentIndex + 1 : 1)} / ${playlist.entries.length}'
            : l10n.panelFileCount(visibleEntries.length);

    final height = OmniaMetrics.playlistDrawerHeight(widget.available, fraction);
    // Dans une fenêtre de mini-lecteur, la réserve de la scène écrase le tiroir
    // sous sa hauteur utile : la rangée de filtres y prendrait toute la place de
    // la liste. Mieux vaut voir des fichiers que des filtres.
    final showFilters = height >= OmniaMetrics.playlistDrawerUsableHeight;

    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.curtain,
        border: Border(top: BorderSide(color: colors.seam, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Poignée de redimensionnement. Elle couvre toute la largeur : le
          // pouce n'a pas à viser une barrette de quarante pixels.
          GestureDetector(
            key: MobileBottomPlaylist.gripKey,
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: _onDragStart,
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            onVerticalDragCancel: () => _dragHeight = null,
            child: Semantics(
              label: l10n.panelResizeHandle,
              child: SizedBox(
                height: OmniaMetrics.playlistDrawerGripHeight,
                child: Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.dust,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // En-tête : Titre, info file d'attente et bouton de repli
          InkWell(
            onTap: onClose,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.playlist_play_rounded, size: 22, color: colors.projector),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currentTitle,
                          style: type.bodyStrong.copyWith(color: colors.screen, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          queueInfo,
                          style: type.caption.copyWith(color: colors.dust, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  OmniaIconButton(
                    icon: Icons.keyboard_arrow_down_rounded,
                    size: 28,
                    iconSize: 22,
                    tooltip: l10n.closePanel,
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
          ),
          // Filtres par type de média
          if (showFilters)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final filter in PlaylistFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _FilterChipItem(
                          label: _labelForFilter(filter, l10n),
                          selected: filter == currentFilter,
                          onTap: () => ref.dispatch(SetPlaylistFilter(filter)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Divider(height: 1, thickness: 1, color: colors.seam),
          // Liste des fichiers
          Expanded(
            child: visibleEntries.isEmpty
                ? Center(
                    child: Text(
                      l10n.panelEmpty,
                      style: type.caption.copyWith(color: colors.dust),
                    ),
                  )
                : ListView.builder(
                    itemCount: visibleEntries.length,
                    itemExtent: 46,
                    itemBuilder: (context, index) {
                      final entry = visibleEntries[index];
                      final isCurrent = entry.path == playlist.currentPath;
                      return PlaylistTile(
                        key: ValueKey('mobile-pl:${entry.path}'),
                        entry: entry,
                        current: isCurrent,
                        height: 46,
                        onTap: () => ref.dispatch(OpenFile(entry.path)),
                        onSecondaryTap: (_) {},
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  VoidCallback get onClose =>
      widget.onClose ?? () => ref.dispatch(const SetSidePanelVisible(false));

  String _labelForFilter(PlaylistFilter f, AppLocalizations l10n) => switch (f) {
        PlaylistFilter.all => l10n.filterAll,
        PlaylistFilter.video => l10n.filterVideo,
        PlaylistFilter.audio => l10n.filterAudio,
        PlaylistFilter.documents => l10n.filterDocuments,
        PlaylistFilter.images => l10n.filterImages,
      };
}

class _FilterChipItem extends StatelessWidget {
  const _FilterChipItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? colors.projector.withValues(alpha: 0.2) : colors.velvet,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colors.projector : colors.seam,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: type.caption.copyWith(
            color: selected ? colors.projector : colors.screen,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}
