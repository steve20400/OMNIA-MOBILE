import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/end_of_playback_mode.dart';
import '../../core/models/media_type.dart';
import '../../core/models/playback_status.dart';
import '../../core/models/video_adjust.dart';
import '../../core/providers.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/app_localizations.dart';
import '../chrome_controller.dart';
import '../file_dialogs.dart';
import '../help_overlay_controller.dart';
import '../panel_controller.dart';
import '../player_focus.dart';
import '../settings/settings_controller.dart';
import '../shortcuts/default_keymap.dart';
import '../shortcuts/shortcut_labels.dart';
import '../tool_panel_controller.dart';
import 'image_edit_dialog.dart';
import 'omnia_menu.dart';
import 'track_menus.dart';

/// Menu contextuel de la scène (clic droit sur la vidéo).
///
/// Enveloppe [child] et ouvre le menu à l'endroit du clic. Les sections
/// sous-titres, pistes audio, image et capture arrivent en Phase 5 : le menu
/// est déjà structuré pour les accueillir.
class StageContextMenu extends ConsumerStatefulWidget {
  const StageContextMenu({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StageContextMenu> createState() => _StageContextMenuState();
}

class _StageContextMenuState extends ConsumerState<StageContextMenu> {
  final MenuController _controller = MenuController();

  /// Menu ouvert : un voile couvre la scène pour le fermer au clic.
  bool _menuOpen = false;

  late final ChromeController _chrome;
  late final PlayerFocus _focus;

  @override
  void initState() {
    super.initState();
    _chrome = ref.read(chromeProvider.notifier);
    _focus = ref.read(playerFocusProvider);
  }

  @override
  void dispose() {
    _chrome.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(playbackStateProvider);
    final prefs = ref.watch(preferencesProvider);
    final panelVisible = ref.watch(panelStateProvider.select((p) => p.visible));


    final hasMedia =
        state.hasFile && state.status != PlaybackStatus.error && state.mediaType.isAv;
    final hasPlaylist = state.playlist.length > 1;
    final path = state.file?.path;

    String aspectLabel(AspectMode mode) => switch (mode) {
          AspectMode.auto => l10n.aspectAuto,
          AspectMode.wide => l10n.aspectWide,
          AspectMode.standard => l10n.aspectStandard,
          AspectMode.fill => l10n.aspectFill,
        };

    String endModeLabel(EndOfPlaybackMode mode) => switch (mode) {
          EndOfPlaybackMode.stop => l10n.endModeStop,
          EndOfPlaybackMode.next => l10n.endModeNext,
          EndOfPlaybackMode.repeatOne => l10n.endModeRepeatOne,
          EndOfPlaybackMode.loopFolder => l10n.endModeLoopFolder,
          EndOfPlaybackMode.shuffle => l10n.endModeShuffle,
        };

    return MenuAnchor(
      controller: _controller,
      consumeOutsideTap: true,
      menuChildren: [
        OmniaMenuItem(
          icon: state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          label: state.isPlaying ? l10n.pause : l10n.play,
          trailing: ref.shortcutOf(ShortcutAction.togglePlay, l10n),
          enabled: hasMedia,
          onPressed: () => ref.dispatch(const TogglePlay()),
        ),
        OmniaMenuItem(
          icon: Icons.skip_previous_rounded,
          label: l10n.previousFile,
          trailing: ref.shortcutOf(ShortcutAction.previousFile, l10n),
          enabled: hasPlaylist,
          onPressed: () => ref.dispatch(const PreviousFile()),
        ),
        OmniaMenuItem(
          icon: Icons.skip_next_rounded,
          label: l10n.nextFile,
          trailing: ref.shortcutOf(ShortcutAction.nextFile, l10n),
          enabled: hasPlaylist,
          onPressed: () => ref.dispatch(const NextFile()),
        ),
        const OmniaMenuDivider(),
        OmniaSubmenu(
          icon: Icons.speed_rounded,
          label: l10n.menuSpeed,
          trailing: l10n.speedValue(_formatSpeed(state.speed)),
          children: speedMenuItems(context, ref, state.speed),
        ),
        OmniaSubmenu(
          icon: Icons.repeat_rounded,
          label: l10n.endModeLabel,
          trailing: endModeLabel(state.endMode),
          children: [
            for (final mode in EndOfPlaybackMode.values)
              OmniaMenuItem(
                label: endModeLabel(mode),
                active: state.endMode == mode,
                icon: state.endMode == mode ? Icons.check_rounded : null,
                onPressed: () => ref.dispatch(SetLoopMode(mode)),
              ),
          ],
        ),
        if (hasMedia && state.hasVideo) ...[
          const OmniaMenuDivider(),
          OmniaSubmenu(
            icon: Icons.subtitles_outlined,
            label: l10n.subtitles,
            children: subtitleMenuItems(context, ref, state),
          ),
          if (state.audioTracks.length > 1)
            OmniaSubmenu(
              icon: Icons.audiotrack_rounded,
              label: l10n.audioTracks,
              children: audioTrackMenuItems(context, ref, state),
            ),
          OmniaSubmenu(
            icon: Icons.tune_rounded,
            label: l10n.image,
            children: [
              OmniaSubmenu(
                label: l10n.aspectRatio,
                trailing: aspectLabel(state.aspectMode),
                children: [
                  for (final mode in AspectMode.values)
                    OmniaMenuItem(
                      label: aspectLabel(mode),
                      active: state.aspectMode == mode,
                      icon: state.aspectMode == mode ? Icons.check_rounded : null,
                      onPressed: () => ref.dispatch(SetAspectMode(mode)),
                    ),
                ],
              ),
              OmniaMenuItem(
                icon: Icons.zoom_in_rounded,
                label: l10n.docZoomIn,
                onPressed: () => ref.dispatch(const VideoZoomRelative(0.1)),
              ),
              OmniaMenuItem(
                icon: Icons.zoom_out_rounded,
                label: l10n.docZoomOut,
                onPressed: () => ref.dispatch(const VideoZoomRelative(-0.1)),
              ),
              OmniaMenuItem(
                icon: Icons.crop_free_rounded,
                label: l10n.videoZoomReset,
                enabled: state.videoZoom != 0,
                onPressed: () => ref.dispatch(const ResetVideoZoom()),
              ),
              OmniaMenuItem(
                icon: Icons.rotate_right_rounded,
                label: l10n.videoRotate,
                trailing: state.videoRotation == 0 ? null : '${state.videoRotation * 90}°',
                onPressed: () => ref.dispatch(const RotateVideo()),
              ),
              const OmniaMenuDivider(),
              OmniaMenuItem(
                icon: Icons.brightness_6_outlined,
                label: l10n.imageAdjust,
                onPressed: () => ref.read(toolPanelProvider.notifier).toggle(ToolPanel.image),
              ),
            ],
          ),
          OmniaMenuItem(
            icon: Icons.photo_camera_outlined,
            label: l10n.screenshot,
            trailing: ref.shortcutOf(ShortcutAction.screenshot, l10n),
            onPressed: () => ref.dispatch(const TakeScreenshot()),
          ),
        ],
        if (hasMedia) ...[
          OmniaMenuItem(
            icon: Icons.fiber_manual_record_rounded,
            label: state.recording ? l10n.stopRecording : l10n.recordClip,
            trailing: ref.shortcutOf(ShortcutAction.recordClip, l10n),
            active: state.recording,
            onPressed: () => ref.dispatch(const ToggleRecording()),
          ),
          OmniaMenuItem(
            icon: Icons.repeat_rounded,
            label: l10n.abLoop,
            trailing: ref.shortcutOf(ShortcutAction.abLoop, l10n),
            active: state.loopA != null,
            onPressed: () => ref.dispatch(const CycleAbLoop()),
          ),
          OmniaMenuItem(
            icon: Icons.equalizer_rounded,
            label: l10n.equalizer,
            active: state.equalizerEnabled,
            onPressed: () => ref.read(toolPanelProvider.notifier).toggle(ToolPanel.equalizer),
          ),
        ],
        if (state.mediaType == MediaType.image && state.file != null) ...[
          const OmniaMenuDivider(),
          OmniaMenuItem(
            icon: Icons.tune_rounded,
            label: 'Retoucher et redimensionner...',
            onPressed: () => ImageEditDialog.show(context, state.file!),
          ),
          OmniaMenuItem(
            icon: Icons.rotate_right_rounded,
            label: 'Pivoter de 90°',
            onPressed: () => ref.dispatch(const RotateDocument()),
          ),
        ],
        const OmniaMenuDivider(),
        OmniaMenuItem(
          icon: state.fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          label: state.fullscreen ? l10n.exitFullscreen : l10n.fullscreen,
          trailing: ref.shortcutOf(ShortcutAction.toggleFullscreen, l10n),
          onPressed: () => ref.dispatch(const ToggleFullscreen()),
        ),
        if (hasMedia)
          OmniaMenuItem(
            icon: Icons.picture_in_picture_alt_outlined,
            label: l10n.miniPlayer,
            trailing: ref.shortcutOf(ShortcutAction.miniPlayer, l10n),
            onPressed: () => ref.dispatch(const ToggleMiniPlayer()),
          ),
        OmniaSubmenu(
          icon: Icons.push_pin_outlined,
          label: l10n.alwaysOnTop,
          children: [
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
        ),

        OmniaMenuItem(
          icon: Icons.view_sidebar_outlined,
          label: panelVisible ? l10n.panelHide : l10n.panelShow,
          trailing: ref.shortcutOf(ShortcutAction.toggleSidePanel, l10n),
          onPressed: () => ref.dispatch(const ToggleSidePanel()),
        ),
        const OmniaMenuDivider(),
        OmniaMenuItem(
          icon: Icons.insert_drive_file_outlined,
          label: l10n.openFile,
          trailing: ref.shortcutOf(ShortcutAction.openFile, l10n),
          onPressed: () => pickAndOpenFile(ref),
        ),
        OmniaMenuItem(
          icon: Icons.folder_outlined,
          label: l10n.openFolder,
          trailing: ref.shortcutOf(ShortcutAction.openFolder, l10n),
          onPressed: () => pickAndOpenFolder(ref),
        ),
        if (path != null)
          OmniaMenuItem(
            icon: Icons.folder_open_rounded,
            label: l10n.contextReveal,
            onPressed: () => ref.dispatch(RevealInFolder(path)),
          ),
        const OmniaMenuDivider(),
        OmniaMenuItem(
          icon: Icons.settings_outlined,
          label: l10n.settingsTitle,
          trailing: ref.shortcutOf(ShortcutAction.settings, l10n),
          onPressed: () => ref.read(settingsUiProvider.notifier).show(),
        ),
        OmniaMenuItem(
          icon: Icons.keyboard_outlined,
          label: l10n.helpTitle,
          trailing: ref.shortcutOf(ShortcutAction.help, l10n),
          onPressed: () => ref.read(helpVisibleProvider.notifier).toggle(),
        ),
      ],
      onOpen: () => _setMenuOpen(true),
      onClose: () => _setMenuOpen(false),
      // L'ancre est la scène entière : pour MenuAnchor, un clic sur la scène
      // est donc un clic « dans » le menu, qui ne le ferme pas. Tant que le
      // menu est ouvert, un voile posé sur la scène s'en charge.
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTapUp: (details) => _controller.open(position: details.localPosition),
            child: widget.child,
          ),
          if (_menuOpen)
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('stage-menu-dismiss'),
                behavior: HitTestBehavior.opaque,
                // Comme un menu du système : le clic qui ferme le menu ne
                // lance ni n'arrête la lecture.
                onTapDown: (_) => _controller.close(),
                onSecondaryTapUp: (details) => _controller.open(position: details.localPosition),
              ),
            ),
        ],
      ),
    );
  }

  void _setMenuOpen(bool open) {
    // Menu ouvert : les contrôles restent affichés ; fermé, le clavier
    // revient au lecteur.
    if (open) {
      _chrome.hold(this);
    } else {
      _chrome.release(this);
      _focus.restore();
    }
    if (!mounted || _menuOpen == open) return;
    // Le menu peut se fermer pendant une reconstruction (écran qui change) :
    // l'état suit alors à l'image suivante.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setMenuOpen(open));
      return;
    }
    setState(() => _menuOpen = open);
  }

  static String _formatSpeed(double speed) => formatSpeed(speed);
}
