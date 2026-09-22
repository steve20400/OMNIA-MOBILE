import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/commands/player_command.dart';
import '../../core/models/playlist_entry.dart';
import '../../core/models/playlist_sort.dart';
import '../../core/models/playlist_state.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../chrome_controller.dart';
import '../document_search_provider.dart';
import '../document_ui_controller.dart';
import '../panel_controller.dart';
import '../shortcuts/default_keymap.dart';
import '../shortcuts/shortcut_labels.dart';
import '../theme/omnia_theme.dart';
import 'omnia_icon_button.dart';
import 'pdf_panel_tabs.dart';
import 'playlist_tile.dart';

/// Vrai si, dans une fenêtre de [windowWidth], le panneau doit s'ouvrir en
/// tiroir par-dessus la scène plutôt que de s'ancrer à côté d'elle : ancré, il
/// ne laisserait presque rien au média. En plein écran, toujours.
bool panelIsDrawer({
  required double windowWidth,
  required double panelWidth,
  required bool fullscreen,
}) =>
    fullscreen ||
    windowWidth - panelWidth - PanelResizeHandle.width < OmniaMetrics.panelDrawerBreakpoint;

/// Le panneau de dossier : la fonctionnalité signature d'OMNIA.
///
/// Il apparaît dès qu'un fichier est ouvert et liste tous les fichiers
/// lisibles du dossier parent. Recherche, filtre par type, tri, et navigation
/// au simple clic.
class SidePanel extends ConsumerStatefulWidget {
  const SidePanel({super.key, this.drawer = false});

  /// Posé par-dessus la scène (fenêtre étroite, plein écran) plutôt qu'ancré
  /// à côté d'elle : le média garde alors toute la largeur.
  final bool drawer;

  /// Bande de scène laissée libre à droite du tiroir : de quoi viser le voile
  /// pour le refermer.
  static const double drawerPeek = 56;

  @override
  ConsumerState<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends ConsumerState<SidePanel> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'omnia.panel.search');

  /// Dernier index suivi, pour ne défiler que lorsqu'il change vraiment.
  int _followedIndex = -1;

  /// Onglet affiché quand un PDF est ouvert (dossier, sommaire, pages).
  PanelTab _tab = PanelTab.folder;

  @override
  void initState() {
    super.initState();
    // Le panneau est remonté à chaque changement de présentation (ancré,
    // tiroir, plein écran) : le champ reprend la recherche en cours.
    final query = ref.read(playlistStateProvider).query;
    if (query.isNotEmpty) _search.text = query;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Amène l'élément en cours au centre de la liste, sans à-coup.
  void _followCurrent(int index) {
    if (index < 0 || !_scroll.hasClients) return;
    const extent = PlaylistTile.tileHeight;
    final viewport = _scroll.position.viewportDimension;
    final target = (index * extent) - (viewport / 2) + (extent / 2);
    final clamped = target.clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      clamped,
      duration: OmniaMotion.panel,
      curve: OmniaMotion.panelCurve,
    );
  }

  void _openContextMenu(BuildContext context, Offset position, PlaylistEntry entry) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;

    showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<VoidCallback>(
          height: 36,
          value: () => ref.dispatch(OpenFile(entry.path)),
          child: _MenuRow(icon: Icons.play_arrow_rounded, label: l10n.contextPlay),
        ),
        PopupMenuItem<VoidCallback>(
          height: 36,
          value: () => ref.dispatch(RevealInFolder(entry.path)),
          child: _MenuRow(icon: Icons.folder_open_rounded, label: l10n.contextReveal),
        ),
        PopupMenuDivider(height: 9, color: colors.seam),
        PopupMenuItem<VoidCallback>(
          height: 36,
          value: () => ref.dispatch(RemoveFromPlaylist(entry.path)),
          child: _MenuRow(icon: Icons.close_rounded, label: l10n.contextRemove),
        ),
      ],
    ).then((action) => action?.call());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final panel = ref.watch(panelStateProvider);
    final playlist = ref.watch(playlistStateProvider);
    final pdf = ref.watch(pdfSessionProvider);
    // Sans PDF, seul l'onglet « dossier » a un sens.
    final tab = pdf == null ? PanelTab.folder : _tab;

    // Le core peut réinitialiser la recherche (changement de dossier) : le
    // champ doit suivre. On passe par `ref.listen`, dont le rappel s'exécute
    // hors de `build` : modifier un TextEditingController pendant la
    // construction réveillerait le champ en plein build, ce qui est interdit.
    ref.listen<String>(playlistStateProvider.select((s) => s.query), (_, query) {
      if (_search.text == query) return;
      _search.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    });

    // Suivi automatique du fichier en cours.
    final index = playlist.currentIndex;
    if (index != _followedIndex) {
      _followedIndex = index;
      WidgetsBinding.instance.addPostFrameCallback((_) => _followCurrent(index));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // En tiroir, le panneau garde sa largeur choisie tant qu'elle laisse
        // une bande de scène à droite ; sinon il se resserre.
        final open = widget.drawer || panel.visible;
        final double width;
        if (!open) {
          width = 0;
        } else if (widget.drawer && constraints.hasBoundedWidth) {
          width = math.min(
            panel.width,
            math.max(0.0, constraints.maxWidth - SidePanel.drawerPeek),
          );
        } else {
          width = panel.width;
        }

        return Listener(
          onPointerDown: (_) => ref.read(documentUiProvider.notifier).setDocumentFocused(false),
          behavior: HitTestBehavior.translucent,
          child: AnimatedContainer(
            duration: OmniaMotion.panel,
            curve: OmniaMotion.panelCurve,
            width: width,
            decoration: BoxDecoration(
              color: colors.curtain,
              border: Border(right: BorderSide(color: colors.seam)),
              // Posé sur la scène, le tiroir se détache par une ombre portée.
              boxShadow: widget.drawer
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: OmniaMetrics.overlayShadowAlpha),
                        blurRadius: OmniaMetrics.overlayShadowBlur,
                      ),
                    ]
                  : null,
            ),
            // Replié, le panneau ne construit rien : une liste de plusieurs
            // milliers de lignes n'a pas à être mesurée, ni ses champs à rester
            // atteignables au clavier, pendant qu'elle est invisible.
            child: !open
                ? null
                : ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: width,
                      maxWidth: width,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PanelHeader(playlist: playlist),
                          if (pdf != null)
                            PanelTabBar(
                              selected: tab,
                              onSelected: (t) => setState(() => _tab = t),
                            ),
                          if (tab == PanelTab.folder) ...[
                            _SearchField(
                              controller: _search,
                              focusNode: _searchFocus,
                              onChanged: (value) => ref.dispatch(SetPlaylistQuery(value)),
                            ),
                            const _FilterRow(),
                        ],
                        Divider(height: 1, thickness: 1, color: colors.seam),
                        Expanded(
                          child: switch (tab) {
                            PanelTab.folder => _PanelBody(
                                playlist: playlist,
                                scroll: _scroll,
                                // En tiroir, ouvrir un fichier referme le
                                // panneau : on veut voir ce qu'on a choisi.
                                closeOnOpen: widget.drawer,
                                onContextMenu: _openContextMenu,
                              ),
                            PanelTab.outline => OutlinePanel(session: pdf!),
                            PanelTab.pages => ThumbnailsPanel(session: pdf!),
                          },
                        ),
                      ],
                    ),
                  ),
                ),
          ),
        );
      },
    );
  }
}

/// En-tête : nom du dossier, nombre de fichiers, tri et bouton de repli.
class _PanelHeader extends ConsumerWidget {
  const _PanelHeader({required this.playlist});

  final PlaylistState playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final folder = playlist.folder;
    final total = playlist.entries.length;
    final shown = playlist.visible.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OmniaMetrics.space3,
        OmniaMetrics.space3,
        OmniaMetrics.space2,
        OmniaMetrics.space2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  folder == null ? l10n.appTitle : p.basename(folder),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.bodyStrong,
                ),
                const SizedBox(height: 2),
                Text(
                  shown == total
                      ? l10n.panelFileCount(total)
                      : l10n.panelFileCountFiltered(shown, total),
                  style: type.caption,
                ),
              ],
            ),
          ),
          const _SortButton(),
          OmniaIconButton(
            icon: Icons.keyboard_double_arrow_left_rounded,
            size: OmniaMetrics.iconButtonSize - 4,
            iconSize: OmniaMetrics.iconSize - 2,
            tooltip: ref.tooltipWith(l10n.panelHide, ShortcutAction.toggleSidePanel, l10n),
            onPressed: () => ref.dispatch(const ToggleSidePanel()),
          ),
        ],
      ),
    );
  }
}

class _SortButton extends ConsumerWidget {
  const _SortButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final state = ref.watch(playlistStateProvider);

    String labelFor(PlaylistSort sort) => switch (sort) {
          PlaylistSort.name => l10n.sortName,
          PlaylistSort.date => l10n.sortDate,
          PlaylistSort.size => l10n.sortSize,
          PlaylistSort.type => l10n.sortType,
        };

    return PopupMenuButton<PlayerCommand>(
      tooltip: l10n.sortLabel,
      position: PopupMenuPosition.under,
      onSelected: ref.dispatch,
      itemBuilder: (context) => [
        for (final sort in PlaylistSort.values)
          PopupMenuItem<PlayerCommand>(
            height: 36,
            value: SetPlaylistSort(sort, descending: state.descending),
            child: _MenuRow(
              icon: state.sort == sort ? Icons.check_rounded : null,
              label: labelFor(sort),
              active: state.sort == sort,
            ),
          ),
        PopupMenuDivider(height: 9, color: colors.seam),
        PopupMenuItem<PlayerCommand>(
          height: 36,
          value: SetPlaylistSort(state.sort, descending: !state.descending),
          child: _MenuRow(
            icon: state.descending
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            label: state.descending ? l10n.sortDescending : l10n.sortAscending,
          ),
        ),
      ],
      child: SizedBox(
        width: OmniaMetrics.iconButtonSize - 4,
        height: OmniaMetrics.iconButtonSize - 4,
        child: Icon(
          Icons.swap_vert_rounded,
          size: OmniaMetrics.iconSize - 2,
          color: colors.dust,
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.label, this.icon, this.active = false});

  final String label;
  final IconData? icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Row(
      children: [
        SizedBox(
          width: 22,
          child: icon == null
              ? null
              : Icon(icon, size: 15, color: active ? colors.projector : colors.dust),
        ),
        Text(
          label,
          style: type.body.copyWith(color: active ? colors.projector : colors.screen),
        ),
      ],
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  @override
  void initState() {
    super.initState();
    // La bordure change de couleur au focus : il faut donc se reconstruire.
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final hasText = widget.controller.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OmniaMetrics.space3,
        0,
        OmniaMetrics.space3,
        OmniaMetrics.space2,
      ),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: OmniaMetrics.space2),
        decoration: BoxDecoration(
          color: colors.velvet,
          borderRadius: const BorderRadius.all(Radius.circular(OmniaMetrics.radiusSmall)),
          border: Border.all(
            color: widget.focusNode.hasFocus ? colors.projector : colors.seam,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 15, color: colors.dust),
            const SizedBox(width: OmniaMetrics.space2),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                style: type.body,
                cursorColor: colors.projector,
                cursorWidth: 1.5,
                onChanged: (value) {
                  setState(() {});
                  widget.onChanged(value);
                },
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: l10n.panelSearchPlaceholder,
                  hintStyle: type.secondary,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
            if (hasText)
              OmniaIconButton(
                icon: Icons.close_rounded,
                size: 20,
                iconSize: 13,
                tooltip: l10n.clearSearch,
                onPressed: () {
                  widget.controller.clear();
                  setState(() {});
                  widget.onChanged('');
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterRow extends ConsumerWidget {
  const _FilterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final active = ref.watch(playlistStateProvider.select((s) => s.filter));

    String labelFor(PlaylistFilter f) => switch (f) {
          PlaylistFilter.all => l10n.filterAll,
          PlaylistFilter.video => l10n.filterVideo,
          PlaylistFilter.audio => l10n.filterAudio,
          PlaylistFilter.documents => l10n.filterDocuments,
          PlaylistFilter.images => l10n.filterImages,
        };


    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OmniaMetrics.space3,
        0,
        OmniaMetrics.space3,
        OmniaMetrics.space2,
      ),
      // Wrap plutôt que Row : dans un panneau étroit, ou avec une traduction
      // plus longue, les filtres passent à la ligne au lieu de déborder.
      child: Wrap(
        spacing: OmniaMetrics.space1,
        runSpacing: OmniaMetrics.space1,
        children: [
          for (final filter in PlaylistFilter.values)
            _FilterChip(
              label: labelFor(filter),
              selected: filter == active,
              onTap: () => ref.dispatch(SetPlaylistFilter(filter)),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatefulWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: OmniaMotion.hover,
          curve: OmniaMotion.hoverCurve,
          padding: const EdgeInsets.symmetric(
            horizontal: OmniaMetrics.space2,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: widget.selected
                ? colors.projector.withValues(alpha: 0.16)
                : (_hovered ? colors.hover : Colors.transparent),
            borderRadius:
                const BorderRadius.all(Radius.circular(OmniaMetrics.radiusSmall)),
          ),
          child: Text(
            widget.label,
            style: type.caption.copyWith(
              color: widget.selected ? colors.projector : colors.dust,
              fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelBody extends ConsumerWidget {
  const _PanelBody({
    required this.playlist,
    required this.scroll,
    required this.closeOnOpen,
    required this.onContextMenu,
  });

  final PlaylistState playlist;
  final ScrollController scroll;

  /// Referme le panneau après l'ouverture d'un fichier (mode tiroir).
  final bool closeOnOpen;
  final void Function(BuildContext, Offset, PlaylistEntry) onContextMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final visible = playlist.visible;

    if (playlist.scanning && visible.isEmpty) {
      return _PanelMessage(message: l10n.panelScanning, busy: true);
    }
    if (playlist.folder == null) {
      return _PanelMessage(message: l10n.panelNoFolder);
    }
    if (visible.isEmpty) {
      return _PanelMessage(
        message: playlist.query.trim().isEmpty
            ? l10n.panelEmpty
            : l10n.panelNoResults(playlist.query.trim()),
      );
    }

    return Scrollbar(
      controller: scroll,
      child: ListView.builder(
        controller: scroll,
        itemExtent: PlaylistTile.tileHeight,
        itemCount: visible.length,
        // La liste peut compter des milliers d'entrées : on garde le cache
        // d'écran par défaut et une hauteur fixe pour un défilement fluide.
        itemBuilder: (context, i) {
          final entry = visible[i];
          return PlaylistTile(
            key: ValueKey(entry.path),
            entry: entry,
            current: entry.path == playlist.currentPath,
            onTap: () {
              ref.dispatch(OpenFile(entry.path));
              if (closeOnOpen) ref.dispatch(const SetSidePanelVisible(false));
            },
            onSecondaryTap: (position) => onContextMenu(context, position, entry),
          );
        },
      ),
    );
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({required this.message, this.busy = false});

  final String message;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(OmniaMetrics.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: OmniaMetrics.space3),
            ],
            Text(message, style: type.secondary, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Poignée de redimensionnement, entre le panneau et la scène.
class PanelResizeHandle extends ConsumerStatefulWidget {
  const PanelResizeHandle({super.key});

  /// Largeur de la zone de préhension, en pixels.
  static const double width = 6;

  /// Largeur maximale du panneau ancré dans une fenêtre de [windowWidth] :
  /// au-delà, il basculerait en tiroir en plein glissement, et la poignée
  /// disparaîtrait sous le curseur.
  static double maxDockedWidth(double windowWidth) =>
      windowWidth - OmniaMetrics.panelDrawerBreakpoint - width;

  @override
  ConsumerState<PanelResizeHandle> createState() => _PanelResizeHandleState();
}

class _PanelResizeHandleState extends ConsumerState<PanelResizeHandle> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _active = true),
      onExit: (_) => setState(() => _active = false),
      child: Tooltip(
        message: l10n.resizePanel,
        waitDuration: const Duration(seconds: 1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // La largeur suit la position absolue du curseur, et non un cumul de
          // déplacements : une fois la largeur bornée au minimum ou au maximum,
          // un cumul décrocherait la poignée du curseur.
          onHorizontalDragUpdate: (details) {
            final maxWidth =
                PanelResizeHandle.maxDockedWidth(MediaQuery.sizeOf(context).width);
            ref.read(panelStateProvider.notifier).setWidth(
                  math.min(details.globalPosition.dx - PanelResizeHandle.width / 2, maxWidth),
                );
          },
          child: SizedBox(
            width: PanelResizeHandle.width,
            child: Center(
              child: AnimatedContainer(
                duration: OmniaMotion.hover,
                curve: OmniaMotion.hoverCurve,
                width: _active ? 2 : 1,
                color: _active ? colors.projector : Colors.transparent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La languette : le bord du panneau replié, fondu dans le côté gauche de la
/// scène (façon PotPlayer).
///
/// Une bande étroite, un chevron, rien de plus : le média garde toute sa
/// largeur. Elle s'élargit sous le pointeur, suit le masquage automatique des
/// contrôles, et se retient visible tant qu'on la survole.
class PanelEdgeTab extends ConsumerStatefulWidget {
  const PanelEdgeTab({super.key});

  /// Largeur au repos, puis sous le pointeur ou au clavier.
  static const double restWidth = 14;
  static const double hoverWidth = 22;
  static const double height = 72;

  @override
  ConsumerState<PanelEdgeTab> createState() => _PanelEdgeTabState();
}

class _PanelEdgeTabState extends ConsumerState<PanelEdgeTab> {
  bool _hovered = false;
  bool _focused = false;

  /// Ce qui retient les contrôles affichés pendant qu'on vise la languette :
  /// elle ne doit pas s'effacer sous le pointeur.
  static const _hold = 'chrome:panel-tab';

  late final ChromeController _chrome = ref.read(chromeProvider.notifier);

  @override
  void dispose() {
    _chrome.release(_hold);
    super.dispose();
  }

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);
    if (hovered) {
      _chrome.activity();
      _chrome.hold(_hold);
    } else {
      _chrome.release(_hold);
    }
  }

  void _open() {
    _chrome.activity();
    ref.dispatch(const ToggleSidePanel());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);
    final visible = ref.watch(chromeProvider);
    final wide = _hovered || _focused;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: OmniaMotion.reveal,
        curve: visible ? OmniaMotion.revealCurve : OmniaMotion.concealCurve,
        child: Tooltip(
          message: ref.tooltipWith(l10n.panelShow, ShortcutAction.toggleSidePanel, l10n),
          child: Semantics(
            button: true,
            label: l10n.panelShow,
            child: FocusableActionDetector(
              mouseCursor: SystemMouseCursors.click,
              onShowHoverHighlight: _setHovered,
              onShowFocusHighlight: (focused) => setState(() => _focused = focused),
              // Espace et Entrée ouvrent la languette qui a le focus. Sans
              // cette table, `Espace` serait interceptée plus haut par les
              // raccourcis du lecteur (lecture/pause) et n'arriverait jamais
              // jusqu'ici : la languette resterait inutilisable au clavier.
              shortcuts: const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
              },
              actions: <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    _open();
                    return null;
                  },
                ),
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _open,
                child: AnimatedContainer(
                  duration: OmniaMotion.hover,
                  curve: OmniaMotion.hoverCurve,
                  width: wide ? PanelEdgeTab.hoverWidth : PanelEdgeTab.restWidth,
                  height: PanelEdgeTab.height,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.curtain.withValues(alpha: wide ? 0.92 : 0.72),
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(OmniaMetrics.radiusMedium + 2),
                    ),
                    border: Border.all(color: colors.screen.withValues(alpha: 0.08)),
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 12,
                    color: colors.projector.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
