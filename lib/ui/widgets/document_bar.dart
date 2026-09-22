import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/document_layout.dart';
import '../../core/models/media_type.dart';
import '../../core/models/playback_state.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../document_ui_controller.dart';
import '../player_focus.dart';
import '../shortcuts/default_keymap.dart';
import '../shortcuts/shortcut_labels.dart';
import '../theme/omnia_theme.dart';
import 'chrome_menu_anchor.dart';
import 'control_layout.dart';
import 'floating_surface.dart';
import 'omnia_icon_button.dart';
import 'omnia_menu.dart';

/// Barre flottante des documents, à la place de la barre de contrôles média :
/// navigation par page, zoom, ajustement, rotation, mode sombre, défilement,
/// recherche. Même surface, même langage que la barre de lecture.
///
/// Comme elle, elle suit la largeur de la scène : les outils qui ne tiennent
/// plus passent dans le menu « ⋯ », qui n'apparaît que dans ce cas
/// ([fitDocumentControls]). La navigation par page et la recherche restent
/// toujours dans la barre. Chaque ligne du menu émet sur le bus la même
/// commande que le bouton qu'elle remplace.
class DocumentBar extends ConsumerStatefulWidget {
  const DocumentBar({super.key});

  @override
  ConsumerState<DocumentBar> createState() => _DocumentBarState();
}

/// Commandes de la barre de documents, dans l'ordre de la barre.
///
/// Priorités ([ControlSlot.priority] : 0, toujours visible ; plus le nombre
/// est grand, plus la commande cède tôt sa place au menu « ⋯ ») :
/// - 0 : page précédente, champ de page, page suivante, recherche ;
/// - 1 : nombre de pages (« / 120 ») ;
/// - 2 : réservée au bouton « Modifier » des textes, qui viendra à côté de
///   la recherche (dans [trailing]) : il ne cédera qu'après tous les outils ;
/// - 3 : séparateur, qui ne s'affiche que devant un outil visible ;
/// - 4 : zoom (−, valeur, +), d'un seul bloc ;
/// - 5 : mode sombre de lecture ;
/// - 6 à 9 : ajuster à la largeur, à la page, rotation, mise en page.
abstract final class DocumentBarSlots {
  static const pageUp = 'pageUp';
  static const pageField = 'pageField';
  static const pageTotal = 'pageTotal';
  static const pageDown = 'pageDown';
  static const separator = 'separator';
  static const zoomOut = 'zoomOut';
  static const zoomValue = 'zoomValue';
  static const zoomIn = 'zoomIn';
  static const fitWidth = 'fitWidth';
  static const fitPage = 'fitPage';
  static const rotate = 'rotate';
  static const layout = 'layout';
  static const readingDark = 'readingDark';
  static const edit = 'edit';
  static const save = 'save';
  static const miniPlayer = 'miniPlayer';
  static const find = 'find';

  /// Le zoom se montre ou part au menu d'un bloc : un « − » seul, sans sa
  /// valeur ni son « + », ne voudrait rien dire.
  static const zoomGroup = {zoomOut, zoomValue, zoomIn};

  /// Commandes rangées à droite, après l'espace libre ; les autres à gauche.
  static const trailing = {readingDark, edit, save, miniPlayer, find};
}

/// Répartit les commandes de la barre de documents : [fitControls], puis deux
/// règles propres aux documents.
///
/// - Le zoom ([DocumentBarSlots.zoomGroup]) reste d'un bloc : si l'une de ses
///   commandes part au menu, les trois y vont.
/// - Le séparateur ne s'affiche que suivi d'un outil visible à sa droite, et
///   ne va jamais au menu : il n'aurait rien à y mettre.
ControlFit fitDocumentControls(
  List<ControlSlot> slots,
  double available, {
  required double overflowWidth,
}) {
  final fit = fitControls(slots, available, overflowWidth: overflowWidth);
  final ids = [for (final s in slots) s.id];
  final hidden = fit.overflow.toSet();
  if (hidden.any(DocumentBarSlots.zoomGroup.contains)) {
    hidden.addAll(DocumentBarSlots.zoomGroup);
  }

  final shown = [for (final id in ids) if (!hidden.contains(id)) id];
  final separator = shown.indexOf(DocumentBarSlots.separator);
  if (separator >= 0 &&
      !shown.skip(separator + 1).any((id) => !DocumentBarSlots.trailing.contains(id))) {
    shown.removeAt(separator);
  }

  return ControlFit(
    shown,
    [
      for (final id in ids)
        if (hidden.contains(id) && id != DocumentBarSlots.separator) id,
    ],
  );
}

/// Une commande de la barre : sa place, son widget, et ses lignes dans le
/// menu « ⋯ » quand elle n'a plus de place dans la barre.
class _DocControl {
  const _DocControl(this.slot, this.widget, this.menu);

  final ControlSlot slot;
  final Widget widget;
  final List<Widget> menu;
}

class _DocumentBarState extends ConsumerState<DocumentBar> {
  final TextEditingController _page = TextEditingController();
  final FocusNode _pageFocus = FocusNode(debugLabel: 'omnia.doc.page');
  int _seenGoToRequest = 0;

  /// Place du bouton « ⋯ », marge comprise.
  static const double _overflowWidth = OmniaMetrics.iconButtonSize + OmniaMetrics.space2;

  /// Bordure d'un pixel de [FloatingSurface], de chaque côté.
  static const double _surfaceBorder = 1;

  static const double _pageFieldWidth = 52;
  static const double _zoomValueWidth = 56;

  @override
  void dispose() {
    _page.dispose();
    _pageFocus.dispose();
    super.dispose();
  }

  void _submitPage(String value) {
    final page = int.tryParse(value.trim());
    if (page != null) ref.dispatch(GoToPage(page));
    // Rendre la main au lecteur : PgUp / PgDn doivent marcher tout de suite.
    ref.read(playerFocusProvider).restore();
  }

  /// Largeur d'un texte d'une ligne, mise à l'échelle du texte comprise.
  static double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playbackStateProvider);
    final ui = ref.watch(documentUiProvider);

    // Le champ suit la page courante, sauf pendant la saisie.
    final pageText = state.currentPage > 0 ? '${state.currentPage}' : '';
    if (!_pageFocus.hasFocus && _page.text != pageText) {
      _page.value = TextEditingValue(
        text: pageText,
        selection: TextSelection.collapsed(offset: pageText.length),
      );
    }

    // `Ctrl+G` : focus sur le champ de page, texte sélectionné.
    if (ui.goToPageRequest != _seenGoToRequest) {
      _seenGoToRequest = ui.goToPageRequest;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pageFocus.requestFocus();
        _page.selection = TextSelection(baseOffset: 0, extentOffset: _page.text.length);
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const margin = OmniaMetrics.controlBarMargin;
        final available = constraints.hasBoundedWidth
            ? math.max(0.0, constraints.maxWidth - 2 * margin)
            : OmniaMetrics.controlBarMaxWidth;
        final barWidth = math.min(OmniaMetrics.controlBarMaxWidth, available);
        final rowWidth = math.max(
          0.0,
          barWidth - 2 * OmniaMetrics.controlBarPadding - 2 * _surfaceBorder,
        );

        return Padding(
          padding: const EdgeInsets.all(margin),
          child: Center(
            child: SizedBox(
              width: barWidth,
              child: FloatingSurface(
                padding: const EdgeInsets.symmetric(
                  horizontal: OmniaMetrics.controlBarPadding,
                  vertical: OmniaMetrics.space2,
                ),
                child: _row(context, state, ui, rowWidth),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, PlaybackState state, DocumentUiState ui, double rowWidth) {
    final controls = _controls(context, state, ui);
    final fit = fitDocumentControls(
      [for (final c in controls) c.slot],
      // Un pixel de marge : un arrondi de mesure du texte ne doit jamais faire
      // déborder la rangée.
      rowWidth - 1,
      overflowWidth: _overflowWidth,
    );
    final byId = {for (final c in controls) c.slot.id: c};

    return Row(
      children: [
        for (final id in fit.shown)
          if (!DocumentBarSlots.trailing.contains(id)) byId[id]!.widget,
        const Spacer(),
        for (final id in fit.shown)
          if (DocumentBarSlots.trailing.contains(id)) byId[id]!.widget,
        if (fit.hasOverflow)
          _OverflowMenu(
            children: [
              for (final id in fit.overflow) ...byId[id]!.menu,
            ],
          ),
      ],
    );
  }

  List<_DocControl> _controls(BuildContext context, PlaybackState state, DocumentUiState ui) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);

    final isPdf = state.mediaType == MediaType.pdf;
    final hasPages = isPdf && state.totalPages > 0;
    final canGoBack = state.currentPage > 1;
    final canGoForward = state.currentPage < state.totalPages;
    final pageTotal = '/ ${state.totalPages}';
    final goToPageTooltip = ref.tooltipWith(l10n.docGoToPage, ShortcutAction.goToPage, l10n);
    final zoomLabel = l10n.docZoomValue((state.zoom * 100).round());
    final continuous = state.documentLayout == DocumentLayout.continuous;
    final layoutIcon = continuous ? Icons.view_agenda_outlined : Icons.view_day_outlined;
    final layoutLabel = continuous ? l10n.docLayoutPaged : l10n.docLayoutContinuous;
    final darkIcon = state.readingDark ? Icons.dark_mode_rounded : Icons.dark_mode_outlined;

    const icon = OmniaMetrics.iconButtonSize;

    return [
      if (hasPages) ...[
        _DocControl(
          const ControlSlot(id: DocumentBarSlots.pageUp, width: icon, priority: 0),
          OmniaIconButton(
            icon: Icons.keyboard_arrow_up_rounded,
            tooltip: ref.tooltipWith(l10n.docPreviousPage, ShortcutAction.previousPage, l10n),
            onPressed: canGoBack ? () => ref.dispatch(const PreviousPage()) : null,
          ),
          const [],
        ),
        _DocControl(
          const ControlSlot(id: DocumentBarSlots.pageField, width: _pageFieldWidth, priority: 0),
          _PageField(
            controller: _page,
            focusNode: _pageFocus,
            onSubmitted: _submitPage,
            tooltip: goToPageTooltip,
          ),
          const [],
        ),
        _DocControl(
          ControlSlot(
            id: DocumentBarSlots.pageTotal,
            width: OmniaMetrics.space2 + _textWidth(context, pageTotal, type.timecode),
            priority: 1,
          ),
          Tooltip(
            message: goToPageTooltip,
            child: Padding(
              padding: const EdgeInsets.only(left: OmniaMetrics.space2),
              child: Text(pageTotal, style: type.timecode.copyWith(color: colors.dust)),
            ),
          ),
          [
            // Simple repère : la page se change par le champ, toujours visible.
            OmniaMenuItem(
              icon: Icons.description_outlined,
              label: '${state.currentPage} $pageTotal',
              enabled: false,
              onPressed: null,
            ),
          ],
        ),
        _DocControl(
          const ControlSlot(id: DocumentBarSlots.pageDown, width: icon, priority: 0),
          OmniaIconButton(
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: ref.tooltipWith(l10n.docNextPage, ShortcutAction.nextPage, l10n),
            onPressed: canGoForward ? () => ref.dispatch(const NextPage()) : null,
          ),
          const [],
        ),
        _DocControl(
          const ControlSlot(
            id: DocumentBarSlots.separator,
            width: 2 * OmniaMetrics.space3 + 1,
            priority: 3,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: OmniaMetrics.space3),
            child: _Separator(color: colors.seam),
          ),
          const [],
        ),
      ],
      _DocControl(
        const ControlSlot(id: DocumentBarSlots.zoomOut, width: icon, priority: 4),
        OmniaIconButton(
          icon: Icons.remove_rounded,
          tooltip: '${l10n.docZoomOut}  ·  ${l10n.keyCtrlWheel}',
          onPressed: () => ref.dispatch(const ZoomRelative(1 / 1.2)),
        ),
        [
          OmniaMenuItem(
            icon: Icons.remove_rounded,
            label: l10n.docZoomOut,
            trailing: l10n.keyCtrlWheel,
            onPressed: () => ref.dispatch(const ZoomRelative(1 / 1.2)),
          ),
        ],
      ),
      _DocControl(
        const ControlSlot(id: DocumentBarSlots.zoomValue, width: _zoomValueWidth, priority: 4),
        Tooltip(
          message: isPdf ? l10n.docFitWidth : l10n.docFontSize,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ref.dispatch(const FitZoom(FitMode.width)),
            child: SizedBox(
              width: _zoomValueWidth,
              child: Text(
                zoomLabel,
                style: type.timecode,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        [
          // Pour un PDF, le clic sur la valeur ajuste à la largeur : la ligne
          // « Ajuster à la largeur » est déjà au menu (elle y part avant le
          // zoom), celle-ci ne fait que donner la valeur.
          if (isPdf)
            OmniaMenuItem(
              icon: Icons.zoom_in_rounded,
              label: zoomLabel,
              enabled: false,
              onPressed: null,
            )
          else
            OmniaMenuItem(
              icon: Icons.zoom_in_rounded,
              label: l10n.docFontSize,
              trailing: zoomLabel,
              onPressed: () => ref.dispatch(const FitZoom(FitMode.width)),
            ),
        ],
      ),
      _DocControl(
        const ControlSlot(id: DocumentBarSlots.zoomIn, width: icon, priority: 4),
        OmniaIconButton(
          icon: Icons.add_rounded,
          tooltip: '${l10n.docZoomIn}  ·  ${l10n.keyCtrlWheel}',
          onPressed: () => ref.dispatch(const ZoomRelative(1.2)),
        ),
        [
          OmniaMenuItem(
            icon: Icons.add_rounded,
            label: l10n.docZoomIn,
            trailing: l10n.keyCtrlWheel,
            onPressed: () => ref.dispatch(const ZoomRelative(1.2)),
          ),
        ],
      ),
      if (isPdf) ...[
        _DocControl(
          const ControlSlot(id: DocumentBarSlots.fitWidth, width: icon, priority: 6),
          OmniaIconButton(
            icon: Icons.fit_screen_outlined,
            tooltip: ref.tooltipWith(l10n.docFitWidth, ShortcutAction.fitZoom, l10n),
            onPressed: () => ref.dispatch(const FitZoom(FitMode.width)),
          ),
          [
            OmniaMenuItem(
              icon: Icons.fit_screen_outlined,
              label: l10n.docFitWidth,
              trailing: ref.shortcutOf(ShortcutAction.fitZoom, l10n),
              onPressed: () => ref.dispatch(const FitZoom(FitMode.width)),
            ),
          ],
        ),
        _DocControl(
          const ControlSlot(id: DocumentBarSlots.fitPage, width: icon, priority: 7),
          OmniaIconButton(
            icon: Icons.crop_portrait_rounded,
            tooltip: l10n.docFitPage,
            onPressed: () => ref.dispatch(const FitZoom(FitMode.page)),
          ),
          [
            OmniaMenuItem(
              icon: Icons.crop_portrait_rounded,
              label: l10n.docFitPage,
              onPressed: () => ref.dispatch(const FitZoom(FitMode.page)),
            ),
          ],
        ),
        _DocControl(
          const ControlSlot(id: DocumentBarSlots.rotate, width: icon, priority: 8),
          OmniaIconButton(
            icon: Icons.rotate_right_rounded,
            tooltip: ref.tooltipWith(l10n.docRotate, ShortcutAction.rotateDocument, l10n),
            active: state.rotation != 0,
            onPressed: () => ref.dispatch(const RotateDocument()),
          ),
          [
            OmniaMenuItem(
              icon: Icons.rotate_right_rounded,
              label: l10n.docRotate,
              active: state.rotation != 0,
              trailing: ref.shortcutOf(ShortcutAction.rotateDocument, l10n),
              onPressed: () => ref.dispatch(const RotateDocument()),
            ),
          ],
        ),
        _DocControl(
          const ControlSlot(id: DocumentBarSlots.layout, width: icon, priority: 9),
          OmniaIconButton(
            icon: layoutIcon,
            tooltip: layoutLabel,
            onPressed: () => ref.dispatch(const ToggleDocumentLayout()),
          ),
          [
            OmniaMenuItem(
              icon: layoutIcon,
              label: layoutLabel,
              onPressed: () => ref.dispatch(const ToggleDocumentLayout()),
            ),
          ],
        ),
      ],
      _DocControl(
        const ControlSlot(id: DocumentBarSlots.readingDark, width: icon, priority: 5),
        OmniaIconButton(
          icon: darkIcon,
          tooltip: ref.tooltipWith(l10n.docReadingDark, ShortcutAction.readingDark, l10n),
          active: state.readingDark,
          onPressed: () => ref.dispatch(const ToggleReadingDarkMode()),
        ),
        [
          OmniaMenuItem(
            icon: darkIcon,
            label: l10n.docReadingDark,
            active: state.readingDark,
            trailing: ref.shortcutOf(ShortcutAction.readingDark, l10n),
            onPressed: () => ref.dispatch(const ToggleReadingDarkMode()),
          ),
        ],
      ),
      // Le bouton « Modifier » et « Enregistrer » pour les fichiers texte/code/bureautique modifiables.
      if (!isPdf && (state.mediaType == MediaType.text || state.mediaType == MediaType.doc)) ...[
        if (ui.isEditing) ...[
          _DocControl(
            const ControlSlot(id: DocumentBarSlots.save, width: icon, priority: 2),
            OmniaIconButton(
              icon: Icons.save_rounded,
              tooltip: 'Enregistrer les modifications  ·  Ctrl+S',
              active: ui.hasUnsavedChanges,
              onPressed: () => ref.read(documentUiProvider.notifier).requestSave(),
            ),
            [
              OmniaMenuItem(
                icon: Icons.save_rounded,
                label: 'Enregistrer les modifications',
                trailing: 'Ctrl+S',
                onPressed: () => ref.read(documentUiProvider.notifier).requestSave(),
              ),
            ],
          ),
          _DocControl(
            const ControlSlot(id: DocumentBarSlots.edit, width: icon, priority: 2),
            OmniaIconButton(
              icon: Icons.visibility_outlined,
              tooltip: 'Terminer la modification (Lecture seule)',
              active: true,
              onPressed: () => ref.read(documentUiProvider.notifier).toggleEdit(),
            ),
            [
              OmniaMenuItem(
                icon: Icons.visibility_outlined,
                label: 'Passer en lecture seule',
                onPressed: () => ref.read(documentUiProvider.notifier).toggleEdit(),
              ),
            ],
          ),
        ] else ...[
          _DocControl(
            const ControlSlot(id: DocumentBarSlots.edit, width: icon, priority: 2),
            OmniaIconButton(
              icon: Icons.edit_outlined,
              tooltip: 'Modifier le document',
              onPressed: () => ref.read(documentUiProvider.notifier).toggleEdit(),
            ),
            [
              OmniaMenuItem(
                icon: Icons.edit_outlined,
                label: 'Modifier le document',
                onPressed: () => ref.read(documentUiProvider.notifier).toggleEdit(),
              ),
            ],
          ),
        ],
      ],
      _DocControl(
        const ControlSlot(id: DocumentBarSlots.miniPlayer, width: icon, priority: 3),
        OmniaIconButton(
          icon: Icons.picture_in_picture_alt_rounded,
          tooltip: ref.tooltipWith(l10n.miniPlayer, ShortcutAction.miniPlayer, l10n),
          onPressed: () => ref.dispatch(const ToggleMiniPlayer()),
        ),
        [
          OmniaMenuItem(
            icon: Icons.picture_in_picture_alt_rounded,
            label: l10n.miniPlayer,
            trailing: ref.shortcutOf(ShortcutAction.miniPlayer, l10n),
            onPressed: () => ref.dispatch(const ToggleMiniPlayer()),
          ),
        ],
      ),
      _DocControl(
        const ControlSlot(id: DocumentBarSlots.find, width: icon, priority: 0),
        OmniaIconButton(
          icon: Icons.search_rounded,
          tooltip: ref.tooltipWith(l10n.docFind, ShortcutAction.find, l10n),
          active: ui.findVisible,
          onPressed: () => ref.read(documentUiProvider.notifier).toggleFind(),
        ),
        const [],
      ),
    ];
  }
}

class _PageField extends StatelessWidget {
  const _PageField({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.tooltip,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Tooltip(
      message: tooltip,
      child: Container(
        width: _DocumentBarState._pageFieldWidth,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.velvet,
          borderRadius: const BorderRadius.all(Radius.circular(OmniaMetrics.radiusSmall)),
          border: Border.all(color: colors.seam),
        ),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          style: type.timecode,
          textAlign: TextAlign.center,
          cursorColor: colors.projector,
          cursorWidth: 1.5,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: onSubmitted,
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 6),
          ),
        ),
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(width: 1, height: 22, child: ColoredBox(color: color));
}

/// Menu « ⋯ » : les outils qui n'ont plus de place dans la barre. Le même
/// que celui de la barre de lecture.
class _OverflowMenu extends ConsumerWidget {
  const _OverflowMenu({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: OmniaMetrics.space2),
      child: ChromeMenuAnchor(
        menuChildren: children,
        builder: (context, controller, _) => OmniaIconButton(
          icon: Icons.more_horiz_rounded,
          tooltip: l10n.moreControls,
          onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
    );
  }
}

/// Utilitaire pour d'autres widgets : le zoom borné d'un PDF.
double clampDocumentZoom(double zoom) =>
    zoom.clamp(PlaybackState.minZoom, PlaybackState.maxZoom);
