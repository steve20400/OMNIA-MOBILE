import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/end_of_playback_mode.dart';
import '../../core/models/video_adjust.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/app_localizations.dart';
import '../osd/osd_controller.dart';
import '../osd/osd_message.dart';
import '../theme/omnia_theme.dart';
import 'floating_surface.dart';

/// Affichage à l'écran : un retour bref et discret pour chaque action.
///
/// Une seule pastille, en haut de la scène, qui apparaît en glissant de
/// quelques pixels et s'efface d'elle-même. Les chiffres sont en mono pour ne
/// pas trembler quand la valeur change.
///
/// La pastille ne dépasse jamais [pillMaxWidth], ni la scène moins une marge
/// de chaque côté : un texte trop long s'abrège.
class OsdOverlay extends ConsumerWidget {
  const OsdOverlay({super.key});

  /// Largeur de la pastille quand la place ne manque pas.
  static const double pillMaxWidth = 480;

  /// Largeur permise à la pastille sur une scène de [available] pixels.
  static double maxPillWidth(double available) =>
      math.min(pillMaxWidth, math.max(0.0, available - 2 * OmniaMetrics.space4));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(osdProvider);

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          return Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: OmniaMetrics.space5),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxPillWidth(available)),
                child: AnimatedSwitcher(
                  duration: OmniaMotion.reveal,
                  switchInCurve: OmniaMotion.revealCurve,
                  switchOutCurve: OmniaMotion.concealCurve,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -0.25),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: message == null
                      ? const SizedBox.shrink(key: ValueKey('osd-none'))
                      : _OsdPill(
                          // Une clé par nature de message : deux volumes
                          // successifs se mettent à jour en place, un volume
                          // puis une vitesse se remplacent en fondu.
                          key: ValueKey(message.runtimeType),
                          message: message,
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OsdPill extends StatelessWidget {
  const _OsdPill({super.key, required this.message});

  final OsdMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);

    final (IconData icon, Widget body) = switch (message) {
      OsdSeek(:final deltaSeconds, :final position, :final duration) => (
          deltaSeconds < 0 ? Icons.replay_rounded : Icons.forward_rounded,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (deltaSeconds != 0) ...[
                Text(_signed(deltaSeconds), style: type.osdValue),
                Text('  ·  ', style: type.osdLabel),
              ],
              Flexible(
                child: Text(
                  formatTimecode(position, reference: duration),
                  style: type.osdLabel,
                ),
              ),
            ],
          ),
        ),
      OsdVolume(:final volume, :final muted) => (
          muted
              ? Icons.volume_off_rounded
              : volume == 0
                  ? Icons.volume_mute_rounded
                  : volume < 50
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  muted ? l10n.osdMuted : l10n.osdVolume(volume.round()),
                  style: muted ? type.osdLabel : type.osdValue,
                ),
              ),
              const SizedBox(width: OmniaMetrics.space3),
              _LevelBar(level: muted ? 0 : volume / 100),
            ],
          ),
        ),
      OsdSpeed(:final speed) => (
          Icons.speed_rounded,
          Text(l10n.speedValue(formatSpeed(speed)), style: type.osdValue),
        ),
      OsdPlayState(:final playing) => (
          playing ? Icons.play_arrow_rounded : Icons.pause_rounded,
          Text(playing ? l10n.play : l10n.pause, style: type.osdLabel),
        ),
      OsdFileChanged(:final name, :final forward) => (
          forward ? Icons.skip_next_rounded : Icons.skip_previous_rounded,
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              name,
              style: type.osdLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      OsdEndMode(:final mode) => (
          switch (mode) {
            EndOfPlaybackMode.stop => Icons.stop_circle_outlined,
            EndOfPlaybackMode.next => Icons.playlist_play_rounded,
            EndOfPlaybackMode.repeatOne => Icons.repeat_one_rounded,
            EndOfPlaybackMode.loopFolder => Icons.repeat_rounded,
            EndOfPlaybackMode.shuffle => Icons.shuffle_rounded,
          },
          Text(
            switch (mode) {
              EndOfPlaybackMode.stop => l10n.endModeStop,
              EndOfPlaybackMode.next => l10n.endModeNext,
              EndOfPlaybackMode.repeatOne => l10n.endModeRepeatOne,
              EndOfPlaybackMode.loopFolder => l10n.endModeLoopFolder,
              EndOfPlaybackMode.shuffle => l10n.endModeShuffle,
            },
            style: type.osdLabel,
          ),
        ),
      OsdAlwaysOnTop(:final enabled) => (
          Icons.push_pin_rounded,
          Text(
            enabled ? l10n.osdAlwaysOnTopOn : l10n.osdAlwaysOnTopOff,
            style: type.osdLabel,
          ),
        ),
      OsdFullscreen(:final enabled) => (
          enabled ? Icons.fullscreen_rounded : Icons.fullscreen_exit_rounded,
          Text(enabled ? l10n.fullscreen : l10n.exitFullscreen, style: type.osdLabel),
        ),
      OsdSubtitles(:final visible, :final trackLabel) => (
          visible ? Icons.subtitles_rounded : Icons.subtitles_off_rounded,
          Text(
            visible ? (trackLabel ?? l10n.subtitles) : l10n.subtitlesOff,
            style: type.osdLabel,
          ),
        ),
      OsdSubtitleDelay(:final seconds) => (
          Icons.subtitles_rounded,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(l10n.subtitleDelay, style: type.osdLabel)),
              Text('  ·  ', style: type.osdLabel),
              Text(
                l10n.subtitleDelayValue(
                  '${seconds > 0 ? '+' : ''}${seconds.toStringAsFixed(1)}',
                ),
                style: type.osdValue,
              ),
            ],
          ),
        ),
      OsdAudioTrack(:final label) => (
          Icons.audiotrack_rounded,
          Text(label.isEmpty ? l10n.audioTrackAuto : label, style: type.osdLabel),
        ),
      OsdAbLoop(:final a, :final b) => (
          Icons.repeat_rounded,
          Text(
            a == null
                ? l10n.abLoopCleared
                : b == null
                    ? '${l10n.abLoopSetA}  ·  ${formatTimecode(a)}'
                    : '${l10n.abLoopSetB}  ·  ${formatTimecode(a)} → ${formatTimecode(b)}',
            style: type.osdLabel,
          ),
        ),
      OsdScreenshot(:final path) => (
          Icons.photo_camera_rounded,
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.screenshotSaved, style: type.osdLabel),
                const SizedBox(height: 3),
                Text(
                  path,
                  style: type.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      OsdScreenshotFailed() => (
          Icons.no_photography_outlined,
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.screenshotFailed, style: type.osdLabel),
                const SizedBox(height: 3),
                Text(
                  l10n.screenshotFailedHint,
                  style: type.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      OsdRecordingStarted() => (
          Icons.fiber_manual_record_rounded,
          Text(l10n.recordingStarted, style: type.osdLabel),
        ),
      OsdRecordingSaved(:final path, :final length) => (
          Icons.video_file_outlined,
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  length == null
                      ? l10n.recordingSaved
                      : '${l10n.recordingSaved} · ${formatTimecode(length)}',
                  style: type.osdLabel,
                ),
                const SizedBox(height: 3),
                Text(
                  path,
                  style: type.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      OsdRecordingFailed() => (
          Icons.error_outline_rounded,
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.recordingFailed, style: type.osdLabel),
                const SizedBox(height: 3),
                Text(
                  l10n.recordingFailedHint,
                  style: type.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      OsdAspect(:final mode) => (
          Icons.aspect_ratio_rounded,
          Text(
            switch (mode) {
              AspectMode.auto => l10n.aspectAuto,
              AspectMode.wide => l10n.aspectWide,
              AspectMode.standard => l10n.aspectStandard,
              AspectMode.fill => l10n.aspectFill,
            },
            style: type.osdLabel,
          ),
        ),
      OsdVideoZoom(:final zoom) => (
          Icons.zoom_in_rounded,
          Text(l10n.videoZoomValue((math.pow(2, zoom) * 100).round()), style: type.osdValue),
        ),
      OsdVideoRotation(:final quarterTurns) => (
          Icons.rotate_right_rounded,
          Text(l10n.videoRotation(quarterTurns * 90), style: type.osdLabel),
        ),
      OsdEqualizer(:final enabled, :final preset) => (
          Icons.equalizer_rounded,
          Text(
            !enabled ? l10n.equalizerOff : (preset == null ? l10n.equalizerOn : _presetLabel(l10n, preset)),
            style: type.osdLabel,
          ),
        ),
      OsdMiniPlayer(:final enabled) => (
          Icons.picture_in_picture_alt_rounded,
          Text(enabled ? l10n.miniPlayer : l10n.miniPlayerExit, style: type.osdLabel),
        ),
    };

    return FloatingSurface(
      borderRadius: OmniaMetrics.controlRadius,
      padding: const EdgeInsets.symmetric(
        horizontal: OmniaMetrics.space4,
        vertical: OmniaMetrics.space2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: OmniaMetrics.iconSize, color: colors.projector),
          const SizedBox(width: OmniaMetrics.space3),
          // Le texte prend la place qui reste dans la pastille, et s'abrège
          // sur une ligne au-delà ; les explications (échecs) en ont deux.
          Flexible(
            child: DefaultTextStyle.merge(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: body,
            ),
          ),
        ],
      ),
    );
  }

  static String _signed(double seconds) {
    final rounded = seconds.round();
    return '${rounded > 0 ? '+' : '−'}${rounded.abs()} s';
  }

  static String _presetLabel(AppLocalizations l10n, String preset) => presetLabel(l10n, preset);
}

/// Libellé traduit d'un préréglage d'égaliseur.
String presetLabel(AppLocalizations l10n, String preset) => switch (preset) {
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

/// Jauge horizontale fine, pour le volume.
class _LevelBar extends StatelessWidget {
  const _LevelBar({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: OmniaMetrics.osdLevelWidth,
      height: OmniaMetrics.volumeSliderThickness,
      child: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.seam,
              borderRadius: BorderRadius.circular(OmniaMetrics.volumeSliderThickness),
            ),
            child: const SizedBox.expand(),
          ),
          AnimatedFractionallySizedBox(
            duration: OmniaMotion.hover,
            curve: OmniaMotion.hoverCurve,
            widthFactor: level.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.projector,
                borderRadius: BorderRadius.circular(OmniaMetrics.volumeSliderThickness),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}
