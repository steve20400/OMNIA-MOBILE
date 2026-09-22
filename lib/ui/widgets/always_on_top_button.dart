import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../shortcuts/default_keymap.dart';
import '../shortcuts/shortcut_labels.dart';
import '../theme/omnia_theme.dart';
import 'omnia_icon_button.dart';
import 'omnia_menu.dart';

/// Bouton « Toujours au premier plan » de la barre de titre et des commandes,
/// décliné en deux catégories : mini-lecteur et lecteur normal.
///
/// Un clic simple bascule le mode courant. Un clic droit ou le menu déroulant
/// permet de choisir spécifiquement pour le lecteur normal et le mini-lecteur.
class AlwaysOnTopButton extends ConsumerWidget {
  const AlwaysOnTopButton({
    super.key,
    this.size,
    this.iconSize,
  });

  final double? size;
  final double? iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(playbackStateProvider);
    final prefs = ref.watch(preferencesProvider);
    final isMini = state.miniPlayer;
    final isOnTop = state.alwaysOnTop;

    return MenuAnchor(
      consumeOutsideTap: true,
      alignmentOffset: const Offset(0, OmniaMetrics.space1),
      menuChildren: [
        OmniaMenuHeader(l10n.alwaysOnTop),
        OmniaMenuItem(
          icon: prefs.normalPlayerAlwaysOnTop
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded,
          label: l10n.alwaysOnTopNormal,
          active: prefs.normalPlayerAlwaysOnTop,
          onPressed: () => ref.dispatch(const ToggleAlwaysOnTop(forMiniPlayer: false)),
        ),
        OmniaMenuItem(
          icon: prefs.miniPlayerAlwaysOnTop
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded,
          label: l10n.alwaysOnTopMini,
          active: prefs.miniPlayerAlwaysOnTop,
          onPressed: () => ref.dispatch(const ToggleAlwaysOnTop(forMiniPlayer: true)),
        ),
      ],
      builder: (context, controller, _) => GestureDetector(
        onSecondaryTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: OmniaIconButton(
          icon: isOnTop ? Icons.push_pin_rounded : Icons.push_pin_outlined,
          iconSize: iconSize ?? OmniaMetrics.iconSize - 2,
          size: size ?? OmniaMetrics.iconButtonSize - 4,
          active: isOnTop,
          tooltip: ref.tooltipWith(
            '${l10n.alwaysOnTop} (${isMini ? l10n.alwaysOnTopMini : l10n.alwaysOnTopNormal})',
            ShortcutAction.alwaysOnTop,
            l10n,
          ),
          onPressed: () => ref.dispatch(const ToggleAlwaysOnTop()),
        ),
      ),
    );
  }
}
