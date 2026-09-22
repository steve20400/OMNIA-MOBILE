import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/media_type.dart';
import '../../core/models/playback_state.dart';
import '../../core/models/playback_status.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../theme/omnia_theme.dart';
import '../widgets/beam_progress_bar.dart';
import '../widgets/document_bar.dart';
import '../widgets/image_bar.dart';
import '../widgets/omnia_connect_modal.dart';
import '../widgets/omnia_icon_button.dart';
import '../widgets/stage.dart';

enum _DragGestureType { none, volume, brightness, scrub }

/// Scène de lecture mobile immersive avec contrôles gestuels tactiles avancés.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> with WidgetsBindingObserver {
  bool _controlsVisible = true;
  Timer? _hideTimer;

  // Gestes tactiles avancés
  _DragGestureType _gestureType = _DragGestureType.none;
  double _gestureStartX = 0.0;
  double _gestureStartY = 0.0;

  // Luminosité (0.0 à 1.0)
  double _screenBrightness = 1.0;
  bool _showBrightnessOsd = false;
  Timer? _brightnessTimer;

  // Volume OSD
  bool _showVolumeOsd = false;
  Timer? _volumeTimer;

  // Balayage horizontal (Scrubbing)
  bool _showScrubOsd = false;
  Duration _scrubOffset = Duration.zero;
  Duration _scrubTarget = Duration.zero;

  // Animation visuelle de saut rapide (Double-tap)
  bool _showDoubleTapLeft = false;
  bool _showDoubleTapRight = false;
  Timer? _doubleTapAnimTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startHideTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _brightnessTimer?.cancel();
    _volumeTimer?.cancel();
    _doubleTapAnimTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      // Sauvegarde immédiate lors du basculement en arrière-plan
      final service = ref.read(playbackServiceProvider);
      unawaited(service.idle);
    }
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

  void _onPanStart(DragStartDetails details, BoxConstraints constraints) {
    _gestureStartX = details.localPosition.dx;
    _gestureStartY = details.localPosition.dy;
    _gestureType = _DragGestureType.none;
    _scrubOffset = Duration.zero;
  }

  void _onPanUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    final dx = details.localPosition.dx - _gestureStartX;
    final dy = details.localPosition.dy - _gestureStartY;
    final width = constraints.maxWidth;

    if (_gestureType == _DragGestureType.none) {
      // Détermination du type de geste
      if (dx.abs() > 20 && dx.abs() > dy.abs()) {
        _gestureType = _DragGestureType.scrub;
      } else if (dy.abs() > 20) {
        if (_gestureStartX < width * 0.4) {
          _gestureType = _DragGestureType.brightness;
        } else if (_gestureStartX > width * 0.6) {
          _gestureType = _DragGestureType.volume;
        }
      }
    }

    switch (_gestureType) {
      case _DragGestureType.brightness:
        final delta = -details.delta.dy / constraints.maxHeight;
        setState(() {
          _screenBrightness = (_screenBrightness + delta).clamp(0.1, 1.0);
          _showBrightnessOsd = true;
        });
        _brightnessTimer?.cancel();
        _brightnessTimer = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _showBrightnessOsd = false);
        });
        break;

      case _DragGestureType.volume:
        final delta = -details.delta.dy / 300.0;
        ref.dispatch(VolumeRelative(delta));
        setState(() {
          _showVolumeOsd = true;
        });
        _volumeTimer?.cancel();
        _volumeTimer = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _showVolumeOsd = false);
        });
        break;

      case _DragGestureType.scrub:
        final playback = ref.read(playbackStateProvider);
        if (playback.duration > Duration.zero) {
          final scrubRatio = dx / (constraints.maxWidth * 0.7);
          final secondsDelta = (scrubRatio * 120).round(); // Jusqu'à ±2 minutes
          final currentPos = playback.position;
          final target = (currentPos + Duration(seconds: secondsDelta)).clamp(
            Duration.zero,
            playback.duration,
          );
          setState(() {
            _showScrubOsd = true;
            _scrubOffset = Duration(seconds: secondsDelta);
            _scrubTarget = target;
          });
        }
        break;

      case _DragGestureType.none:
        break;
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_gestureType == _DragGestureType.scrub && _showScrubOsd) {
      ref.dispatch(SeekAbsolute(_scrubTarget));
      setState(() {
        _showScrubOsd = false;
      });
    }
    _gestureType = _DragGestureType.none;
  }

  void _triggerDoubleTap(TapDownDetails details, double width) {
    if (details.localPosition.dx < width * 0.35) {
      ref.dispatch(const SeekRelative(-10));
      setState(() => _showDoubleTapLeft = true);
      _doubleTapAnimTimer?.cancel();
      _doubleTapAnimTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _showDoubleTapLeft = false);
      });
    } else if (details.localPosition.dx > width * 0.65) {
      ref.dispatch(const SeekRelative(10));
      setState(() => _showDoubleTapRight = true);
      _doubleTapAnimTimer?.cancel();
      _doubleTapAnimTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _showDoubleTapRight = false);
      });
    } else {
      ref.dispatch(const TogglePlay());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final playback = ref.watch(playbackStateProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            onDoubleTapDown: (details) => _triggerDoubleTap(details, constraints.maxWidth),
            onPanStart: (details) => _onPanStart(details, constraints),
            onPanUpdate: (details) => _onPanUpdate(details, constraints),
            onPanEnd: _onPanEnd,
            child: Stack(
              children: [
                // Surface média
                Positioned.fill(
                  child: _buildStage(playback),
                ),

                // Filtre de luminosité logicielle
                if (_screenBrightness < 1.0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: Colors.black.withValues(
                          alpha: (1.0 - _screenBrightness).clamp(0.0, 0.9),
                        ),
                      ),
                    ),
                  ),

                // OSD Luminosité (Gauche)
                if (_showBrightnessOsd)
                  Positioned(
                    left: 24,
                    top: constraints.maxHeight / 2 - 60,
                    child: _buildOsdPill(
                      icon: Icons.brightness_6_rounded,
                      label: '${(_screenBrightness * 100).round()}%',
                      progress: _screenBrightness,
                      colors: colors,
                    ),
                  ),

                // OSD Volume (Droite)
                if (_showVolumeOsd)
                  Positioned(
                    right: 24,
                    top: constraints.maxHeight / 2 - 60,
                    child: _buildOsdPill(
                      icon: playback.volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      label: '${(playback.volume * 100).round()}%',
                      progress: playback.volume,
                      colors: colors,
                    ),
                  ),

                // OSD Scrubbing (Centre)
                if (_showScrubOsd)
                  Center(
                    child: _buildScrubOsd(playback, colors),
                  ),

                // Animation visuelle de saut rapide gauche (-10s)
                if (_showDoubleTapLeft)
                  Positioned(
                    left: 40,
                    top: constraints.maxHeight / 2 - 40,
                    child: _buildDoubleTapIndicator(Icons.replay_10_rounded, '-10 s', colors),
                  ),

                // Animation visuelle de saut rapide droite (+10s)
                if (_showDoubleTapRight)
                  Positioned(
                    right: 40,
                    top: constraints.maxHeight / 2 - 40,
                    child: _buildDoubleTapIndicator(Icons.forward_10_rounded, '+10 s', colors),
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
                          // Barre supérieure (Retour, Titre, PiP)
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
          );
        },
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
            icon: Icons.wifi_tethering_rounded,
            tooltip: 'Projeter (OMNIA Connect)',
            onPressed: () => OmniaConnectModal.show(context),
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

  Widget _buildOsdPill({
    required IconData icon,
    required String label,
    required double progress,
    required OmniaColors colors,
  }) {
    return Container(
      width: 48,
      height: 140,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colors.curtain.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.seam),
      ),
      child: Column(
        children: [
          Icon(icon, color: colors.projector, size: 20),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: OmniaFonts.mono,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: colors.screen,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: colors.velvet,
                  valueColor: AlwaysStoppedAnimation(colors.projector),
                  minHeight: 6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrubOsd(PlaybackState playback, OmniaColors colors) {
    final sign = _scrubOffset.inSeconds >= 0 ? '+' : '';
    final deltaStr = '$sign${_scrubOffset.inSeconds} s';
    final targetMinutes = (_scrubTarget.inSeconds / 60).floor();
    final targetSeconds = (_scrubTarget.inSeconds % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: colors.curtain.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.seam),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            deltaStr,
            style: TextStyle(
              fontFamily: OmniaFonts.mono,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colors.projector,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$targetMinutes:$targetSeconds',
            style: TextStyle(
              fontFamily: OmniaFonts.mono,
              fontSize: 14,
              color: colors.screen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoubleTapIndicator(IconData icon, String label, OmniaColors colors) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.curtain.withValues(alpha: 0.75),
        shape: BoxShape.circle,
        border: Border.all(color: colors.projector.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colors.projector, size: 28),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontFamily: OmniaFonts.ui,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: colors.screen,
            ),
          ),
        ],
      ),
    );
  }
}
