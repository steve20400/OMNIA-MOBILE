import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/end_of_playback_mode.dart';
import '../../core/models/playback_state.dart';
import '../../core/models/playback_status.dart';
import '../../core/providers.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/app_localizations.dart';
import '../chrome_controller.dart';
import '../control_bar_width.dart';
import '../shortcuts/default_keymap.dart';
import '../shortcuts/shortcut_labels.dart';
import '../theme/omnia_theme.dart';
import '../tool_panel_controller.dart';
import 'beam_progress_bar.dart';
import 'chrome_menu_anchor.dart';
import 'control_layout.dart';
import 'floating_surface.dart';
import 'omnia_icon_button.dart';
import 'omnia_menu.dart';
import 'slim_slider.dart';
import 'track_menus.dart';

/// Barre de contrôles flottante : faisceau de progression, lecture/pause,
/// timecodes, et les commandes secondaires.
///
/// Sa largeur se règle à la souris, par les poignées de ses deux côtés
/// (double-clic : largeur automatique), et suit la fenêtre. Les commandes qui
/// ne tiennent plus passent dans le menu « ⋯ », en bas à droite, qui
/// n'apparaît que dans ce cas : les moins utiles cèdent leur place les
/// premières ([fitControls]).
///
/// Chaque interaction émet une [PlayerCommand] sur le bus ; ce widget ne
/// connaît aucun contrôleur.
class ControlBar extends ConsumerStatefulWidget {
  const ControlBar({super.key});

  @override
  ConsumerState<ControlBar> createState() => _ControlBarState();
}

/// Une commande de la barre : sa place, son widget, et ses lignes dans le
/// menu « ⋯ » quand elle n'a plus de place dans la barre.
class _Control {
  const _Control(this.slot, this.widget, this.menu);

  final ControlSlot slot;
  final Widget widget;
  final List<Widget> menu;
}

class _ControlBarState extends ConsumerState<ControlBar> {
  /// Clic sur la durée : bascule durée totale ↔ temps restant.
  bool _showRemaining = false;

  /// Pointeur sur la barre : les poignées de largeur se montrent.
  bool _hovering = false;
  bool _resizing = false;
  double _dragWidth = 0;

  /// Commandes rangées à gauche, avant l'espace libre ; les autres à droite.
  static const _leading = {'previous', 'play', 'next', 'time'};

  /// Place du bouton « ⋯ », marge comprise.
  static const double _overflowWidth = OmniaMetrics.iconButtonSize + OmniaMetrics.space2;

  /// Bordure d'un pixel de [FloatingSurface], de chaque côté : elle prend sur
  /// la place des commandes, comme la marge intérieure (même convention que la
  /// barre des documents).
  static const double _surfaceBorder = 1;

  static double? _fraction(Duration? value, Duration duration) {
    if (value == null || duration.inMilliseconds <= 0) return null;
    return (value.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
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
    final userWidth = ref.watch(controlBarWidthProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        const margin = OmniaMetrics.controlBarMargin;
        final available = math.max(0.0, constraints.maxWidth - 2 * margin);
        final minWidth = math.min(OmniaMetrics.controlBarMinWidth, available);
        // Largeur choisie, bornée par la fenêtre du moment : réduire la
        // fenêtre ne change pas la préférence, qui revient quand on l'agrandit.
        final width = userWidth > 0
            ? userWidth.clamp(minWidth, available).toDouble()
            : math.min(OmniaMetrics.controlBarMaxWidth - 2 * margin, available);
        final rowWidth = math.max(
          0.0,
          width - 2 * OmniaMetrics.controlBarPadding - 2 * _surfaceBorder,
        );

        return Padding(
          padding: const EdgeInsets.all(margin),
          child: Center(
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovering = true),
              onExit: (_) => setState(() => _hovering = false),
              child: SizedBox(
                width: width,
                child: Stack(
                  children: [
                    FloatingSurface(
                      padding: const EdgeInsets.fromLTRB(
                        OmniaMetrics.controlBarPadding,
                        0,
                        OmniaMetrics.controlBarPadding,
                        OmniaMetrics.space2,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _beam(state),
                          _row(context, state, rowWidth),
                        ],
                      ),
                    ),
                    for (final side in const [-1, 1])
                      Positioned(
                        left: side < 0 ? 0 : null,
                        right: side > 0 ? 0 : null,
                        top: 0,
                        bottom: 0,
                        child: _ResizeGrip(
                          key: ValueKey('control-bar-grip-$side'),
                          visible: _hovering || _resizing,
                          onStart: () => setState(() {
                            _resizing = true;
                            _dragWidth = width;
                          }),
                          onDelta: (dx) {
                            // Barre centrée : un bord qui bouge de dx change
                            // la largeur de deux fois dx.
                            _dragWidth = (_dragWidth + side * 2 * dx).clamp(minWidth, available);
                            ref.dispatch(SetControlBarWidth(_dragWidth));
                          },
                          onEnd: () => setState(() => _resizing = false),
                          onReset: () => ref.dispatch(const SetControlBarWidth(0)),
                        ),
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

  Widget _beam(PlaybackState state) {
    final hasMedia = state.hasFile && state.status != PlaybackStatus.error && state.mediaType.isAv;
    return BeamProgressBar(
      progress: state.progress,
      duration: state.duration,
      enabled: hasMedia && state.duration > Duration.zero,
      loopA: _fraction(state.loopA, state.duration),
      loopB: _fraction(state.loopB, state.duration),
      onSeek: (position) => ref.dispatch(SeekAbsolute(position)),
      // Molette sur la barre : avance ou recul du pas réglé dans les
      // paramètres (le même que les flèches du clavier).
      onScrollSeek: (direction) => ref.dispatch(
        SeekRelative(ref.read(preferencesProvider).seekStepSeconds * direction.toDouble()),
      ),
      // Tant qu'on fait glisser la tête de lecture, la barre reste affichée.
      onInteractionStart: () => ref.read(chromeProvider.notifier).hold(_beamDragHold),
      onInteractionEnd: () => ref.read(chromeProvider.notifier).release(_beamDragHold),
    );
  }

  static const _beamDragHold = 'chrome:beam-drag';

  Widget _row(BuildContext context, PlaybackState state, double rowWidth) {
    final controls = _controls(context, state);
    final fit = fitControls(
      [for (final c in controls) c.slot],
      // Un pixel de marge : un arrondi de mesure du texte ne doit jamais faire
      // déborder la rangée.
      rowWidth - 1,
      overflowWidth: _overflowWidth,
    );
    final byId = {for (final c in controls) c.slot.id: c};
    final leading = [
      for (final id in fit.shown)
        if (_leading.contains(id)) byId[id]!.widget,
    ];
    final trailing = [
      for (final id in fit.shown)
        if (!_leading.contains(id)) byId[id]!.widget,
    ];

    return Row(
      children: [
        ...leading,
        const Spacer(),
        ...trailing,
        if (fit.hasOverflow)
          _OverflowMenu(
            children: [
              for (final id in fit.overflow) ...byId[id]!.menu,
            ],
          ),
      ],
    );
  }

  List<_Control> _controls(BuildContext context, PlaybackState state) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final toolPanel = ref.watch(toolPanelProvider);

    final hasMedia = state.hasFile && state.status != PlaybackStatus.error && state.mediaType.isAv;
    final canSeek = hasMedia && state.duration > Duration.zero;
    final hasPlaylist = state.playlist.length > 1;
    final isPlaying = state.status == PlaybackStatus.playing;
    final mutedColor = colors.dust;
    final timeColor = hasMedia ? colors.screen : mutedColor;

    final elapsed = formatTimecode(state.position, reference: state.duration);
    final total = _showRemaining
        ? '-${formatTimecode(state.remaining, reference: state.duration)}'
        : formatTimecode(state.duration);
    final timeText = '$elapsed  /  $total';

    final volumeIcon = state.muted || state.volume <= 0
        ? Icons.volume_off_rounded
        : state.volume < 50
            ? Icons.volume_down_rounded
            : Icons.volume_up_rounded;
    final speedLabel = l10n.speedValue(formatSpeed(state.speed));
    final recordLabel = state.recording ? l10n.stopRecording : l10n.recordClip;

    const icon = OmniaMetrics.iconButtonSize;
    final timeWidth = OmniaMetrics.space3 + _textWidth(context, timeText, type.timecode);
    final speedWidth =
        3 * OmniaMetrics.space2 + _textWidth(context, speedLabel, type.timecode);

    void toggleTool(ToolPanel panel) => ref.read(toolPanelProvider.notifier).toggle(panel);

    return [
      _Control(
        const ControlSlot(id: 'previous', width: icon, priority: 4),
        OmniaIconButton(
          icon: Icons.skip_previous_rounded,
          tooltip: ref.tooltipWith(l10n.previousFile, ShortcutAction.previousFile, l10n),
          onPressed: hasPlaylist ? () => ref.dispatch(const PreviousFile()) : null,
        ),
        [
          OmniaMenuItem(
            icon: Icons.skip_previous_rounded,
            label: l10n.previousFile,
            trailing: ref.shortcutOf(ShortcutAction.previousFile, l10n),
            enabled: hasPlaylist,
            onPressed: () => ref.dispatch(const PreviousFile()),
          ),
        ],
      ),
      _Control(
        const ControlSlot(id: 'play', width: OmniaMetrics.playButtonSize, priority: 0),
        OmniaIconButton(
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: OmniaMetrics.playButtonSize,
          iconSize: OmniaMetrics.iconSizeLarge,
          tooltip: ref.tooltipWith(isPlaying ? l10n.pause : l10n.play, ShortcutAction.togglePlay, l10n),
          onPressed: hasMedia ? () => ref.dispatch(const TogglePlay()) : null,
        ),
        const [],
      ),
      _Control(
        const ControlSlot(id: 'next', width: icon, priority: 4),
        OmniaIconButton(
          icon: Icons.skip_next_rounded,
          tooltip: ref.tooltipWith(l10n.nextFile, ShortcutAction.nextFile, l10n),
          onPressed: hasPlaylist ? () => ref.dispatch(const NextFile()) : null,
        ),
        [
          OmniaMenuItem(
            icon: Icons.skip_next_rounded,
            label: l10n.nextFile,
            trailing: ref.shortcutOf(ShortcutAction.nextFile, l10n),
            enabled: hasPlaylist,
            onPressed: () => ref.dispatch(const NextFile()),
          ),
        ],
      ),
      _Control(
        ControlSlot(id: 'time', width: timeWidth, priority: 2),
        Padding(
          padding: const EdgeInsets.only(left: OmniaMetrics.space3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(elapsed, style: type.timecode.copyWith(color: timeColor)),
              Text('  /  ', style: type.timecode.copyWith(color: mutedColor)),
              Tooltip(
                message: _showRemaining ? l10n.showTotalTime : l10n.showRemainingTime,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _showRemaining = !_showRemaining),
                    child: Text(total, style: type.timecode.copyWith(color: mutedColor)),
                  ),
                ),
              ),
            ],
          ),
        ),
        [
          OmniaMenuItem(
            icon: Icons.schedule_rounded,
            label: timeText,
            enabled: false,
            onPressed: null,
          ),
        ],
      ),
      _Control(
        const ControlSlot(id: 'abLoop', width: icon, priority: 7),
        OmniaIconButton(
          icon: Icons.repeat_rounded,
          tooltip: ref.tooltipWith(l10n.abLoop, ShortcutAction.abLoop, l10n),
          active: state.loopA != null,
          onPressed: canSeek ? () => ref.dispatch(const CycleAbLoop()) : null,
        ),
        [
          OmniaMenuItem(
            icon: Icons.repeat_rounded,
            label: l10n.abLoop,
            active: state.loopA != null,
            trailing: ref.shortcutOf(ShortcutAction.abLoop, l10n),
            enabled: canSeek,
            onPressed: () => ref.dispatch(const CycleAbLoop()),
          ),
        ],
      ),
      if (state.hasVideo)
        _Control(
          const ControlSlot(id: 'screenshot', width: icon, priority: 6),
          OmniaIconButton(
            icon: Icons.photo_camera_outlined,
            tooltip: ref.tooltipWith(l10n.screenshot, ShortcutAction.screenshot, l10n),
            onPressed: hasMedia ? () => ref.dispatch(const TakeScreenshot()) : null,
          ),
          [
            OmniaMenuItem(
              icon: Icons.photo_camera_outlined,
              label: l10n.screenshot,
              trailing: ref.shortcutOf(ShortcutAction.screenshot, l10n),
              enabled: hasMedia,
              onPressed: () => ref.dispatch(const TakeScreenshot()),
            ),
          ],
        ),
      if (hasMedia)
        _Control(
          const ControlSlot(id: 'record', width: icon, priority: 5),
          OmniaIconButton(
            icon: state.recording
                ? Icons.fiber_manual_record_rounded
                : Icons.fiber_manual_record_outlined,
            active: state.recording,
            activeColor: colors.alert,
            tooltip: ref.tooltipWith(recordLabel, ShortcutAction.recordClip, l10n),
            onPressed: () => ref.dispatch(const ToggleRecording()),
          ),
          [
            OmniaMenuItem(
              icon: Icons.fiber_manual_record_rounded,
              label: recordLabel,
              active: state.recording,
              trailing: ref.shortcutOf(ShortcutAction.recordClip, l10n),
              onPressed: () => ref.dispatch(const ToggleRecording()),
            ),
          ],
        ),
      if (state.hasVideo)
        _Control(
          const ControlSlot(id: 'subtitles', width: icon, priority: 5),
          SubtitleMenuButton(enabled: hasMedia),
          [
            OmniaSubmenu(
              icon: Icons.subtitles_outlined,
              label: l10n.subtitles,
              children: subtitleMenuItems(context, ref, state),
            ),
          ],
        ),
      if (state.audioTracks.length >= 2)
        _Control(
          const ControlSlot(id: 'audioTrack', width: icon, priority: 6),
          const AudioTrackMenuButton(),
          [
            OmniaSubmenu(
              icon: Icons.audiotrack_rounded,
              label: l10n.audioTracks,
              children: audioTrackMenuItems(context, ref, state),
            ),
          ],
        ),
      if (state.hasVideo)
        _Control(
          const ControlSlot(id: 'image', width: icon, priority: 7),
          OmniaIconButton(
            icon: Icons.tune_rounded,
            tooltip: l10n.image,
            active: toolPanel == ToolPanel.image,
            onPressed: () => toggleTool(ToolPanel.image),
          ),
          [
            OmniaMenuItem(
              icon: Icons.tune_rounded,
              label: l10n.image,
              active: toolPanel == ToolPanel.image,
              onPressed: () => toggleTool(ToolPanel.image),
            ),
          ],
        ),
      _Control(
        const ControlSlot(id: 'equalizer', width: icon, priority: 7),
        OmniaIconButton(
          icon: Icons.equalizer_rounded,
          tooltip: l10n.equalizer,
          active: state.equalizerEnabled || toolPanel == ToolPanel.equalizer,
          onPressed: hasMedia ? () => toggleTool(ToolPanel.equalizer) : null,
        ),
        [
          OmniaMenuItem(
            icon: Icons.equalizer_rounded,
            label: l10n.equalizer,
            active: state.equalizerEnabled || toolPanel == ToolPanel.equalizer,
            enabled: hasMedia,
            onPressed: () => toggleTool(ToolPanel.equalizer),
          ),
        ],
      ),
      _Control(
        const ControlSlot(id: 'endMode', width: icon + 2 * OmniaMetrics.space2, priority: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: OmniaMetrics.space2),
          child: _EndModeButton(mode: state.endMode),
        ),
        [
          // Dans le menu, un choix direct plutôt que le cycle du bouton.
          OmniaSubmenu(
            icon: endModeIcon(state.endMode),
            label: l10n.endModeLabel,
            trailing: endModeLabel(l10n, state.endMode),
            children: [
              for (final mode in EndOfPlaybackMode.values)
                OmniaMenuItem(
                  label: endModeLabel(l10n, mode),
                  active: mode == state.endMode,
                  icon: mode == state.endMode ? Icons.check_rounded : null,
                  onPressed: () => ref.dispatch(SetLoopMode(mode)),
                ),
            ],
          ),
        ],
      ),
      _Control(
        ControlSlot(id: 'speed', width: speedWidth, priority: 5),
        Padding(
          padding: const EdgeInsets.only(right: OmniaMetrics.space2),
          child: _SpeedChip(speed: state.speed, enabled: hasMedia),
        ),
        [
          OmniaSubmenu(
            icon: Icons.speed_rounded,
            label: l10n.menuSpeed,
            trailing: speedLabel,
            children: speedMenuItems(context, ref, state.speed),
          ),
        ],
      ),
      _Control(
        const ControlSlot(id: 'volume', width: icon + OmniaMetrics.space3, priority: 3),
        Padding(
          padding: const EdgeInsets.only(left: OmniaMetrics.space3),
          child: OmniaIconButton(
            icon: volumeIcon,
            tooltip: ref.tooltipWith(state.muted ? l10n.unmute : l10n.mute, ShortcutAction.toggleMute, l10n),
            onPressed: () => ref.dispatch(const ToggleMute()),
          ),
        ),
        [
          OmniaMenuItem(
            icon: volumeIcon,
            label: state.muted ? l10n.unmute : l10n.mute,
            trailing: ref.shortcutOf(ShortcutAction.toggleMute, l10n),
            onPressed: () => ref.dispatch(const ToggleMute()),
          ),
        ],
      ),
      _Control(
        const ControlSlot(id: 'volumeSlider', width: OmniaMetrics.volumeSliderWidth, priority: 4),
        SlimSlider(
          value: state.muted ? 0 : state.volume / PlaybackState.maxVolume,
          muted: state.muted,
          onChanged: (v) => ref.dispatch(SetVolume(v * PlaybackState.maxVolume)),
        ),
        [
          OmniaSubmenu(
            icon: Icons.volume_up_rounded,
            label: l10n.volumeLabel,
            trailing: '${state.volume.round()} %',
            children: [
              OmniaMenuItem(
                icon: Icons.add_rounded,
                label: '+10 %',
                onPressed: () => ref.dispatch(const VolumeRelative(10)),
              ),
              OmniaMenuItem(
                icon: Icons.remove_rounded,
                label: '−10 %',
                onPressed: () => ref.dispatch(const VolumeRelative(-10)),
              ),
            ],
          ),
        ],
      ),
      _Control(
        const ControlSlot(id: 'miniPlayer', width: icon + OmniaMetrics.space3, priority: 6),
        Padding(
          padding: const EdgeInsets.only(left: OmniaMetrics.space3),
          child: OmniaIconButton(
            icon: Icons.picture_in_picture_alt_outlined,
            tooltip: ref.tooltipWith(l10n.miniPlayer, ShortcutAction.miniPlayer, l10n),
            onPressed: hasMedia ? () => ref.dispatch(const ToggleMiniPlayer()) : null,
          ),
        ),
        [
          OmniaMenuItem(
            icon: Icons.picture_in_picture_alt_outlined,
            label: l10n.miniPlayer,
            trailing: ref.shortcutOf(ShortcutAction.miniPlayer, l10n),
            enabled: hasMedia,
            onPressed: () => ref.dispatch(const ToggleMiniPlayer()),
          ),
        ],
      ),
      _Control(
        const ControlSlot(id: 'fullscreen', width: icon, priority: 1),
        OmniaIconButton(
          icon: state.fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          tooltip: ref.tooltipWith(
            state.fullscreen ? l10n.exitFullscreen : l10n.fullscreen,
            ShortcutAction.toggleFullscreen,
            l10n,
          ),
          onPressed: () => ref.dispatch(const ToggleFullscreen()),
        ),
        [
          OmniaMenuItem(
            icon: state.fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
            label: state.fullscreen ? l10n.exitFullscreen : l10n.fullscreen,
            trailing: ref.shortcutOf(ShortcutAction.toggleFullscreen, l10n),
            onPressed: () => ref.dispatch(const ToggleFullscreen()),
          ),
        ],
      ),
    ];
  }
}

/// Icône d'un mode de fin de lecture.
IconData endModeIcon(EndOfPlaybackMode mode) => switch (mode) {
      EndOfPlaybackMode.stop => Icons.stop_circle_outlined,
      EndOfPlaybackMode.next => Icons.playlist_play_rounded,
      EndOfPlaybackMode.repeatOne => Icons.repeat_one_rounded,
      EndOfPlaybackMode.loopFolder => Icons.repeat_rounded,
      EndOfPlaybackMode.shuffle => Icons.shuffle_rounded,
    };

/// Nom d'un mode de fin de lecture.
String endModeLabel(AppLocalizations l10n, EndOfPlaybackMode mode) => switch (mode) {
      EndOfPlaybackMode.stop => l10n.endModeStop,
      EndOfPlaybackMode.next => l10n.endModeNext,
      EndOfPlaybackMode.repeatOne => l10n.endModeRepeatOne,
      EndOfPlaybackMode.loopFolder => l10n.endModeLoopFolder,
      EndOfPlaybackMode.shuffle => l10n.endModeShuffle,
    };

/// Comportement en fin de lecture. Un clic passe au mode suivant du cycle,
/// comme la touche `L`.
class _EndModeButton extends ConsumerWidget {
  const _EndModeButton({required this.mode});

  final EndOfPlaybackMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return OmniaIconButton(
      icon: endModeIcon(mode),
      tooltip: ref.tooltipWith('${l10n.endModeLabel} : ${endModeLabel(l10n, mode)}', ShortcutAction.cycleEndMode, l10n),
      active: mode != EndOfPlaybackMode.next,
      onPressed: () => ref.dispatch(const CycleLoopMode()),
    );
  }
}

/// Vitesse courante en mono ; un clic ouvre le choix de la vitesse, la même
/// liste que le menu contextuel de la scène.
class _SpeedChip extends ConsumerWidget {
  const _SpeedChip({required this.speed, required this.enabled});

  final double speed;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final isDefault = speed == 1.0;
    final label = l10n.speedValue(formatSpeed(speed));
    return ChromeMenuAnchor(
      menuChildren: enabled ? speedMenuItems(context, ref, speed) : const [],
      builder: (context, controller, _) => Tooltip(
        message: l10n.menuSpeed,
        child: Semantics(
          button: true,
          enabled: enabled,
          label: '${l10n.menuSpeed} $label',
          child: MouseRegion(
            cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? () => controller.isOpen ? controller.close() : controller.open() : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: OmniaMetrics.space2),
                child: Text(
                  label,
                  style: type.timecode.copyWith(
                    color: isDefault ? colors.dust : colors.projector,
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

/// Menu « ⋯ » : les commandes qui n'ont plus de place dans la barre.
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

/// Poignée de largeur, sur un bord de la barre : un trait discret qui ne se
/// montre qu'au survol de la barre. Glisser règle la largeur ; double-clic,
/// largeur automatique.
class _ResizeGrip extends StatelessWidget {
  const _ResizeGrip({
    super.key,
    required this.visible,
    required this.onStart,
    required this.onDelta,
    required this.onEnd,
    required this.onReset,
  });

  final bool visible;
  final VoidCallback onStart;
  final ValueChanged<double> onDelta;
  final VoidCallback onEnd;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: AppLocalizations.of(context).controlBarResize,
      waitDuration: const Duration(milliseconds: 700),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => onStart(),
          onHorizontalDragUpdate: (d) => onDelta(d.delta.dx),
          onHorizontalDragEnd: (_) => onEnd(),
          onHorizontalDragCancel: onEnd,
          onDoubleTap: onReset,
          child: SizedBox(
            width: OmniaMetrics.controlBarGripWidth,
            child: Center(
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: OmniaMotion.hover,
                child: Container(
                  width: 4,
                  height: 26,
                  decoration: BoxDecoration(
                    color: colors.seam,
                    borderRadius: const BorderRadius.all(Radius.circular(2)),
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
