import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/media_type.dart';
import '../../core/models/playback_state.dart';
import '../../core/models/playback_status.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../file_dialogs.dart';
import '../panel_controller.dart';
import '../settings/settings_screen.dart';
import '../theme/omnia_theme.dart';
import '../widgets/beam_progress_bar.dart';
import '../widgets/document_bar.dart';
import '../widgets/image_bar.dart';
import '../widgets/mobile_bottom_playlist.dart';
import '../widgets/omnia_connect_modal.dart';
import '../widgets/omnia_icon_button.dart';
import '../widgets/side_panel.dart';
import '../widgets/stage.dart';

enum _DragGestureType { none, volume, brightness, scrub }

/// Scène de lecture mobile immersive avec rotation d'écran, verrouillage étanche
/// et barre latérale responsive (à gauche en paysage, en bas en portrait et mini-lecteur).
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

  // Verrouillage tactile étanche (Screen Lock)
  bool _isLocked = false;
  bool _showUnlockPill = false;
  Timer? _unlockPillTimer;

  // Accélération 2x par maintien prolongé (Hold-to-2x)
  bool _isHolding2x = false;
  double _preHoldSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startHideTimer();
  }

  @override
  void dispose() {
    // Restaure la libre rotation du capteur quand on quitte le lecteur
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _brightnessTimer?.cancel();
    _volumeTimer?.cancel();
    _doubleTapAnimTimer?.cancel();
    _unlockPillTimer?.cancel();
    super.dispose();
  }

  void _startUnlockPillTimer() {
    _unlockPillTimer?.cancel();
    _unlockPillTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showUnlockPill = false);
    });
  }

  void _toggleScreenOrientation(bool isLandscape) {
    if (isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (_isLocked) return;
    final playback = ref.read(playbackStateProvider);
    if (!playback.hasVideo || playback.status != PlaybackStatus.playing) return;
    _preHoldSpeed = playback.speed;
    ref.dispatch(const SetSpeed(2.0));
    setState(() => _isHolding2x = true);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (_isHolding2x) {
      ref.dispatch(SetSpeed(_preHoldSpeed));
      setState(() => _isHolding2x = false);
    }
  }

  void _onLongPressCancel() {
    if (_isHolding2x) {
      ref.dispatch(SetSpeed(_preHoldSpeed));
      setState(() => _isHolding2x = false);
    }
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
    if (_isLocked) {
      setState(() {
        _showUnlockPill = true;
        _startUnlockPillTimer();
      });
      return;
    }
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _startHideTimer();
  }

  void _onPanStart(DragStartDetails details, BoxConstraints constraints) {
    if (_isLocked) return;
    _gestureStartX = details.localPosition.dx;
    _gestureStartY = details.localPosition.dy;
    _gestureType = _DragGestureType.none;
    _scrubOffset = Duration.zero;
  }

  void _onPanUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    if (_isLocked) return;
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

    if (_gestureType == _DragGestureType.brightness) {
      final delta = -details.delta.dy / 250.0;
      setState(() {
        _screenBrightness = (_screenBrightness + delta).clamp(0.05, 1.0);
        _showBrightnessOsd = true;
      });
      _brightnessTimer?.cancel();
      _brightnessTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showBrightnessOsd = false);
      });
    } else if (_gestureType == _DragGestureType.volume) {
      final delta = -details.delta.dy / 250.0;
      ref.dispatch(VolumeRelative(delta));
      setState(() {
        _showVolumeOsd = true;
      });
      _volumeTimer?.cancel();
      _volumeTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showVolumeOsd = false);
      });
    } else if (_gestureType == _DragGestureType.scrub) {
      final playback = ref.read(playbackStateProvider);
      final duration = playback.duration;
      if (duration > Duration.zero) {
        final scrubFraction = (dx / width) * 90; // jusqu'à 90s par balayage
        final newOffset = Duration(seconds: scrubFraction.round());
        final targetMs = (playback.position.inMilliseconds + newOffset.inMilliseconds)
            .clamp(0, duration.inMilliseconds);
        setState(() {
          _scrubOffset = newOffset;
          _scrubTarget = Duration(milliseconds: targetMs);
          _showScrubOsd = true;
        });
      }
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
    if (_isLocked) return;
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
    final isPanelVisible = ref.watch(panelStateProvider.select((s) => s.visible));
    final isMini = playback.miniPlayer;

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isLandscape = constraints.maxWidth > constraints.maxHeight;

          // RÈGLES DE DISPOSITION D'OMNIA (selon les directives exactes) :
          // 1. En mini-lecteur (Android) : la barre latérale/liste est TOUJOURS en dessous.
          // 2. En mode normal :
          //    - Si écran couché en largeur (Paysage) : la barre latérale est à GAUCHE.
          //    - Si écran debout (Portrait) : la barre latérale est EN DESSOUS.
          if (isMini) {
            return Column(
              children: [
                Expanded(
                  child: _buildStageAndControls(
                    context,
                    constraints,
                    playback,
                    colors,
                    l10n,
                    isLandscape,
                    isPanelVisible,
                  ),
                ),
                if (isPanelVisible) const MobileBottomPlaylist(height: 200),
              ],
            );
          }

          if (isLandscape) {
            // Mode Paysage couché : Barre latérale à GAUCHE
            return Row(
              children: [
                if (isPanelVisible)
                  const SizedBox(
                    width: 290,
                    child: SidePanel(drawer: false),
                  ),
                Expanded(
                  child: _buildStageAndControls(
                    context,
                    constraints,
                    playback,
                    colors,
                    l10n,
                    isLandscape,
                    isPanelVisible,
                  ),
                ),
              ],
            );
          }

          // Mode Portrait debout : Barre latérale EN DESSOUS
          return Column(
            children: [
              Expanded(
                child: _buildStageAndControls(
                  context,
                  constraints,
                  playback,
                  colors,
                  l10n,
                  isLandscape,
                  isPanelVisible,
                ),
              ),
              if (isPanelVisible) const MobileBottomPlaylist(height: 240),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStageAndControls(
    BuildContext context,
    BoxConstraints constraints,
    PlaybackState playback,
    OmniaColors colors,
    AppLocalizations l10n,
    bool isLandscape,
    bool isPanelVisible,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      onDoubleTapDown: (details) => _triggerDoubleTap(details, constraints.maxWidth),
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _onLongPressEnd,
      onLongPressCancel: _onLongPressCancel,
      onPanStart: (details) => _onPanStart(details, constraints),
      onPanUpdate: (details) => _onPanUpdate(details, constraints),
      onPanEnd: _onPanEnd,
      child: Stack(
        children: [
          // Surface média (AbsorbPointer quand verrouillé pour bloquer les gestes internes)
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: _isLocked,
              child: _buildStage(playback),
            ),
          ),

          // Indicateur de maintien 2x
          if (_isHolding2x && !_isLocked)
            Positioned(
              top: 54,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.projector, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fast_forward_rounded, color: colors.projector, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '2x Vitesse rapide',
                        style: TextStyle(
                          fontFamily: OmniaFonts.ui,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: colors.screen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
          if (_showBrightnessOsd && !_isLocked)
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
          if (_showVolumeOsd && !_isLocked)
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
          if (_showScrubOsd && !_isLocked)
            Center(
              child: _buildScrubOsd(playback, colors),
            ),

          // Animation visuelle de saut rapide gauche (-10s)
          if (_showDoubleTapLeft && !_isLocked)
            Positioned(
              left: 40,
              top: constraints.maxHeight / 2 - 40,
              child: _buildDoubleTapIndicator(Icons.replay_10_rounded, '-10 s', colors),
            ),

          // Animation visuelle de saut rapide droite (+10s)
          if (_showDoubleTapRight && !_isLocked)
            Positioned(
              right: 40,
              top: constraints.maxHeight / 2 - 40,
              child: _buildDoubleTapIndicator(Icons.forward_10_rounded, '+10 s', colors),
            ),

          // Barres de contrôle superposées
          // Lorsque _isLocked est actif : AbsorbPointer empêche TOUT clic sur les boutons !
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: _isLocked,
              child: AnimatedOpacity(
                opacity: _controlsVisible && !_isLocked ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_controlsVisible || _isLocked,
                  child: SafeArea(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Barre supérieure (Retour, Titre, Rotation, Playlist, OMNIA Connect, Verrou, PiP)
                        _buildTopBar(playback, colors, isLandscape, isPanelVisible),

                        // Barre inférieure contextuelle (Vidéo, Document, ou Image)
                        _buildBottomControls(playback, colors, l10n),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Languette latérale gauche (PanelEdgeTab) pour ouvrir la barre latérale / playlist
          if (!isPanelVisible && !_isLocked)
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Center(child: PanelEdgeTab()),
            ),

          // Boutons flottants "Ouvrir un dossier" et "Ouvrir un fichier"
          // Positionnés proprement au-dessus de la barre de navigation système
          if (!playback.hasFile && !_isLocked)
            Positioned(
              right: 16,
              bottom: MediaQuery.paddingOf(context).bottom + 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton.extended(
                    heroTag: 'player-fab-open-folder',
                    onPressed: () => pickAndOpenFolder(ref),
                    icon: Icon(Icons.folder_open_rounded, color: colors.projector, size: 20),
                    label: Text(
                      'Ouvrir un dossier',
                      style: TextStyle(
                        fontFamily: OmniaFonts.ui,
                        fontWeight: FontWeight.bold,
                        color: colors.projector,
                        fontSize: 13,
                      ),
                    ),
                    backgroundColor: colors.curtain,
                    elevation: 4,
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton.extended(
                    heroTag: 'player-fab-open-file',
                    onPressed: () => pickAndOpenFile(ref),
                    icon: Icon(Icons.file_open_rounded, color: colors.velvet, size: 20),
                    label: Text(
                      'Ouvrir un fichier',
                      style: TextStyle(
                        fontFamily: OmniaFonts.ui,
                        fontWeight: FontWeight.bold,
                        color: colors.velvet,
                        fontSize: 13,
                      ),
                    ),
                    backgroundColor: colors.projector,
                    elevation: 6,
                  ),
                ],
              ),
            ),

          // Quand l'écran est verrouillé : barrière tactile totale absorbante
          // Tout tap n'importe où sur l'écran affiche le widget de déverrouillage
          if (_isLocked)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    _showUnlockPill = true;
                    _startUnlockPillTimer();
                  });
                },
                child: const SizedBox.expand(),
              ),
            ),

          // Bouton flottant de déverrouillage écran (seul élément interactif quand verrouillé)
          if (_isLocked && _showUnlockPill)
            Positioned(
              top: 60,
              left: 20,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _isLocked = false;
                    _showUnlockPill = false;
                    _controlsVisible = true;
                    _startHideTimer();
                  });
                },
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: colors.projector, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: colors.projector.withValues(alpha: 0.35),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_open_rounded, color: colors.projector, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Déverrouiller l’écran',
                        style: TextStyle(
                          color: colors.screen,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStage(PlaybackState playback) {
    return const Stage();
  }

  Future<void> _triggerPip(PlaybackState playback) async {
    ref.dispatch(const ToggleMiniPlayer());
    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('dev.omnia.mobile/pip');
        final double ratio = (playback.videoWidth != null && playback.videoHeight != null && playback.videoHeight! > 0)
            ? (playback.videoWidth! / playback.videoHeight!)
            : (16.0 / 9.0);
        final int aspectWidth = (ratio * 100).round().clamp(42, 239);
        final int aspectHeight = 100;
        await channel.invokeMethod('enterPip', {
          'aspectRatioWidth': aspectWidth,
          'aspectRatioHeight': aspectHeight,
        });
      } catch (_) {}
    }
  }

  Widget _buildTopBar(
    PlaybackState playback,
    OmniaColors colors,
    bool isLandscape,
    bool isPanelVisible,
  ) {
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
            tooltip: 'Fermer le média',
            onPressed: () {
              if (playback.hasFile) {
                ref.dispatch(const CloseFile());
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              playback.file?.name ?? 'OMNIA',
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
          if (playback.hasFile)
            OmniaIconButton(
              icon: Icons.picture_in_picture_alt_rounded,
              tooltip: 'Mode flottant (PiP)',
              onPressed: () => _triggerPip(playback),
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
              OmniaIconButton(
                icon: Icons.more_vert_rounded,
                tooltip: 'Options de lecture',
                onPressed: () => _showPlaybackOptionsMenu(context, playback, colors, l10n),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Ligne secondaire : timecode et sélecteur de vitesse rapide
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${playback.position.inMinutes}:${(playback.position.inSeconds % 60).toString().padLeft(2, '0')} / ${playback.duration.inMinutes}:${(playback.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontFamily: OmniaFonts.mono,
                    fontSize: 12,
                    color: colors.dust,
                  ),
                ),
                InkWell(
                  onTap: () => _showSpeedSelector(context, playback, colors),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.velvet.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.seam),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.speed_rounded, color: colors.projector, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '${playback.speed.toStringAsFixed(playback.speed == playback.speed.roundToDouble() ? 0 : 2)}x',
                          style: TextStyle(
                            fontFamily: OmniaFonts.mono,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colors.screen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPlaybackOptionsMenu(
    BuildContext context,
    PlaybackState playback,
    OmniaColors colors,
    AppLocalizations l10n,
  ) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.78,
          ),
          decoration: BoxDecoration(
            color: colors.curtain,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: colors.seam),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                // Poignée de tirage
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.dust.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      Icon(Icons.tune_rounded, color: colors.projector, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'Options de lecture',
                        style: TextStyle(
                          fontFamily: OmniaFonts.ui,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: colors.screen,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: colors.dust, size: 20),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                ),
                Divider(color: colors.seam, height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      // Paramètres OMNIA
                      ListTile(
                        leading: Icon(Icons.settings_outlined, color: colors.projector),
                        title: Text('Paramètres OMNIA', style: TextStyle(color: colors.screen, fontFamily: OmniaFonts.ui, fontWeight: FontWeight.w600)),
                        subtitle: Text('Général, lecture, réseau et interface', style: TextStyle(color: colors.dust, fontSize: 12)),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => const SettingsOverlay()),
                          );
                        },
                      ),

                      // OMNIA Connect (Projection & Télécommande)
                      ListTile(
                        leading: Icon(Icons.wifi_tethering_rounded, color: colors.projector),
                        title: Text('OMNIA Connect (Zero-Internet)', style: TextStyle(color: colors.screen, fontFamily: OmniaFonts.ui, fontWeight: FontWeight.w600)),
                        subtitle: Text('Scanner QR Code, télécommande et projection PC', style: TextStyle(color: colors.dust, fontSize: 12)),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          OmniaConnectModal.show(context);
                        },
                      ),

                      // Mode flottant (PiP)
                      ListTile(
                        leading: Icon(Icons.picture_in_picture_alt_rounded, color: colors.projector),
                        title: Text('Mode flottant (Picture-in-Picture)', style: TextStyle(color: colors.screen, fontFamily: OmniaFonts.ui, fontWeight: FontWeight.w600)),
                        subtitle: Text('Continuer la lecture par-dessus d’autres applications', style: TextStyle(color: colors.dust, fontSize: 12)),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _triggerPip(playback);
                        },
                      ),

                      // Pivoter l'écran
                      ListTile(
                        leading: Icon(Icons.screen_rotation_rounded, color: colors.projector),
                        title: Text('Pivoter l\'écran', style: TextStyle(color: colors.screen, fontFamily: OmniaFonts.ui, fontWeight: FontWeight.w600)),
                        subtitle: Text(isLandscape ? 'Basculer en mode Portrait' : 'Basculer en mode Paysage', style: TextStyle(color: colors.dust, fontSize: 12)),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _toggleScreenOrientation(isLandscape);
                        },
                      ),

                      // Verrouiller l'écran
                      ListTile(
                        leading: Icon(Icons.lock_outline_rounded, color: colors.projector),
                        title: Text('Verrouiller l’écran tactile', style: TextStyle(color: colors.screen, fontFamily: OmniaFonts.ui, fontWeight: FontWeight.w600)),
                        subtitle: Text('Bloque les gestes accidentels pendant le visionnage', style: TextStyle(color: colors.dust, fontSize: 12)),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          setState(() {
                            _isLocked = true;
                            _controlsVisible = false;
                            _showUnlockPill = true;
                            _startUnlockPillTimer();
                          });
                        },
                      ),

                      Divider(color: colors.seam),

                      // Vitesse de lecture
                      ListTile(
                        leading: Icon(Icons.speed_rounded, color: colors.projector),
                        title: Text('Vitesse de lecture', style: TextStyle(color: colors.screen, fontFamily: OmniaFonts.ui, fontWeight: FontWeight.w600)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colors.projector.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${playback.speed}×',
                            style: TextStyle(color: colors.projector, fontWeight: FontWeight.bold, fontFamily: OmniaFonts.mono),
                          ),
                        ),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _showSpeedSelector(context, playback, colors);
                        },
                      ),

                      // Format d'image / Aspect Ratio
                      ListTile(
                        leading: Icon(Icons.aspect_ratio_rounded, color: colors.projector),
                        title: Text('Format d’image', style: TextStyle(color: colors.screen, fontFamily: OmniaFonts.ui, fontWeight: FontWeight.w600)),
                        trailing: Text(
                          _aspectModeLabel(playback.aspectMode),
                          style: TextStyle(color: colors.dust, fontSize: 13),
                        ),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _showAspectModeSelector(context, playback, colors);
                        },
                      ),

                      // Pistes audio
                      if (playback.audioTracks.isNotEmpty)
                        ListTile(
                          leading: Icon(Icons.audiotrack_rounded, color: colors.projector),
                          title: Text('Piste audio', style: TextStyle(color: colors.screen, fontFamily: OmniaFonts.ui, fontWeight: FontWeight.w600)),
                          trailing: Text(
                            playback.currentAudioTrack?.title ?? playback.currentAudioTrack?.language ?? 'Auto',
                            style: TextStyle(color: colors.dust, fontSize: 13),
                          ),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _showAudioTrackSelector(context, playback, colors);
                          },
                        ),

                      // Sous-titres
                      if (playback.subtitleTracks.isNotEmpty)
                        ListTile(
                          leading: Icon(Icons.subtitles_rounded, color: colors.projector),
                          title: Text('Sous-titres', style: TextStyle(color: colors.screen, fontFamily: OmniaFonts.ui, fontWeight: FontWeight.w600)),
                          trailing: Text(
                            playback.currentSubtitleTrack?.title ?? playback.currentSubtitleTrack?.language ?? 'Désactivés',
                            style: TextStyle(color: colors.dust, fontSize: 13),
                          ),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _showSubtitleTrackSelector(context, playback, colors);
                          },
                        ),

                      // Rotation vidéo 90°
                      ListTile(
                        leading: Icon(Icons.rotate_right_rounded, color: colors.projector),
                        title: Text('Rotation vidéo (90°)', style: TextStyle(color: colors.screen, fontFamily: OmniaFonts.ui, fontWeight: FontWeight.w600)),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          ref.dispatch(const RotateVideo());
                        },
                      ),

                      // Capture d'écran (Image)
                      ListTile(
                        leading: Icon(Icons.camera_alt_outlined, color: colors.projector),
                        title: Text('Prendre une capture d’écran', style: TextStyle(color: colors.screen, fontFamily: OmniaFonts.ui, fontWeight: FontWeight.w600)),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          ref.dispatch(const TakeScreenshot());
                        },
                      ),

                      // Boucle A-B
                      ListTile(
                        leading: Icon(Icons.repeat_rounded, color: colors.projector),
                        title: Text('Boucle A-B', style: TextStyle(color: colors.screen, fontFamily: OmniaFonts.ui, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          playback.loopA != null
                              ? (playback.loopB != null ? 'Boucle active (A-B)' : 'Point A défini')
                              : 'Définir un intervalle répété',
                          style: TextStyle(color: colors.dust, fontSize: 12),
                        ),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          ref.dispatch(const CycleAbLoop());
                        },
                      ),

                      Divider(color: colors.seam),

                      // Ouvrir un fichier
                      ListTile(
                        leading: Icon(Icons.file_open_rounded, color: colors.projector),
                        title: Text('Ouvrir un fichier...', style: TextStyle(color: colors.screen, fontFamily: OmniaFonts.ui, fontWeight: FontWeight.w600)),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          pickAndOpenFile(ref);
                        },
                      ),

                      // Ouvrir un dossier
                      ListTile(
                        leading: Icon(Icons.folder_open_rounded, color: colors.projector),
                        title: Text('Ouvrir un dossier...', style: TextStyle(color: colors.screen, fontFamily: OmniaFonts.ui, fontWeight: FontWeight.w600)),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          pickAndOpenFolder(ref);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _aspectModeLabel(AspectMode mode) => switch (mode) {
        AspectMode.auto => 'Auto',
        AspectMode.wide => '16:9',
        AspectMode.standard => '4:3',
        AspectMode.fill => 'Remplir',
      };

  void _showAspectModeSelector(BuildContext context, PlaybackState playback, OmniaColors colors) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.curtain,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Format d’image', style: TextStyle(color: colors.screen, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Divider(color: colors.seam, height: 1),
              ...AspectMode.values.map((mode) {
                final isSelected = playback.aspectMode == mode;
                return ListTile(
                  title: Text(_aspectModeLabel(mode), style: TextStyle(color: isSelected ? colors.projector : colors.screen, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  trailing: isSelected ? Icon(Icons.check_rounded, color: colors.projector) : null,
                  onTap: () {
                    ref.dispatch(SetAspectMode(mode));
                    Navigator.of(ctx).pop();
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showAudioTrackSelector(BuildContext context, PlaybackState playback, OmniaColors colors) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.curtain,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Pistes audio', style: TextStyle(color: colors.screen, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Divider(color: colors.seam, height: 1),
              Expanded(
                child: ListView(
                  children: playback.audioTracks.map((track) {
                    final isSelected = playback.currentAudioTrack?.id == track.id;
                    return ListTile(
                      title: Text(track.title ?? track.language ?? track.id, style: TextStyle(color: isSelected ? colors.projector : colors.screen, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                      trailing: isSelected ? Icon(Icons.check_rounded, color: colors.projector) : null,
                      onTap: () {
                        ref.dispatch(SelectAudioTrack(track));
                        Navigator.of(ctx).pop();
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSubtitleTrackSelector(BuildContext context, PlaybackState playback, OmniaColors colors) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.curtain,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Sous-titres', style: TextStyle(color: colors.screen, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Divider(color: colors.seam, height: 1),
              ListTile(
                title: Text('Désactiver les sous-titres', style: TextStyle(color: playback.currentSubtitleTrack == null ? colors.projector : colors.screen)),
                trailing: playback.currentSubtitleTrack == null ? Icon(Icons.check_rounded, color: colors.projector) : null,
                onTap: () {
                  ref.dispatch(const ToggleSubtitle());
                  Navigator.of(ctx).pop();
                },
              ),
              Expanded(
                child: ListView(
                  children: playback.subtitleTracks.map((track) {
                    final isSelected = playback.currentSubtitleTrack?.id == track.id;
                    return ListTile(
                      title: Text(track.title ?? track.language ?? track.id, style: TextStyle(color: isSelected ? colors.projector : colors.screen, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                      trailing: isSelected ? Icon(Icons.check_rounded, color: colors.projector) : null,
                      onTap: () {
                        ref.dispatch(SelectSubtitleTrack(track));
                        Navigator.of(ctx).pop();
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSpeedSelector(BuildContext context, PlaybackState playback, OmniaColors colors) {
    const speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.curtain,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Vitesse de lecture',
                      style: TextStyle(
                        fontFamily: OmniaFonts.ui,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colors.screen,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: colors.dust),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final s in speeds)
                      ChoiceChip(
                        label: Text('${s}x'),
                        selected: (playback.speed - s).abs() < 0.05,
                        selectedColor: colors.projector.withValues(alpha: 0.3),
                        labelStyle: TextStyle(
                          color: (playback.speed - s).abs() < 0.05
                              ? colors.projector
                              : colors.screen,
                          fontWeight: (playback.speed - s).abs() < 0.05
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        onSelected: (_) {
                          ref.dispatch(SetSpeed(s));
                          Navigator.of(ctx).pop();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
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
