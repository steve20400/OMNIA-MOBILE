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

/// Déroulé inférieur de liste de lecture pour mobile (style compact sous le lecteur).
/// Utilisé en mode portrait ou en mode mini-lecteur.
class MobileBottomPlaylist extends ConsumerWidget {
  const MobileBottomPlaylist({super.key, this.height = 250, this.onClose});

  final double height;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final playlist = ref.watch(playlistStateProvider);
    final state = ref.watch(playbackStateProvider);
    final currentFilter = playlist.filter;
    final visibleEntries = playlist.visible;

    final currentTitle = state.file?.name ?? l10n.panelTabFolder;
    final queueInfo = playlist.entries.isNotEmpty
        ? 'File d\'attente • ${(playlist.currentIndex >= 0 ? playlist.currentIndex + 1 : 1)} / ${playlist.entries.length}'
        : l10n.panelFileCount(visibleEntries.length);

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
          // En-tête : Titre, info file d'attente et bouton de repli
          InkWell(
            onTap: onClose ?? () => ref.dispatch(const SetSidePanelVisible(false)),
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
                    onPressed: onClose ?? () => ref.dispatch(const SetSidePanelVisible(false)),
                  ),
                ],
              ),
            ),
          ),
          // Filtres par type de média
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
