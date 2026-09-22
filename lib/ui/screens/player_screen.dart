import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/media_type.dart';
import '../../core/models/playback_state.dart';
import '../../core/models/playback_status.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../theme/omnia_theme.dart';
import '../widgets/audio_stage.dart';
import '../widgets/beam_progress_bar.dart';
import '../widgets/document_bar.dart';
import '../widgets/image_bar.dart';
import '../widgets/image_stage.dart';
import '../widgets/omnia_icon_button.dart';
import '../widgets/pdf_stage.dart';
import '../widgets/text_view.dart';

import '../widgets/stage.dart';

/// Scène de lecture mobile immersive avec contrôles gestuels tactiles.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _controlsVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _startHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final playback = ref.watch(playbackStateProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: (details) {
          final width = MediaQuery.of(context).size.width;
          if (details.localPosition.dx < width / 3) {
            ref.dispatch(const SeekRelative(-10));
          } else if (details.localPosition.dx > width * 2 / 3) {
            ref.dispatch(const SeekRelative(10));
          } else {
            ref.dispatch(const TogglePlay());
          }
        },
        child: Stack(
          children: [
            // Surface média
            Positioned.fill(
              child: _buildStage(playback),
            ),

            // Barres de contrôle superposées
            AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Barre supérieure (Retour, Titre, Menu)
                      _buildTopBar(playback, colors),

                      // Barre inférieure contextuelle (Vidéo, Document, ou Image)
                      _buildBottomControls(playback, colors, l10n),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStage(PlaybackState playback) {
    return const Stage();
  }

  Widget _buildTopBar(PlaybackState playback, OmniaColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          OmniaIconButton(
            icon: Icons.arrow_back_rounded,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              playback.file?.name ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: OmniaFonts.ui,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: colors.screen,
              ),
            ),
          ),
          OmniaIconButton(
            icon: Icons.picture_in_picture_alt_rounded,
            tooltip: 'Mode flottant (PiP)',
            onPressed: () {
              ref.dispatch(const ToggleMiniPlayer());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(PlaybackState playback, OmniaColors colors, AppLocalizations l10n) {
    if (playback.mediaType == MediaType.pdf || playback.mediaType == MediaType.text) {
      return const DocumentBar();
    }
    if (playback.mediaType == MediaType.image) {
      return const ImageBar();
    }

    // Vidéo et Audio
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Barre de progression
          BeamProgressBar(
            progress: playback.progress,
            duration: playback.duration,
            onSeek: (pos) => ref.dispatch(SeekAbsolute(pos)),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OmniaIconButton(
                icon: Icons.replay_10_rounded,
                onPressed: () => ref.dispatch(const SeekRelative(-10)),
              ),
              OmniaIconButton(
                icon: Icons.skip_previous_rounded,
                onPressed: () => ref.dispatch(const PreviousFile()),
              ),
              OmniaIconButton(
                icon: playback.status == PlaybackStatus.playing
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_filled_rounded,
                size: 52,
                iconSize: 42,
                active: true,
                onPressed: () => ref.dispatch(const TogglePlay()),
              ),
              OmniaIconButton(
                icon: Icons.skip_next_rounded,
                onPressed: () => ref.dispatch(const NextFile()),
              ),
              OmniaIconButton(
                icon: Icons.forward_10_rounded,
                onPressed: () => ref.dispatch(const SeekRelative(10)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
