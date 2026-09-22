import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/document_layout.dart';
import '../../core/models/playback_state.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../shortcuts/default_keymap.dart';
import '../shortcuts/shortcut_labels.dart';
import '../theme/omnia_theme.dart';
import 'chrome_menu_anchor.dart';
import 'control_layout.dart';
import 'floating_surface.dart';
import 'image_edit_dialog.dart';
import 'omnia_icon_button.dart';
import 'omnia_menu.dart';

/// Barre flottante dédiée au visionneur d'images :
/// navigation dans le dossier (précédente / suivante), zoom (−, 100 %, +),
/// ajuster à la fenêtre, rotation à 90° et plein écran.
class ImageBar extends ConsumerWidget {
  const ImageBar({super.key});

  /// Place du bouton « ⋯ », marge comprise.
  static const double _overflowWidth = OmniaMetrics.iconButtonSize + OmniaMetrics.space2;
  static const double _surfaceBorder = 1;
  static const double _zoomValueWidth = 56;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackStateProvider);

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
                child: _row(context, ref, state, rowWidth),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    PlaybackState state,
    double rowWidth,
  ) {
    final controls = _controls(context, ref, state);
    final fit = fitControls(
      [for (final c in controls) c.slot],
      rowWidth - 1,
      overflowWidth: _overflowWidth,
    );
    final byId = {for (final c in controls) c.slot.id: c};

    return Row(
      children: [
        for (final id in fit.shown)
          if (!_trailingSlots.contains(id)) byId[id]!.widget,
        const Spacer(),
        for (final id in fit.shown)
          if (_trailingSlots.contains(id)) byId[id]!.widget,
        if (fit.hasOverflow)
          _ImageOverflowMenu(
            children: [
              for (final id in fit.overflow) ...byId[id]!.menu,
            ],
          ),
      ],
    );
  }

  static const _trailingSlots = {'miniPlayer', 'fullscreen'};

  List<_ImageControl> _controls(
    BuildContext context,
    WidgetRef ref,
    PlaybackState state,
  ) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    const icon = OmniaMetrics.iconButtonSize;

    final zoomPercent = (state.zoom * 100).round();
    final zoomLabel = '$zoomPercent %';
    final canNavigate = state.playlist.length > 1 || state.hasFile;

    return [
      // Navigation dans le dossier
      _ImageControl(
        const ControlSlot(id: 'prev', width: icon, priority: 0),
        OmniaIconButton(
          icon: Icons.skip_previous_rounded,
          tooltip: ref.tooltipWith(l10n.previousFile, ShortcutAction.previousFile, l10n),
          onPressed: canNavigate ? () => ref.dispatch(const PreviousFile()) : null,
        ),
        [
          OmniaMenuItem(
            icon: Icons.skip_previous_rounded,
            label: l10n.previousFile,
            enabled: canNavigate,
            trailing: ref.shortcutOf(ShortcutAction.previousFile, l10n),
            onPressed: () => ref.dispatch(const PreviousFile()),
          ),
        ],
      ),
      _ImageControl(
        const ControlSlot(id: 'next', width: icon, priority: 0),
        OmniaIconButton(
          icon: Icons.skip_next_rounded,
          tooltip: ref.tooltipWith(l10n.nextFile, ShortcutAction.nextFile, l10n),
          onPressed: canNavigate ? () => ref.dispatch(const NextFile()) : null,
        ),
        [
          OmniaMenuItem(
            icon: Icons.skip_next_rounded,
            label: l10n.nextFile,
            enabled: canNavigate,
            trailing: ref.shortcutOf(ShortcutAction.nextFile, l10n),
            onPressed: () => ref.dispatch(const NextFile()),
          ),
        ],
      ),
      _ImageControl(
        const ControlSlot(id: 'sep1', width: 2 * OmniaMetrics.space2 + 1, priority: 3),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: OmniaMetrics.space2),
          child: SizedBox(width: 1, height: 22, child: ColoredBox(color: colors.seam)),
        ),
        const [],
      ),
      // Zoom
      _ImageControl(
        const ControlSlot(id: 'zoomOut', width: icon, priority: 1),
        OmniaIconButton(
          icon: Icons.remove_rounded,
          tooltip: '${l10n.docZoomOut}  ·  ${l10n.keyCtrlWheel}',
          onPressed: () => ref.dispatch(const ZoomRelative(1 / 1.25)),
        ),
        [
          OmniaMenuItem(
            icon: Icons.remove_rounded,
            label: l10n.docZoomOut,
            trailing: l10n.keyCtrlWheel,
            onPressed: () => ref.dispatch(const ZoomRelative(1 / 1.25)),
          ),
        ],
      ),
      _ImageControl(
        const ControlSlot(id: 'zoomValue', width: _zoomValueWidth, priority: 1),
        Tooltip(
          message: 'Taille originale (100 %)',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ref.dispatch(const SetZoom(1.0)),
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
          OmniaMenuItem(
            icon: Icons.zoom_in_rounded,
            label: 'Réinitialiser le zoom',
            trailing: zoomLabel,
            onPressed: () => ref.dispatch(const SetZoom(1.0)),
          ),
        ],
      ),
      _ImageControl(
        const ControlSlot(id: 'zoomIn', width: icon, priority: 1),
        OmniaIconButton(
          icon: Icons.add_rounded,
          tooltip: '${l10n.docZoomIn}  ·  ${l10n.keyCtrlWheel}',
          onPressed: () => ref.dispatch(const ZoomRelative(1.25)),
        ),
        [
          OmniaMenuItem(
            icon: Icons.add_rounded,
            label: l10n.docZoomIn,
            trailing: l10n.keyCtrlWheel,
            onPressed: () => ref.dispatch(const ZoomRelative(1.25)),
          ),
        ],
      ),
      _ImageControl(
        const ControlSlot(id: 'fit', width: icon, priority: 2),
        OmniaIconButton(
          icon: Icons.fit_screen_outlined,
          tooltip: 'Ajuster à la fenêtre',
          onPressed: () => ref.dispatch(const FitZoom(FitMode.width)),
        ),
        [
          OmniaMenuItem(
            icon: Icons.fit_screen_outlined,
            label: 'Ajuster à la fenêtre',
            onPressed: () => ref.dispatch(const FitZoom(FitMode.width)),
          ),
        ],
      ),
      // Rotation
      _ImageControl(
        const ControlSlot(id: 'rotate', width: icon, priority: 2),
        OmniaIconButton(
          icon: Icons.rotate_right_rounded,
          tooltip: 'Pivoter de 90°',
          active: state.rotation != 0,
          onPressed: () => ref.dispatch(const RotateDocument()),
        ),
        [
          OmniaMenuItem(
            icon: Icons.rotate_right_rounded,
            label: 'Pivoter de 90°',
            active: state.rotation != 0,
            onPressed: () => ref.dispatch(const RotateDocument()),
          ),
        ],
      ),
      // Retoucher et redimensionner l'image
      if (state.file != null)
        _ImageControl(
          const ControlSlot(id: 'editImage', width: icon, priority: 2),
          OmniaIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Retoucher et redimensionner',
            onPressed: () => ImageEditDialog.show(context, state.file!),
          ),
          [
            OmniaMenuItem(
              icon: Icons.tune_rounded,
              label: 'Retoucher et redimensionner...',
              onPressed: () => ImageEditDialog.show(context, state.file!),
            ),
          ],
        ),
      // Mini-lecteur
      _ImageControl(
        const ControlSlot(id: 'miniPlayer', width: icon, priority: 1),
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
      // Plein écran (à droite)
      _ImageControl(
        const ControlSlot(id: 'fullscreen', width: icon, priority: 0),
        OmniaIconButton(
          icon: state.fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          tooltip: ref.tooltipWith(l10n.fullscreen, ShortcutAction.toggleFullscreen, l10n),
          onPressed: () => ref.dispatch(const ToggleFullscreen()),
        ),
        const [],
      ),
    ];
  }
}

class _ImageControl {
  const _ImageControl(this.slot, this.widget, this.menu);

  final ControlSlot slot;
  final Widget widget;
  final List<Widget> menu;
}

class _ImageOverflowMenu extends StatelessWidget {
  const _ImageOverflowMenu({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
