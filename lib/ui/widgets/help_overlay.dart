import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../help_overlay_controller.dart';
import '../player_focus.dart';
import '../settings/settings_controller.dart';
import '../shortcuts/keymap_provider.dart';
import '../shortcuts/shortcut_labels.dart';
import '../theme/omnia_theme.dart';
import 'floating_surface.dart';
import 'key_cap.dart';
import 'omnia_button.dart';
import 'omnia_icon_button.dart';

/// Récapitulatif des raccourcis (`F1`).
///
/// Lu dans la table de l'utilisateur, pas dans une liste figée : un raccourci
/// réaffecté dans les paramètres apparaît ici tel quel, dans la langue de
/// l'interface.
///
/// Dans une petite fenêtre, la carte se fait compacte : marges courtes,
/// bouton « Raccourcis » réduit à son icône, et tout ce qui suit le titre
/// défile. Le titre et la fermeture restent toujours visibles.
class HelpOverlay extends ConsumerWidget {
  const HelpOverlay({super.key});

  /// Fenêtre plus étroite ou plus basse : présentation compacte.
  static const double compactWidth = 560;
  static const double compactHeight = 420;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(helpVisibleProvider);
    final colors = context.colors;

    ref.listen<bool>(helpVisibleProvider, (previous, next) {
      if (previous == true && !next) ref.read(playerFocusProvider).restore();
    });

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: OmniaMotion.reveal,
        curve: visible ? OmniaMotion.revealCurve : OmniaMotion.concealCurve,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(helpVisibleProvider.notifier).hide(),
          child: ColoredBox(
            color: colors.overlayScrim,
            child: Center(
              child: GestureDetector(
                // Un clic dans la carte ne doit pas la fermer.
                onTap: () {},
                child: visible ? const _HelpCard() : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpCard extends ConsumerWidget {
  const _HelpCard();

  static const double _maxWidth = 760;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    final compact =
        size.width < HelpOverlay.compactWidth || size.height < HelpOverlay.compactHeight;
    final margin = compact ? OmniaMetrics.space3 : OmniaMetrics.space5;
    final padding = compact ? OmniaMetrics.space4 : OmniaMetrics.space5;

    void openShortcuts() {
      ref.read(helpVisibleProvider.notifier).hide();
      ref.read(settingsUiProvider.notifier).show(SettingsSection.shortcuts);
    }

    final subtitle = Text(l10n.helpSubtitle, style: type.secondary);
    final groups = Wrap(
      spacing: OmniaMetrics.space6,
      runSpacing: OmniaMetrics.space5,
      children: [
        // Plus étroite que la carte, une colonne se contente de la place.
        for (final group in ShortcutGroup.values)
          SizedBox(width: 320, child: _HelpGroup(group: group)),
      ],
    );
    final footer = Text(
      [
        '${l10n.keyDoubleClick} : ${l10n.fullscreen}',
        '${l10n.keyWheel} : ${l10n.helpVolume}',
        '${l10n.keyCtrlWheel} : ${l10n.docZoomIn}',
      ].join('   ·   '),
      style: type.caption,
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: math.max(0.0, math.min(_maxWidth, size.width - 2 * margin)),
        maxHeight: math.max(0.0, size.height - 2 * margin),
      ),
      child: FloatingSurface(
        padding: EdgeInsets.all(padding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.helpTitle,
                    style: type.viewTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (compact)
                  OmniaIconButton(
                    icon: Icons.keyboard_outlined,
                    tooltip: l10n.settingsSectionShortcuts,
                    onPressed: openShortcuts,
                  )
                else
                  OmniaButton(
                    label: l10n.settingsSectionShortcuts,
                    icon: Icons.keyboard_outlined,
                    onPressed: openShortcuts,
                  ),
                const SizedBox(width: OmniaMetrics.space2),
                OmniaIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '${l10n.helpClose}  ·  ${l10n.keyEscape}',
                  onPressed: () => ref.read(helpVisibleProvider.notifier).hide(),
                ),
              ],
            ),
            if (!compact) ...[
              const SizedBox(height: OmniaMetrics.space2),
              subtitle,
              const SizedBox(height: OmniaMetrics.space4),
            ],
            Flexible(
              child: SingleChildScrollView(
                child: compact
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: OmniaMetrics.space2),
                          subtitle,
                          const SizedBox(height: OmniaMetrics.space4),
                          groups,
                          const SizedBox(height: OmniaMetrics.space4),
                          footer,
                        ],
                      )
                    : groups,
              ),
            ),
            if (!compact) ...[
              const SizedBox(height: OmniaMetrics.space4),
              footer,
            ],
          ],
        ),
      ),
    );
  }
}

class _HelpGroup extends ConsumerWidget {
  const _HelpGroup({required this.group});

  final ShortcutGroup group;

  /// Place laissée aux touches : au-delà, elles passent à la ligne, et le
  /// libellé garde le reste.
  static const double _keysMaxWidth = 180;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final keymap = ref.watch(keymapProvider);
    final prefs = ref.watch(preferencesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.label(l10n).toUpperCase(),
          style: type.caption.copyWith(
            color: colors.projector,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: OmniaMetrics.space2),
        for (final action in group.actions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(actionLabel(action, l10n, prefs), style: type.body)),
                const SizedBox(width: OmniaMetrics.space3),
                if (keymap.combosFor(action).isEmpty)
                  KeyCap(l10n.shortcutsNone, muted: true)
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _keysMaxWidth),
                    child: Wrap(
                      spacing: OmniaMetrics.space1,
                      runSpacing: OmniaMetrics.space1,
                      children: [
                        for (final combo in keymap.combosFor(action))
                          KeyCap(comboLabel(combo, l10n)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
