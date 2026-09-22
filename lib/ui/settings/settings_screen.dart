import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/app_preferences.dart';
import '../../core/models/document_layout.dart';
import '../../core/models/end_of_playback_mode.dart';
import '../../core/models/equalizer.dart';
import '../../core/models/playback_state.dart';
import '../../core/providers.dart';
import '../../core/services/update_service.dart';
import '../../core/utils/screenshot_naming.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/app_localizations.dart';
import '../player_focus.dart';
import '../recent_files.dart';
import '../theme/omnia_theme.dart';
import '../widgets/key_cap.dart';
import '../widgets/omnia_button.dart';
import '../widgets/omnia_icon_button.dart';
import '../widgets/recent_files_menu.dart';
import 'settings_controller.dart';
import 'settings_controls.dart';
import 'shortcut_editor.dart';

/// Écran Paramètres (§10) : une feuille posée sur la scène, sections à
/// gauche, réglages à droite. `Échap` ou un clic sur le voile la ferme.
///
/// Toute modification passe par le bus (`UpdatePreferences`, `SetLoopMode`,
/// `SetScreenshotFolder`, effacements d'historique) : l'écran ne touche jamais
/// directement au stockage.
class SettingsOverlay extends ConsumerWidget {
  const SettingsOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(settingsUiProvider.select((s) => s.visible));
    final colors = context.colors;

    // En se fermant, l'écran rend le clavier au lecteur.
    ref.listen<bool>(settingsUiProvider.select((s) => s.visible), (previous, next) {
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
          onTap: () => ref.read(settingsUiProvider.notifier).hide(),
          child: ColoredBox(
            color: colors.overlayScrim,
            child: Center(
              child: GestureDetector(
                // Un clic dans la feuille ne doit pas la fermer.
                onTap: () {},
                child: AnimatedSwitcher(
                  duration: OmniaMotion.reveal,
                  switchInCurve: OmniaMotion.revealCurve,
                  switchOutCurve: OmniaMotion.concealCurve,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
                      child: child,
                    ),
                  ),
                  child: visible
                      ? const _SettingsSheet(key: ValueKey('settings-sheet'))
                      : const SizedBox.shrink(key: ValueKey('settings-none')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La feuille elle-même. Dans une fenêtre étroite, la colonne des sections
/// devient une colonne d'icônes (le nom de la section reste en tête du
/// contenu), et les marges se resserrent ; le contenu défile.
class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet({super.key});

  /// Fenêtre plus étroite : colonne d'icônes et marges resserrées.
  static const double _compactWidth = 560;

  /// Fenêtre plus basse : marges resserrées.
  static const double _compactHeight = 400;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final size = MediaQuery.sizeOf(context);
    final section = ref.watch(settingsUiProvider.select((s) => s.section));
    final compact = size.width < _compactWidth;
    final margin = compact || size.height < _compactHeight
        ? OmniaMetrics.space3
        : OmniaMetrics.space5;

    // La feuille garde le focus clavier pour elle (Tab y circule) ; le lecteur
    // ne reçoit donc plus les touches, et c'est ici qu'Échap ferme l'écran.
    return FocusScope(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          ref.read(settingsUiProvider.notifier).hide();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.max(
            0.0,
            math.min(OmniaMetrics.settingsMaxWidth, size.width - 2 * margin),
          ),
          maxHeight: math.max(
            0.0,
            math.min(OmniaMetrics.settingsMaxHeight, size.height - 2 * margin),
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.curtain,
            borderRadius: OmniaMetrics.overlayRadius,
            border: Border.all(color: colors.seam),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: OmniaMetrics.overlayShadowAlpha),
                blurRadius: OmniaMetrics.overlayShadowBlur,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: OmniaMetrics.overlayRadius,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (compact) _SettingsRail(selected: section) else _SettingsNav(selected: section),
                VerticalDivider(width: 1, thickness: 1, color: colors.seam),
                Expanded(child: _SettingsBody(section: section, compact: compact)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Navigation ------------------------------------------------------------------

IconData _iconFor(SettingsSection section) => switch (section) {
      SettingsSection.general => Icons.tune_rounded,
      SettingsSection.playback => Icons.play_circle_outline_rounded,
      SettingsSection.subtitles => Icons.subtitles_outlined,
      SettingsSection.audio => Icons.graphic_eq_rounded,
      SettingsSection.documents => Icons.description_outlined,
      SettingsSection.shortcuts => Icons.keyboard_outlined,
      SettingsSection.screenshots => Icons.photo_camera_outlined,
      SettingsSection.connect => Icons.wifi_tethering_rounded,
      SettingsSection.network => Icons.cloud_sync_rounded,
      SettingsSection.history => Icons.history_rounded,
    };

String _labelFor(SettingsSection section, AppLocalizations l10n) => switch (section) {
      SettingsSection.general => l10n.settingsSectionGeneral,
      SettingsSection.playback => l10n.settingsSectionPlayback,
      SettingsSection.subtitles => l10n.settingsSectionSubtitles,
      SettingsSection.audio => l10n.settingsSectionAudio,
      SettingsSection.documents => l10n.settingsSectionDocuments,
      SettingsSection.shortcuts => l10n.settingsSectionShortcuts,
      SettingsSection.screenshots => l10n.settingsSectionScreenshots,
      SettingsSection.connect => 'Connexions sans fil',
      SettingsSection.network => 'Réseau & Mises à jour',
      SettingsSection.history => l10n.settingsSectionHistory,
    };

class _SettingsNav extends ConsumerWidget {
  const _SettingsNav({required this.selected});

  final SettingsSection selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    return Container(
      width: OmniaMetrics.settingsNavWidth,
      color: colors.velvet.withValues(alpha: 0.35),
      // Défile quand la fenêtre est trop basse pour toutes les sections.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(OmniaMetrics.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                OmniaMetrics.space2,
                OmniaMetrics.space2,
                OmniaMetrics.space2,
                OmniaMetrics.space4,
              ),
              child: Text(l10n.settingsTitle, style: type.sectionTitle),
            ),
            for (final section in SettingsSection.values)
              _NavItem(
                icon: _iconFor(section),
                label: _labelFor(section, l10n),
                selected: section == selected,
                onTap: () => ref.read(settingsUiProvider.notifier).select(section),
              ),
          ],
        ),
      ),
    );
  }
}

/// Sections d'une fenêtre étroite : une colonne d'icônes, le nom de chacune
/// en infobulle. Elle défile quand la fenêtre est trop basse.
class _SettingsRail extends ConsumerWidget {
  const _SettingsRail({required this.selected});

  final SettingsSection selected;

  /// Un bouton et ses marges.
  static const double _width = OmniaMetrics.iconButtonSize + 2 * OmniaMetrics.space1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);
    return Container(
      width: _width,
      color: colors.velvet.withValues(alpha: 0.35),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: OmniaMetrics.space2),
        child: Column(
          children: [
            for (final section in SettingsSection.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Semantics(
                  selected: section == selected,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: section == selected
                          ? colors.projector.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: OmniaMetrics.controlRadius,
                    ),
                    child: OmniaIconButton(
                      icon: _iconFor(section),
                      iconSize: OmniaMetrics.iconSize - 2,
                      tooltip: _labelFor(section, l10n),
                      active: section == selected,
                      onPressed: () => ref.read(settingsUiProvider.notifier).select(section),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final foreground = widget.selected ? colors.projector : colors.screen;
    return Semantics(
      selected: widget.selected,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: OmniaMotion.hover,
            curve: OmniaMotion.hoverCurve,
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(
              horizontal: OmniaMetrics.space3,
              vertical: OmniaMetrics.space2,
            ),
            decoration: BoxDecoration(
              color: widget.selected
                  ? colors.projector.withValues(alpha: 0.12)
                  : (_hovered ? colors.hover : Colors.transparent),
              borderRadius: OmniaMetrics.controlRadius,
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: OmniaMetrics.iconSize - 2,
                  color: widget.selected ? colors.projector : colors.dust,
                ),
                const SizedBox(width: OmniaMetrics.space3),
                Expanded(
                  child: Text(
                    widget.label,
                    style: type.body.copyWith(
                      color: foreground,
                      fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Corps ------------------------------------------------------------------------

class _SettingsBody extends ConsumerStatefulWidget {
  const _SettingsBody({required this.section, required this.compact});

  final SettingsSection section;

  /// Feuille étroite : marges resserrées.
  final bool compact;

  @override
  ConsumerState<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends ConsumerState<_SettingsBody> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(_SettingsBody old) {
    super.didUpdateWidget(old);
    // Changer de section remonte en haut de la page.
    if (old.section != widget.section && _scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final l10n = AppLocalizations.of(context);

    final Widget content = switch (widget.section) {
      SettingsSection.general => const _GeneralSection(),
      SettingsSection.playback => const _PlaybackSection(),
      SettingsSection.subtitles => const _SubtitlesSection(),
      SettingsSection.audio => const _AudioSection(),
      SettingsSection.documents => const _DocumentsSection(),
      SettingsSection.shortcuts => const ShortcutEditor(),
      SettingsSection.screenshots => const _ScreenshotsSection(),
      SettingsSection.connect => const _ConnectSection(),
      SettingsSection.network => const _NetworkSection(),
      SettingsSection.history => const _HistorySection(),
    };

    // Étroite, la feuille rend ses marges au contenu.
    final compact = widget.compact;
    final side = compact ? OmniaMetrics.space3 : OmniaMetrics.space5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            side,
            compact ? OmniaMetrics.space2 : OmniaMetrics.space4,
            compact ? OmniaMetrics.space2 : OmniaMetrics.space3,
            OmniaMetrics.space2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _labelFor(widget.section, l10n),
                  style: type.viewTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              OmniaIconButton(
                icon: Icons.close_rounded,
                tooltip: '${l10n.settingsClose}  ·  ${l10n.keyEscape}',
                onPressed: () => ref.read(settingsUiProvider.notifier).hide(),
              ),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(
                side,
                OmniaMetrics.space1,
                side,
                compact ? OmniaMetrics.space3 : OmniaMetrics.space5,
              ),
              child: KeyedSubtree(key: ValueKey(widget.section), child: content),
            ),
          ),
        ),
      ],
    );
  }
}

/// Modification des préférences : seules les différences partent sur le bus.
extension _Preferences on WidgetRef {
  void change(AppPreferences Function(AppPreferences current) edit) {
    final before = read(preferencesProvider);
    final command = UpdatePreferences.between(before, edit(before));
    if (command.changes.isNotEmpty) dispatch(command);
  }
}

// --- Général ------------------------------------------------------------------------

class _GeneralSection extends ConsumerWidget {
  const _GeneralSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = ref.watch(preferencesProvider);
    final endMode = ref.watch(playbackStateProvider.select((s) => s.endMode));

    return Column(
      children: [
        SettingRow(
          title: l10n.settingsLanguage,
          control: OmniaSegmented<AppLanguage>(
            values: AppLanguage.values,
            selected: p.language,
            labelOf: (v) => switch (v) {
              AppLanguage.system => l10n.languageSystem,
              AppLanguage.fr => l10n.languageFrench,
              AppLanguage.en => l10n.languageEnglish,
            },
            onChanged: (v) => ref.change((p) => p.copyWith(language: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: l10n.settingsTheme,
          control: OmniaSegmented<AppThemeMode>(
            values: AppThemeMode.values,
            selected: p.themeMode,
            labelOf: (v) => switch (v) {
              AppThemeMode.dark => l10n.themeDark,
              AppThemeMode.light => l10n.themeLight,
              AppThemeMode.system => l10n.themeSystem,
            },
            onChanged: (v) => ref.change((p) => p.copyWith(themeMode: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: l10n.endModeLabel,
          hint: l10n.settingsEndModeHint,
          control: OmniaSegmented<EndOfPlaybackMode>(
            values: EndOfPlaybackMode.values,
            selected: endMode,
            labelOf: (v) => switch (v) {
              EndOfPlaybackMode.stop => l10n.endModeStop,
              EndOfPlaybackMode.next => l10n.endModeNext,
              EndOfPlaybackMode.repeatOne => l10n.endModeRepeatOne,
              EndOfPlaybackMode.loopFolder => l10n.endModeLoopFolder,
              EndOfPlaybackMode.shuffle => l10n.endModeShuffle,
            },
            onChanged: (v) => ref.dispatch(SetLoopMode(v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: l10n.settingsResume,
          hint: l10n.settingsResumeHint,
          control: OmniaSegmented<ResumePolicy>(
            values: ResumePolicy.values,
            selected: p.resumePolicy,
            labelOf: (v) => switch (v) {
              ResumePolicy.auto => l10n.resumeAuto,
              ResumePolicy.ask => l10n.resumeAsk,
              ResumePolicy.never => l10n.resumeNever,
            },
            onChanged: (v) => ref.change((p) => p.copyWith(resumePolicy: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: l10n.settingsSingleInstance,
          hint: l10n.settingsSingleInstanceHint,
          control: OmniaSwitch(
            label: l10n.settingsSingleInstance,
            value: p.singleInstance,
            onChanged: (v) => ref.change((p) => p.copyWith(singleInstance: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: l10n.settingsInAppOpenTarget,
          hint: l10n.settingsInAppOpenTargetHint,
          control: OmniaSegmented<InAppOpenTarget>(
            values: InAppOpenTarget.values,
            selected: p.inAppOpenTarget,
            labelOf: (v) => switch (v) {
              InAppOpenTarget.currentWindow => l10n.inAppOpenCurrent,
              InAppOpenTarget.newWindow => l10n.inAppOpenNew,
            },
            onChanged: (v) => ref.change((p) => p.copyWith(inAppOpenTarget: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: '${l10n.alwaysOnTop} · ${l10n.alwaysOnTopNormal}',
          control: OmniaSwitch(
            label: l10n.alwaysOnTopNormal,
            value: p.normalPlayerAlwaysOnTop,
            onChanged: (v) => ref.change((p) => p.copyWith(normalPlayerAlwaysOnTop: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: '${l10n.alwaysOnTop} · ${l10n.alwaysOnTopMini}',
          control: OmniaSwitch(
            label: l10n.alwaysOnTopMini,
            value: p.miniPlayerAlwaysOnTop,
            onChanged: (v) => ref.change((p) => p.copyWith(miniPlayerAlwaysOnTop: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: 'Reprendre la session au démarrage',
          hint: 'Rouvre automatiquement le dernier média ou document lors de l’ouverture d’OMNIA',
          control: OmniaSwitch(
            label: 'Reprendre la session',
            value: p.restoreLastSession,
            onChanged: (v) => ref.change((p) => p.copyWith(restoreLastSession: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: 'Version & Mises à jour en place',
          hint: 'OMNIA Mobile v0.1.0 • Mise à jour directe sans désinstallation préalable (vos préférences et historique sont préservés)',
          control: OmniaButton(
            label: 'À jour (v0.1.0)',
            icon: Icons.check_circle_outline_rounded,
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: context.colors.curtain,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Row(
                    children: [
                      Icon(Icons.system_update_alt_rounded, color: context.colors.projector),
                      const SizedBox(width: 10),
                      Text('OMNIA Mobile v0.1.0', style: TextStyle(color: context.colors.screen)),
                    ],
                  ),
                  content: Text(
                    'Vous utilisez la dernière version d’OMNIA Mobile.\n\n'
                    'Toutes les nouvelles versions s’installent directement par-dessus la version existante sans nécessiter de désinstallation préalable.\n'
                    'Vos réglages, votre historique et vos raccourcis sont intégralement conservés.',
                    style: TextStyle(color: context.colors.dust, height: 1.4),
                  ),
                  actions: [
                    OmniaButton(
                      label: 'Fermer',
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}


// --- Lecture ------------------------------------------------------------------------

class _PlaybackSection extends ConsumerWidget {
  const _PlaybackSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = ref.watch(preferencesProvider);

    return Column(
      children: [
        SettingRow(
          title: l10n.settingsSeekStep,
          hint: l10n.settingsSeekStepHint,
          control: OmniaSegmented<int>(
            values: AppPreferences.seekSteps,
            selected: p.seekStepSeconds,
            labelOf: l10n.settingsSeconds,
            onChanged: (v) => ref.change((p) => p.copyWith(seekStepSeconds: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: l10n.settingsDefaultSpeed,
          control: OmniaSegmented<double>(
            values: AppPreferences.speeds,
            selected: p.defaultSpeed,
            labelOf: (v) => l10n.speedValue(formatSpeed(v)),
            onChanged: (v) => ref.change((p) => p.copyWith(defaultSpeed: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: l10n.settingsStartupVolume,
          control: OmniaSegmented<StartupVolume>(
            values: StartupVolume.values,
            selected: p.startupVolume,
            labelOf: (v) => switch (v) {
              StartupVolume.last => l10n.startupVolumeLast,
              StartupVolume.fixed => l10n.startupVolumeFixed,
            },
            onChanged: (v) => ref.change((p) => p.copyWith(startupVolume: v)),
          ),
        ),
        if (p.startupVolume == StartupVolume.fixed) ...[
          const SettingDivider(),
          SettingRow(
            title: l10n.settingsFixedVolume,
            control: LabelledSlider(
              value: p.fixedVolume,
              min: PlaybackState.minVolume,
              max: PlaybackState.maxVolume,
              divisions: 20,
              format: (v) => '${v.round()}',
              onChanged: (v) => ref.change((p) => p.copyWith(fixedVolume: v)),
            ),
          ),
        ],
      ],
    );
  }
}

// --- Sous-titres --------------------------------------------------------------------

class _SubtitlesSection extends ConsumerWidget {
  const _SubtitlesSection();

  static String _delay(double seconds, AppLocalizations l10n) =>
      l10n.subtitleDelayValue('${seconds > 0 ? '+' : ''}${seconds.toStringAsFixed(1)}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = ref.watch(preferencesProvider);
    const step = PlaybackState.subtitleDelayStep;

    return Column(
      children: [
        SettingRow(
          title: l10n.subtitleSize,
          control: LabelledSlider(
            value: p.subtitleScale,
            min: PlaybackState.minSubtitleScale,
            max: PlaybackState.maxSubtitleScale,
            divisions: 20,
            format: (v) => '${(v * 100).round()} %',
            onChanged: (v) => ref.change((p) => p.copyWith(subtitleScale: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: l10n.settingsSubtitleAutoLoad,
          hint: l10n.settingsSubtitleAutoLoadHint,
          control: OmniaSwitch(
            label: l10n.settingsSubtitleAutoLoad,
            value: p.subtitleAutoLoad,
            onChanged: (v) => ref.change((p) => p.copyWith(subtitleAutoLoad: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: l10n.settingsSubtitleDelay,
          hint: l10n.settingsSubtitleDelayHint,
          control: ValueStepper(
            value: _delay(p.subtitleDelay, l10n),
            decreaseLabel: '−$step s',
            increaseLabel: '+$step s',
            onDecrease: p.subtitleDelay > PlaybackState.minSubtitleDelay
                ? () => ref.change((p) => p.copyWith(subtitleDelay: p.subtitleDelay - step))
                : null,
            onIncrease: p.subtitleDelay < PlaybackState.maxSubtitleDelay
                ? () => ref.change((p) => p.copyWith(subtitleDelay: p.subtitleDelay + step))
                : null,
          ),
        ),
      ],
    );
  }
}

// --- Audio --------------------------------------------------------------------------

class _AudioSection extends ConsumerWidget {
  const _AudioSection();

  static const _custom = 'custom';

  static String _presetLabel(String key, AppLocalizations l10n) => switch (key) {
        'normal' => l10n.presetNormal,
        'rock' => l10n.presetRock,
        'pop' => l10n.presetPop,
        'jazz' => l10n.presetJazz,
        'classical' => l10n.presetClassical,
        'bass' => l10n.presetBass,
        'treble' => l10n.presetTreble,
        'vocal' => l10n.presetVocal,
        'electronic' => l10n.presetElectronic,
        'acoustic' => l10n.presetAcoustic,
        _ => l10n.presetCustom,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = ref.watch(preferencesProvider);
    final preset = Equalizer.presetFor(p.equalizerGains);

    return Column(
      children: [
        SettingRow(
          title: l10n.equalizer,
          hint: l10n.settingsEqualizerHint,
          control: OmniaSwitch(
            label: l10n.equalizer,
            value: p.equalizerEnabled,
            onChanged: (v) => ref.change((p) => p.copyWith(equalizerEnabled: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: l10n.equalizerPreset,
          control: const SizedBox.shrink(),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OmniaSegmented<String>(
            values: [...Equalizer.presets.keys, if (preset == null) _custom],
            selected: preset ?? _custom,
            labelOf: (k) => _presetLabel(k, l10n),
            onChanged: (k) {
              final gains = Equalizer.presets[k];
              if (gains == null) return;
              ref.change((p) => p.copyWith(equalizerGains: gains, equalizerEnabled: true));
            },
          ),
        ),
        const SizedBox(height: OmniaMetrics.space3),
      ],
    );
  }
}

// --- Documents ----------------------------------------------------------------------

class _DocumentsSection extends ConsumerWidget {
  const _DocumentsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = ref.watch(preferencesProvider);

    return Column(
      children: [
        SettingRow(
          title: l10n.settingsPdfLayout,
          control: OmniaSegmented<DocumentLayout>(
            values: DocumentLayout.values,
            selected: p.pdfLayout,
            labelOf: (v) => switch (v) {
              DocumentLayout.continuous => l10n.docLayoutContinuous,
              DocumentLayout.paged => l10n.docLayoutPaged,
            },
            onChanged: (v) => ref.change((p) => p.copyWith(pdfLayout: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: l10n.docReadingDark,
          hint: l10n.settingsReadingDarkHint,
          control: OmniaSwitch(
            label: l10n.docReadingDark,
            value: p.readingDark,
            onChanged: (v) => ref.change((p) => p.copyWith(readingDark: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: l10n.docFontSize,
          hint: l10n.settingsTextSizeHint,
          control: LabelledSlider(
            value: p.textScale,
            min: 0.6,
            max: 3.0,
            divisions: 24,
            format: (v) => '${(v * 100).round()} %',
            onChanged: (v) => ref.change((p) => p.copyWith(textScale: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: 'Sauvegarde automatique des documents',
          hint: 'Enregistre automatiquement les fichiers texte et code modifiés pour éviter toute perte de données',
          control: OmniaSwitch(
            label: 'Sauvegarde automatique',
            value: p.docAutoSave,
            onChanged: (v) => ref.change((p) => p.copyWith(docAutoSave: v)),
          ),
        ),
        if (p.docAutoSave) ...[
          const SettingDivider(),
          SettingRow(
            title: 'Délai d’inactivité avant sauvegarde',
            hint: 'Temps d’attente après la dernière touche saisie avant d’écrire sur le disque',
            control: OmniaSegmented<int>(
              values: AppPreferences.docAutoSaveIntervals,
              selected: p.docAutoSaveIntervalSeconds,
              labelOf: (v) => '$v s',
              onChanged: (v) => ref.change((p) => p.copyWith(docAutoSaveIntervalSeconds: v)),
            ),
          ),
        ],
        const SettingDivider(),
        SettingRow(
          title: 'Fermeture avec modifications en cours',
          hint: 'Action à effectuer si l’application est fermée alors qu’un document est en cours d’édition',
          control: OmniaSegmented<UnsavedChangesPolicy>(
            values: UnsavedChangesPolicy.values,
            selected: p.unsavedChangesPolicy,
            labelOf: (v) => switch (v) {
              UnsavedChangesPolicy.ask => 'Demander',
              UnsavedChangesPolicy.save => 'Enregistrer',
              UnsavedChangesPolicy.discard => 'Ignorer',
            },
            onChanged: (v) => ref.change((p) => p.copyWith(unsavedChangesPolicy: v)),
          ),
        ),
      ],
    );
  }
}

// --- Captures -----------------------------------------------------------------------

/// Dossier des captures d'écran vidéo tel qu'il sera utilisé, et s'il a été choisi à la main.
final screenshotFolderProvider = FutureProvider<({String path, bool custom})>((ref) async {
  final folder = await ref.watch(screenshotServiceProvider).screenshotFolder();
  final custom = ref.watch(settingsStoreProvider).screenshotFolder != null;
  return (path: folder.path, custom: custom);
});

/// Dossier des enregistrements audio tel qu'il sera utilisé, et s'il a été choisi à la main.
final recordingFolderProvider = FutureProvider<({String path, bool custom})>((ref) async {
  final folder = await ref.watch(screenshotServiceProvider).recordingFolder();
  final custom = ref.watch(settingsStoreProvider).recordingFolder != null;
  return (path: folder.path, custom: custom);
});

class _ScreenshotsSection extends ConsumerStatefulWidget {
  const _ScreenshotsSection();

  @override
  ConsumerState<_ScreenshotsSection> createState() => _ScreenshotsSectionState();
}

class _ScreenshotsSectionState extends ConsumerState<_ScreenshotsSection> {
  late final TextEditingController _pattern =
      TextEditingController(text: ref.read(preferencesProvider).screenshotNamePattern);
  late final TextEditingController _suffix =
      TextEditingController(text: ref.read(preferencesProvider).imageEditSuffix);
  final FocusNode _patternFocus = FocusNode(debugLabel: 'omnia.settings.pattern');

  @override
  void initState() {
    super.initState();
    _patternFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pattern.dispose();
    _suffix.dispose();
    _patternFocus.dispose();
    super.dispose();
  }

  /// Change le dossier des captures par le bus, puis relit le dossier effectif une fois la
  /// commande traitée.
  Future<void> _setScreenshotFolder(String? path) async {
    final bus = ref.read(commandBusProvider);
    final service = ref.read(playbackServiceProvider);
    bus.dispatch(SetScreenshotFolder(path));
    await Future<void>.delayed(Duration.zero);
    await service.idle;
    if (mounted) ref.invalidate(screenshotFolderProvider);
  }

  Future<void> _chooseScreenshotFolder() async {
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: 'OMNIA',
    );
    if (dir != null && mounted) await _setScreenshotFolder(dir);
  }

  /// Change le dossier des enregistrements audio par le bus.
  Future<void> _setRecordingFolder(String? path) async {
    final bus = ref.read(commandBusProvider);
    final service = ref.read(playbackServiceProvider);
    bus.dispatch(SetRecordingFolder(path));
    await Future<void>.delayed(Duration.zero);
    await service.idle;
    if (mounted) ref.invalidate(recordingFolderProvider);
  }

  Future<void> _chooseRecordingFolder() async {
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: 'OMNIA',
    );
    if (dir != null && mounted) await _setRecordingFolder(dir);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final type = context.type;
    final screenshotFolder = ref.watch(screenshotFolderProvider);
    final recordingFolder = ref.watch(recordingFolderProvider);

    final preview = screenshotFileName(
      '/Films/Film.mkv',
      DateTime.now(),
      pattern: _pattern.text.trim().isEmpty
          ? AppPreferences.defaultScreenshotPattern
          : _pattern.text,
      position: const Duration(minutes: 12, seconds: 34),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingRow(
          title: l10n.settingsScreenshotFolderVideo,
          hint: screenshotFolder.when(
            data: (f) => f.custom ? f.path : '${l10n.settingsScreenshotFolderDefault} · ${f.path}',
            loading: () => '…',
            error: (_, _) => l10n.settingsScreenshotFolderDefault,
          ),
          control: Wrap(
            spacing: OmniaMetrics.space2,
            runSpacing: OmniaMetrics.space2,
            children: [
              _FittingButton(
                label: l10n.settingsChooseFolder,
                icon: Icons.folder_open_rounded,
                onPressed: _chooseScreenshotFolder,
              ),
              _FittingButton(
                label: l10n.settingsResetFolder,
                icon: Icons.restart_alt_rounded,
                showIcon: false,
                onPressed: screenshotFolder.valueOrNull?.custom == true
                    ? () => _setScreenshotFolder(null)
                    : null,
              ),
            ],
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: l10n.settingsRecordingFolder,
          hint: recordingFolder.when(
            data: (f) => f.custom ? f.path : '${l10n.settingsScreenshotFolderDefault} · ${f.path}',
            loading: () => '…',
            error: (_, _) => l10n.settingsScreenshotFolderDefault,
          ),
          control: Wrap(
            spacing: OmniaMetrics.space2,
            runSpacing: OmniaMetrics.space2,
            children: [
              _FittingButton(
                label: l10n.settingsChooseFolder,
                icon: Icons.folder_open_rounded,
                onPressed: _chooseRecordingFolder,
              ),
              _FittingButton(
                label: l10n.settingsResetFolder,
                icon: Icons.restart_alt_rounded,
                showIcon: false,
                onPressed: recordingFolder.valueOrNull?.custom == true
                    ? () => _setRecordingFolder(null)
                    : null,
              ),
            ],
          ),
        ),
        const SettingDivider(),
        const SizedBox(height: OmniaMetrics.space3),
        Text(l10n.settingsScreenshotPattern, style: type.bodyStrong),
        const SizedBox(height: OmniaMetrics.space2),

        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: OmniaMetrics.space3),
          decoration: BoxDecoration(
            color: colors.velvet,
            borderRadius: OmniaMetrics.controlRadius,
            border: Border.all(color: _patternFocus.hasFocus ? colors.projector : colors.seam),
          ),
          child: TextField(
            controller: _pattern,
            focusNode: _patternFocus,
            style: type.timecode,
            cursorColor: colors.projector,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (value) {
              setState(() {});
              ref.change((p) => p.copyWith(screenshotNamePattern: value));
            },
          ),
        ),
        const SizedBox(height: OmniaMetrics.space3),
        Wrap(
          spacing: OmniaMetrics.space4,
          runSpacing: OmniaMetrics.space2,
          children: [
            for (final (token, meaning) in [
              ('{name}', l10n.tokenName),
              ('{date}', l10n.tokenDate),
              ('{time}', l10n.tokenTime),
              ('{position}', l10n.tokenPosition),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  KeyCap(token),
                  const SizedBox(width: OmniaMetrics.space2),
                  // À l'étroit, l'explication passe à la ligne.
                  Flexible(child: Text(meaning, style: type.secondary)),
                ],
              ),
          ],
        ),
        const SizedBox(height: OmniaMetrics.space3),
        Text(l10n.settingsScreenshotPreview(preview), style: type.caption),
        const SizedBox(height: OmniaMetrics.space6),
        SettingRow(
          title: 'Suffixe des copies modifiées',
          hint: 'Ajouté au nom de fichier lors de la retouche (ex. photo_modifié.png)',
          control: SizedBox(
            width: 140,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.curtain,
                borderRadius: OmniaMetrics.controlRadius,
                border: Border.all(color: colors.seam),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: TextField(
                  controller: _suffix,
                  style: type.body,
                  cursorColor: colors.projector,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (value) {
                    ref.change((p) => p.copyWith(
                          imageEditSuffix: value.trim().isEmpty
                              ? AppPreferences.defaultImageEditSuffix
                              : value.trim(),
                        ));
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// --- Connexions sans fil & OMNIA Connect -------------------------------------

class _ConnectSection extends ConsumerStatefulWidget {
  const _ConnectSection();

  @override
  ConsumerState<_ConnectSection> createState() => _ConnectSectionState();
}

class _ConnectSectionState extends ConsumerState<_ConnectSection> {
  bool _showQrCode = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final p = ref.watch(preferencesProvider);
    final connectService = ref.watch(omniaConnectServiceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingRow(
          title: 'OMNIA Connect local',
          hint: 'Partage, synchronisation et télécommande sans Internet sur le réseau local.',
          control: OmniaSwitch(
            label: 'OMNIA Connect',
            value: p.omniaConnectEnabled,
            onChanged: (v) => ref.change((prefs) => prefs.copyWith(omniaConnectEnabled: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: 'Mode de liaison',
          hint: 'Technologie utilisée pour découvrir et relier les appareils.',
          control: OmniaSegmented<String>(
            values: const ['wifi', 'hotspot', 'bluetooth'],
            selected: p.wirelessMode,
            labelOf: (v) => switch (v) {
              'hotspot' => 'Point d\'accès',
              'bluetooth' => 'Bluetooth',
              _ => 'Wi-Fi local',
            },
            onChanged: (v) => ref.change((prefs) => prefs.copyWith(wirelessMode: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: 'Contrôle à distance',
          hint: 'Autoriser la télécommande depuis un smartphone ou une autre instance OMNIA.',
          control: OmniaSwitch(
            label: 'Contrôle à distance',
            value: p.allowRemoteControl,
            onChanged: (v) => ref.change((prefs) => prefs.copyWith(allowRemoteControl: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: 'Diffusion locale (Streaming)',
          hint: 'Autoriser la diffusion vidéo, audio ou document en temps réel.',
          control: OmniaSwitch(
            label: 'Diffusion locale',
            value: p.allowRemoteStreaming,
            onChanged: (v) => ref.change((prefs) => prefs.copyWith(allowRemoteStreaming: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: 'Appairage rapide & QR Code',
          hint: 'Scannez le code avec OMNIA Mobile ou saisissez la clé d\'association.',
          control: _FittingButton(
            label: _showQrCode ? 'Masquer' : 'Afficher l\'appairage',
            icon: Icons.qr_code_2_rounded,
            onPressed: () => setState(() => _showQrCode = !_showQrCode),
          ),
        ),
        if (_showQrCode) ...[
          const SizedBox(height: OmniaMetrics.space2),
          Container(
            padding: const EdgeInsets.all(OmniaMetrics.space3),
            decoration: BoxDecoration(
              color: colors.curtain.withValues(alpha: 0.6),
              borderRadius: OmniaMetrics.cardRadius,
              border: Border.all(color: colors.divider),
            ),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Icon(Icons.qr_code_2_rounded, size: 60, color: colors.background),
                  ),
                ),
                const SizedBox(width: OmniaMetrics.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Clé d\'association', style: type.label),
                      const SizedBox(height: 2),
                      Text(
                        '849 - 217',
                        style: type.sectionTitle.copyWith(
                          letterSpacing: 2,
                          color: colors.projector,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Port : ${connectService.port} · Protocole v1.0',
                        style: type.secondary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: OmniaMetrics.space2),
        ],
        const SettingDivider(),
        SettingRow(
          title: 'Appareils associés',
          hint: 'Appareils autorisés à piloter ou diffuser des médias.',
          control: _FittingButton(
            label: 'Rechercher',
            icon: Icons.refresh_rounded,
            onPressed: () {},
          ),
        ),
        const SizedBox(height: OmniaMetrics.space1),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: OmniaMetrics.space3,
            vertical: OmniaMetrics.space2,
          ),
          decoration: BoxDecoration(
            color: colors.velvet.withValues(alpha: 0.25),
            borderRadius: OmniaMetrics.controlRadius,
            border: Border.all(color: colors.divider.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.desktop_windows_rounded, size: OmniaMetrics.iconSize, color: colors.projector),
              const SizedBox(width: OmniaMetrics.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('OMNIA Desktop (Bureau)', style: type.bodyStrong),
                    Text('Dernière connexion : Aujourd\'hui · Prêt', style: type.secondary),
                  ],
                ),
              ),
              OmniaIconButton(
                icon: Icons.link_off_rounded,
                tooltip: 'Dissocier',
                onPressed: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: OmniaMetrics.space3),
      ],
    );
  }
}

// --- Réseau & Mises à jour --------------------------------------------------

class _NetworkSection extends ConsumerStatefulWidget {
  const _NetworkSection();

  @override
  ConsumerState<_NetworkSection> createState() => _NetworkSectionState();
}

class _NetworkSectionState extends ConsumerState<_NetworkSection> {
  UpdateStatus _status = UpdateStatus.idle;
  UpdateInfo? _info;
  double _progress = 0.0;
  int _downloaded = 0;
  int _total = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    final service = ref.read(updateServiceProvider);
    _status = service.status;
    _info = service.info;
    _progress = service.downloadProgress;
    _downloaded = service.downloadedBytes;
  }

  Future<void> _checkUpdates() async {
    setState(() {
      _status = UpdateStatus.checking;
      _error = null;
    });
    final service = ref.read(updateServiceProvider);
    final p = ref.read(preferencesProvider);
    final info = await service.checkForUpdates(channel: p.updateChannel);
    if (!mounted) return;
    setState(() {
      _status = service.status;
      _info = info;
    });
  }

  Future<void> _downloadAndInstall() async {
    final service = ref.read(updateServiceProvider);
    setState(() {
      _status = UpdateStatus.downloading;
      _error = null;
    });

    final success = await service.downloadUpdate(
      onProgress: (p, dl, tot) {
        if (!mounted) return;
        setState(() {
          _progress = p;
          _downloaded = dl;
          _total = tot;
        });
      },
    );

    if (!mounted) return;
    if (success) {
      setState(() => _status = UpdateStatus.readyToInstall);
    } else {
      setState(() {
        _status = UpdateStatus.error;
        _error = service.errorMessage ?? 'Erreur de téléchargement';
      });
    }
  }

  Future<void> _applyInstall() async {
    final service = ref.read(updateServiceProvider);
    await service.applyUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final p = ref.watch(preferencesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingRow(
          title: 'Version de l\'application',
          hint: 'OMNIA Mobile v0.1.0 (Production Android/iOS)',
          control: _status == UpdateStatus.checking
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : _FittingButton(
                  label: 'Rechercher',
                  icon: Icons.refresh_rounded,
                  onPressed: _checkUpdates,
                ),
        ),
        const SettingDivider(),
        SettingRow(
          title: 'Vérification automatique',
          hint: 'Rechercher automatiquement les nouvelles versions au démarrage.',
          control: OmniaSwitch(
            label: 'Vérification auto',
            value: p.autoCheckUpdates,
            onChanged: (v) => ref.change((prefs) => prefs.copyWith(autoCheckUpdates: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: 'Canal de mise à jour',
          hint: 'Source des APK et artéfacts d\'installation.',
          control: OmniaSegmented<String>(
            values: const ['stable', 'preview'],
            selected: p.updateChannel,
            labelOf: (v) => switch (v) {
              'preview' => 'CI GitHub',
              _ => 'Stable',
            },
            onChanged: (v) => ref.change((prefs) => prefs.copyWith(updateChannel: v)),
          ),
        ),
        const SettingDivider(),
        Container(
          padding: const EdgeInsets.all(OmniaMetrics.space3),
          decoration: BoxDecoration(
            color: colors.curtain.withValues(alpha: 0.5),
            borderRadius: OmniaMetrics.cardRadius,
            border: Border.all(color: colors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _status == UpdateStatus.available
                        ? Icons.system_update_rounded
                        : _status == UpdateStatus.downloading
                            ? Icons.downloading_rounded
                            : _status == UpdateStatus.readyToInstall
                                ? Icons.check_circle_rounded
                                : Icons.verified_rounded,
                    color: _status == UpdateStatus.available || _status == UpdateStatus.downloading
                        ? colors.projector
                        : _status == UpdateStatus.readyToInstall
                            ? Colors.greenAccent
                            : colors.screen.withValues(alpha: 0.7),
                    size: 22,
                  ),
                  const SizedBox(width: OmniaMetrics.space2),
                  Expanded(
                    child: Text(
                      _status == UpdateStatus.available
                          ? 'Nouvelle version disponible : v${_info?.latestVersion ?? "0.2.0"}'
                          : _status == UpdateStatus.downloading
                              ? 'Téléchargement en cours...'
                              : _status == UpdateStatus.readyToInstall
                                  ? 'Mise à jour prête pour installation'
                                  : 'Votre version d\'OMNIA Mobile est à jour',
                      style: type.bodyStrong,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: OmniaMetrics.space2),
              Text(
                _status == UpdateStatus.readyToInstall
                    ? 'Le paquet d\'installation a été téléchargé avec succès. Appuyez sur Installer pour appliquer la mise à jour sans perte de données.'
                    : _info?.releaseNotes ??
                        'Mises à jour téléchargées directement depuis GitHub Releases sans manipulation manuelle.',
                style: type.secondary,
              ),
              if (_status == UpdateStatus.downloading) ...[
                const SizedBox(height: OmniaMetrics.space2),
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: colors.hover,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.projector),
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: OmniaMetrics.space1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _total > 0
                          ? '${(_downloaded / (1024 * 1024)).toStringAsFixed(1)} Mo / ${(_total / (1024 * 1024)).toStringAsFixed(1)} Mo'
                          : '${(_downloaded / (1024 * 1024)).toStringAsFixed(1)} Mo',
                      style: type.secondary,
                    ),
                    Text(
                      '${(_progress * 100).toInt()} %',
                      style: type.bodyStrong.copyWith(color: colors.projector),
                    ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: OmniaMetrics.space2),
                Text(_error!, style: type.secondary.copyWith(color: Colors.redAccent)),
              ],
              const SizedBox(height: OmniaMetrics.space3),
              Wrap(
                spacing: OmniaMetrics.space2,
                runSpacing: OmniaMetrics.space2,
                children: [
                  if (_status == UpdateStatus.available || _status == UpdateStatus.upToDate)
                    OmniaButton(
                      label: _status == UpdateStatus.available
                          ? 'Télécharger la mise à jour'
                          : 'Télécharger la dernière version',
                      icon: Icons.download_rounded,
                      onPressed: _downloadAndInstall,
                    ),
                  if (_status == UpdateStatus.readyToInstall)
                    OmniaButton(
                      label: 'Installer le paquet',
                      icon: Icons.auto_mode_rounded,
                      onPressed: _applyInstall,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: 'Dépôt et miroirs officiels',
          hint: 'github.com/steve20400/OMNIA-MOBILE · Synchronisé.',
          control: Text(
            'HTTPS · Actif',
            style: type.secondary.copyWith(color: Colors.greenAccent),
          ),
        ),
        const SizedBox(height: OmniaMetrics.space3),
      ],
    );
  }
}

// --- Historique ---------------------------------------------------------------------

class _HistorySection extends ConsumerWidget {
  const _HistorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final type = context.type;
    final recents = ref.watch(recentFilesProvider);
    final p = ref.watch(preferencesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingRow(
          title: l10n.settingsRememberPlaybackState,
          hint: l10n.settingsRememberPlaybackStateHint,
          control: OmniaSwitch(
            label: l10n.settingsRememberPlaybackState,
            value: p.rememberPlaybackState,
            onChanged: (v) => ref.change((prefs) => prefs.copyWith(rememberPlaybackState: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: l10n.settingsHistoryRetention,
          hint: l10n.settingsHistoryRetentionHint,
          control: OmniaSegmented<int>(
            values: AppPreferences.retentionDaysOptions,
            selected: p.historyRetentionDays,
            labelOf: (v) => switch (v) {
              7 => l10n.historyRetention7Days,
              30 => l10n.historyRetention30Days,
              90 => l10n.historyRetention90Days,
              _ => l10n.historyRetentionUnlimited,
            },
            onChanged: (v) => ref.change((prefs) => prefs.copyWith(historyRetentionDays: v)),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: l10n.recentFiles,
          hint: l10n.settingsRecentHint,
          control: _ClearButton(
            label: l10n.clearRecent,
            enabled: recents.isNotEmpty,
            onPressed: () => ref.dispatch(const ClearRecentFiles()),
          ),
        ),
        if (recents.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: OmniaMetrics.space3),
            child: Text(l10n.noRecentFiles, style: type.secondary),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: OmniaMetrics.space3),
            child: RecentFilesList(
              limit: RecentFilesNotifier.limit,
              showTitle: false,
              // Ouvrir un fichier depuis les paramètres ferme l'écran.
              onOpened: () => ref.read(settingsUiProvider.notifier).hide(),
            ),
          ),
        const SettingDivider(),
        SettingRow(
          title: l10n.settingsClearPositions,
          hint: l10n.settingsClearPositionsHint,
          control: _ClearButton(
            label: l10n.settingsClearPositions,
            onPressed: () => ref.dispatch(const ClearResumePositions()),
          ),
        ),
        const SettingDivider(),
        SettingRow(
          title: l10n.settingsClearAll,
          hint: l10n.settingsClearAllHint,
          control: _ClearButton(
            label: l10n.settingsClearAll,
            enabled: true,
            onPressed: () => ref.dispatch(const ClearHistory()),
          ),
        ),
      ],
    );
  }
}

/// Bouton d'effacement : confirme par « Effacé » pendant deux secondes.
class _ClearButton extends StatefulWidget {
  const _ClearButton({required this.label, required this.onPressed, this.enabled = true});

  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  State<_ClearButton> createState() => _ClearButtonState();
}

class _ClearButtonState extends State<_ClearButton> {
  bool _done = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnimatedSwitcher(
      duration: OmniaMotion.reveal,
      child: _done
          ? _FittingButton(
              key: const ValueKey('done'),
              label: l10n.settingsDone,
              icon: Icons.check_rounded,
              onPressed: null,
            )
          : _FittingButton(
              key: const ValueKey('clear'),
              label: widget.label,
              icon: Icons.delete_sweep_outlined,
              onPressed: widget.enabled
                  ? () {
                      widget.onPressed();
                      setState(() => _done = true);
                      _reset?.cancel();
                      _reset = Timer(const Duration(seconds: 2), () {
                        if (mounted) setState(() => _done = false);
                      });
                    }
                  : null,
            ),
    );
  }
}

/// Bouton texte qui se réduit à son icône, le libellé passant en infobulle,
/// quand la place manque : un intitulé long ne fait jamais déborder une
/// ligne de réglage étroite.
class _FittingButton extends StatelessWidget {
  const _FittingButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.showIcon = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  /// Icône à côté du libellé dans la forme pleine ; réduit à son icône, le
  /// bouton la montre de toute façon.
  final bool showIcon;

  /// Largeur d'un [OmniaButton] secondaire : marges, icône et son espace,
  /// libellé, contour d'un pixel.
  double _naturalWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: context.type.bodyStrong),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final text = painter.width.ceilToDouble();
    painter.dispose();
    return 2 * OmniaMetrics.space4 +
        (showIcon ? OmniaMetrics.iconSize - 2 + OmniaMetrics.space2 : 0.0) +
        text +
        2;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || _naturalWidth(context) <= constraints.maxWidth) {
          return OmniaButton(label: label, icon: showIcon ? icon : null, onPressed: onPressed);
        }
        return OmniaIconButton(icon: icon, tooltip: label, onPressed: onPressed);
      },
    );
  }
}
