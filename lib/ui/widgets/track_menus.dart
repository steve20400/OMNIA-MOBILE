import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/playback_state.dart';
import '../../core/providers.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/app_localizations.dart';
import '../shortcuts/default_keymap.dart';
import '../shortcuts/shortcut_labels.dart';
import 'chrome_menu_anchor.dart';
import 'omnia_icon_button.dart';
import 'omnia_menu.dart';

/// Contenu du menu des sous-titres : pistes, chargement, décalage, taille.
/// Partagé par la barre de contrôles et le menu contextuel.
List<Widget> subtitleMenuItems(BuildContext context, WidgetRef ref, PlaybackState state) {
  final l10n = AppLocalizations.of(context);
  final selected = state.subtitleTrackId;
  final delay = state.subtitleDelay;

  return [
    OmniaMenuItem(
      label: l10n.subtitlesNone,
      icon: selected == null ? Icons.check_rounded : null,
      active: selected == null,
      onPressed: () => ref.dispatch(const SetSubtitleTrack(null)),
    ),
    if (state.subtitleTracks.isEmpty)
      OmniaMenuItem(label: l10n.noTracks, enabled: false, onPressed: null)
    else
      for (final track in state.subtitleTracks)
        OmniaMenuItem(
          label: track.label,
          subtitle: track.external ? track.id : null,
          icon: track.id == selected ? Icons.check_rounded : null,
          active: track.id == selected,
          onPressed: () => ref.dispatch(SetSubtitleTrack(track.id)),
        ),
    const OmniaMenuDivider(),
    OmniaMenuItem(
      icon: Icons.file_open_outlined,
      label: l10n.subtitlesLoadFile,
      onPressed: () => pickSubtitleFile(ref),
    ),
    OmniaMenuItem(
      icon: state.subtitlesVisible ? Icons.subtitles_rounded : Icons.subtitles_off_rounded,
      label: state.subtitlesVisible ? l10n.subtitlesOff : l10n.subtitles,
      trailing: ref.shortcutOf(ShortcutAction.toggleSubtitles, l10n),
      onPressed: () => ref.dispatch(const ToggleSubtitles()),
    ),
    const OmniaMenuDivider(),
    OmniaSubmenu(
      icon: Icons.schedule_rounded,
      label: l10n.subtitleDelay,
      trailing: l10n.subtitleDelayValue('${delay > 0 ? '+' : ''}${delay.toStringAsFixed(1)}'),
      children: [
        OmniaMenuItem(
          icon: Icons.remove_rounded,
          label: '−${PlaybackState.subtitleDelayStep} s',
          onPressed: () => ref.dispatch(const SubtitleDelayRelative(-PlaybackState.subtitleDelayStep)),
        ),
        OmniaMenuItem(
          icon: Icons.add_rounded,
          label: '+${PlaybackState.subtitleDelayStep} s',
          onPressed: () => ref.dispatch(const SubtitleDelayRelative(PlaybackState.subtitleDelayStep)),
        ),
        OmniaMenuItem(
          icon: Icons.restart_alt_rounded,
          label: l10n.resetAdjust,
          enabled: delay != 0,
          onPressed: () => ref.dispatch(const SetSubtitleDelay(0)),
        ),
      ],
    ),
    OmniaSubmenu(
      icon: Icons.format_size_rounded,
      label: l10n.subtitleSize,
      trailing: '${(state.subtitleScale * 100).round()} %',
      children: [
        for (final scale in const [0.7, 0.85, 1.0, 1.2, 1.5, 2.0])
          OmniaMenuItem(
            label: '${(scale * 100).round()} %',
            active: (state.subtitleScale - scale).abs() < 0.01,
            icon: (state.subtitleScale - scale).abs() < 0.01 ? Icons.check_rounded : null,
            onPressed: () => ref.dispatch(SetSubtitleScale(scale)),
          ),
      ],
    ),
  ];
}

/// Contenu du menu des pistes audio.
List<Widget> audioTrackMenuItems(BuildContext context, WidgetRef ref, PlaybackState state) {
  final l10n = AppLocalizations.of(context);
  final selected = state.audioTrackId;
  return [
    OmniaMenuItem(
      label: l10n.audioTrackAuto,
      icon: selected == null ? Icons.check_rounded : null,
      active: selected == null,
      onPressed: () => ref.dispatch(const SetAudioTrack(null)),
    ),
    if (state.audioTracks.isEmpty)
      OmniaMenuItem(label: l10n.noTracks, enabled: false, onPressed: null)
    else
      for (final track in state.audioTracks)
        OmniaMenuItem(
          label: track.label,
          icon: track.id == selected ? Icons.check_rounded : null,
          active: track.id == selected,
          onPressed: () => ref.dispatch(SetAudioTrack(track.id)),
        ),
  ];
}

/// Contenu du menu des vitesses. Partagé par l'indicateur de vitesse de la
/// barre de contrôles et le menu contextuel.
List<Widget> speedMenuItems(BuildContext context, WidgetRef ref, double current) {
  final l10n = AppLocalizations.of(context);
  return [
    for (final speed in PlaybackState.speedPresets)
      OmniaMenuItem(
        label: l10n.speedValue(formatSpeed(speed)),
        active: (current - speed).abs() < 0.001,
        icon: (current - speed).abs() < 0.001 ? Icons.check_rounded : null,
        // La vitesse normale rappelle son raccourci : la touche qui y revient.
        trailing: speed == 1.0 ? ref.shortcutOf(ShortcutAction.speedReset, l10n) : null,
        onPressed: () => ref.dispatch(SetSpeed(speed)),
      ),
    const OmniaMenuDivider(),
    OmniaMenuItem(
      icon: Icons.remove_rounded,
      label: l10n.scSpeedDown,
      trailing: ref.shortcutOf(ShortcutAction.speedDown, l10n),
      enabled: current > PlaybackState.minSpeed,
      onPressed: () => ref.dispatch(const SpeedRelative(-PlaybackState.speedStep)),
    ),
    OmniaMenuItem(
      icon: Icons.add_rounded,
      label: l10n.scSpeedUp,
      trailing: ref.shortcutOf(ShortcutAction.speedUp, l10n),
      enabled: current < PlaybackState.maxSpeed,
      onPressed: () => ref.dispatch(const SpeedRelative(PlaybackState.speedStep)),
    ),
  ];
}

/// Dialogue de choix d'un fichier de sous-titres, puis chargement.
Future<void> pickSubtitleFile(WidgetRef ref) async {
  final bus = ref.read(commandBusProvider);
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: 'OMNIA',
    type: FileType.custom,
    allowedExtensions: const ['srt', 'ass', 'ssa', 'vtt', 'sub', 'SRT', 'ASS', 'SSA', 'VTT', 'SUB'],
  );
  final path = result?.files.singleOrNull?.path;
  if (path != null) bus.dispatch(LoadSubtitleFile(path));
}

/// Bouton « sous-titres » de la barre de contrôles, avec son menu.
class SubtitleMenuButton extends ConsumerWidget {
  const SubtitleMenuButton({super.key, required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(playbackStateProvider);
    final active = state.subtitlesVisible && state.subtitleTrackId != null;

    return ChromeMenuAnchor(
      menuChildren: enabled ? subtitleMenuItems(context, ref, state) : const [],
      builder: (context, controller, _) => OmniaIconButton(
        icon: active ? Icons.subtitles_rounded : Icons.subtitles_outlined,
        active: active,
        tooltip: ref.tooltipWith(l10n.subtitles, ShortcutAction.toggleSubtitles, l10n),
        onPressed: enabled ? () => controller.isOpen ? controller.close() : controller.open() : null,
      ),
    );
  }
}

/// Bouton « piste audio » de la barre de contrôles, visible seulement quand
/// le fichier en a plusieurs.
class AudioTrackMenuButton extends ConsumerWidget {
  const AudioTrackMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(playbackStateProvider);
    if (state.audioTracks.length < 2) return const SizedBox.shrink();

    return ChromeMenuAnchor(
      menuChildren: audioTrackMenuItems(context, ref, state),
      builder: (context, controller, _) => OmniaIconButton(
        icon: Icons.audiotrack_rounded,
        tooltip: l10n.audioTracks,
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
