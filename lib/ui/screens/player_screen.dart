import 'dart:async';

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
import '../settings/settings_controller.dart';
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

/// Scène de lecture mobile immersive avec rotation d'écran, verrouillage étanche,
/// boutons d'ouverture flottants, et barre latérale responsive (à gauche en paysage, en bas en portrait).
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> with WidgetsBindingObserver {
  bool _controlsVisible = true;
  Timer? _hideTimer;

  // Gestes tactiles
  double _gestureStartX = 0;
  double _gestureStartY = 0;
  _DragGestureType _gestureType = _DragGestureType.none;

  // Luminosité logicielle (0.0 à 1.0)
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
    if (_controlsVisible) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
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
      // Un balayage vertical complet ajuste le volume de 0 à 100
      final delta = (-details.delta.dy / 250.0) * 100.0;
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
        final scrubFraction = (dx / width) * 90;
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
      setState(() {
        _showDoubleTapLeft = true;
        _showDoubleTapRight = false;
      });
      _doubleTapAnimTimer?.cancel();
      _doubleTapAnimTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _showDoubleTapLeft = false);
      });
    } else if (details.localPosition.dx > width * 0.65) {
      ref.dispatch(const SeekRelative(10));
      setState(() {
        _showDoubleTapRight = true;
        _showDoubleTapLeft = false;
      });
      _doubleTapAnimTimer?.cancel();
      _doubleTapAnimTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _showDoubleTapRight = false);
      });
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
      body: Stack(
        children: [
          // Disposition principale (Scène + Barre latérale / tiroir)
          LayoutBuilder(
            builder: (context, constraints) {
              final isLandscape = constraints.maxWidth > constraints.maxHeight;

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

          // Languette de la barre latérale sur le bord gauche, au milieu vertical de l'écran
          if (!isPanelVisible && !_isLocked)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: PanelEdgeTab(visible: _controlsVisible),
              ),
            ),

          // Boutons flottants d'ouverture en bas à droite lorsque aucun média n'est chargé
          // 1er bouton en partant du bas : "Ouvrir un fichier"
          // 2e bouton au-dessus (marge de 16px) : "Ouvrir un dossier"
          if (!playback.hasMedia && !_isLocked)
            Positioned(
              right: 20,
              bottom: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton.extended(
                    heroTag: 'fab-open-folder',
                    onPressed: () => pickAndOpenFolder(ref),
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('Ouvrir un dossier'),
                    backgroundColor: colors.curtain,
                    foregroundColor: colors.projector,
                    elevation: 4,
                  ),
                  const SizedBox(height: 16),
                  FloatingActionButton.extended(
                    heroTag: 'fab-open-file',
                    onPressed: () => pickAndOpenFile(ref),
                    icon: const Icon(Icons.file_open_rounded),
                    label: const Text('Ouvrir un fichier'),
                    backgroundColor: colors.projector,
                    foregroundColor: colors.velvet,
                    elevation: 6,
                  ),
                ],
              ),
            ),

          // SettingsOverlay superposé directement dans l'arbre racine
          const Positioned.fill(
            child: SettingsOverlay(),
          ),
        ],
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
      onTap: () {
        if (_isLocked) {
          setState(() {
            _showUnlockPill = true;
            _startUnlockPillTimer();
          });
          return;
        }
        if (playback.hasMedia) {
          // Un tap sur l'écran permet de mettre pause / relancer directement
          ref.dispatch(const TogglePlay());
          setState(() {
            _controlsVisible = true;
          });
          _startHideTimer();
        } else {
          _toggleControls();
        }
      },
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

          // OSD Volume (Droite) - Valeur réelle 0-100% sans multiplication erronée
          if (_showVolumeOsd && !_isLocked)
            Positioned(
              right: 24,
              top: constraints.maxHeight / 2 - 60,
              child: _buildOsdPill(
                icon: playback.volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                label: '${playback.volume.round()}%',
                progress: (playback.volume / 100.0).clamp(0.0, 1.0),
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
                        // Barre supérieure
                        _buildTopBar(playback, colors, l10n, isLandscape, isPanelVisible),

                        // Barre inférieure contextuelle (Vidéo, Document, ou Image)
                        _buildBottomControls(playback, colors, l10n),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Quand l'écran est verrouillé : barrière tactile totale absorbante
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

          // Bouton flottant de déverrouillage écran
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

  Widget _buildTopBar(
    PlaybackState playback,
    OmniaColors colors,
    AppLocalizations l10n,
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
            tooltip: playback.hasMedia ? 'Fermer le média' : 'Retour',
            onPressed: () {
              if (playback.hasMedia) {
                ref.dispatch(const Stop());
              } else if (Navigator.canPop(context)) {
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
          // Ouvrir un fichier
          OmniaIconButton(
            icon: Icons.file_open_rounded,
            tooltip: l10n.openFile,
            onPressed: () => pickAndOpenFile(ref),
          ),
          // Paramètres OMNIA
          OmniaIconButton(
            icon: Icons.settings_outlined,
            tooltip: l10n.settingsTitle,
            onPressed: () => ref.read(settingsUiProvider.notifier).show(),
          ),
          // Bouton Liste de lecture (ToggleSidePanel)
          OmniaIconButton(
            icon: Icons.playlist_play_rounded,
            tooltip: 'Liste de lecture',
            active: isPanelVisible,
            onPressed: () => ref.dispatch(const ToggleSidePanel()),
          ),
          // Bouton Rotation d'écran (Bascule Portrait ↔ Paysage)
          OmniaIconButton(
            icon: Icons.screen_rotation_rounded,
            tooltip: isLandscape ? 'Passer en portrait' : 'Passer en paysage',
            onPressed: () => _toggleScreenOrientation(isLandscape),
          ),
          // OMNIA Connect
          OmniaIconButton(
            icon: Icons.wifi_tethering_rounded,
            tooltip: 'Projeter (OMNIA Connect)',
            onPressed: () => OmniaConnectModal.show(context),
          ),
          // Bouton Verrouillage tactile étanche
          OmniaIconButton(
            icon: Icons.lock_outline_rounded,
            tooltip: 'Verrouiller l’écran',
            onPressed: () {
              setState(() {
                _isLocked = true;
                _controlsVisible = false;
                _showUnlockPill = true;
                _startUnlockPillTimer();
              });
            },
          ),
          // Mode PiP / Mini-lecteur
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

  Widget _buildBottomControls(
    PlaybackState playback,
    OmniaColors colors,
    AppLocalizations l10n,
  ) {
    if (playback.mediaType.isDocument) {
      return Container(
        color: colors.curtain.withValues(alpha: 0.9),
        child: const DocumentBar(),
      );
    }

    if (playback.mediaType.isImage) {
      return Container(
        color: colors.curtain.withValues(alpha: 0.9),
        child: const ImageBar(),
      );
    }

    // Vidéo et Audio : Contrôles de lecture et BeamProgressBar
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Barre de progression (Faisceau lumineux)
          const BeamProgressBar(),
          const SizedBox(height: 8),
          // Ligne des boutons de commande
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Indicateur de temps écoulé / total
              Text(
                '${_formatDuration(playback.position)} / ${_formatDuration(playback.duration)}',
                style: TextStyle(
                  fontFamily: OmniaFonts.mono,
                  fontSize: 12,
                  color: colors.screen,
                ),
              ),

              // Boutons centraux de transport
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OmniaIconButton(
                    icon: Icons.replay_10_rounded,
                    tooltip: 'Recul 10s',
                    onPressed: () => ref.dispatch(const SeekRelative(-10)),
                  ),
                  const SizedBox(width: 4),
                  OmniaIconButton(
                    icon: Icons.skip_previous_rounded,
                    tooltip: l10n.prevFile,
                    onPressed: () => ref.dispatch(const PreviousFile()),
                  ),
                  const SizedBox(width: 8),
                  // Bouton Play/Pause
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.projector,
                    ),
                    child: IconButton(
                      icon: Icon(
                        playback.status == PlaybackStatus.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: colors.velvet,
                        size: 32,
                      ),
                      onPressed: () => ref.dispatch(const TogglePlay()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OmniaIconButton(
                    icon: Icons.skip_next_rounded,
                    tooltip: l10n.nextFile,
                    onPressed: () => ref.dispatch(const NextFile()),
                  ),
                  const SizedBox(width: 4),
                  OmniaIconButton(
                    icon: Icons.forward_10_rounded,
                    tooltip: 'Avance 10s',
                    onPressed: () => ref.dispatch(const SeekRelative(10)),
                  ),
                ],
              ),

              // Sélecteur de vitesse rapide
              _buildSpeedButton(playback, colors),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedButton(PlaybackState playback, OmniaColors colors) {
    return PopupMenuButton<double>(
      initialValue: playback.speed,
      tooltip: 'Vitesse de lecture',
      onSelected: (speed) => ref.dispatch(SetSpeed(speed)),
      color: colors.curtain,
      itemBuilder: (context) => [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
          .map(
            (s) => PopupMenuItem(
              value: s,
              child: Text(
                '${s}x',
                style: TextStyle(
                  fontFamily: OmniaFonts.mono,
                  color: playback.speed == s ? colors.projector : colors.screen,
                  fontWeight: playback.speed == s ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.seam),
          color: colors.velvet.withValues(alpha: 0.6),
        ),
        child: Text(
          '${playback.speed}x',
          style: TextStyle(
            fontFamily: OmniaFonts.mono,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: colors.projector,
          ),
        ),
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
              quarterTurns: -1,
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: colors.velvet,
                valueColor: AlwaysStoppedAnimation<Color>(colors.projector),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrubOsd(PlaybackState playback, OmniaColors colors) {
    final isForward = _scrubOffset.inMilliseconds >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.projector, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isForward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
                color: colors.projector,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                '${isForward ? '+' : ''}${_scrubOffset.inSeconds} s',
                style: TextStyle(
                  fontFamily: OmniaFonts.mono,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.projector,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _formatDuration(_scrubTarget),
            style: TextStyle(
              fontFamily: OmniaFonts.mono,
              fontSize: 13,
              color: colors.screen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoubleTapIndicator(IconData icon, String label, OmniaColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        shape: BoxShape.circle,
        border: Border.all(color: colors.projector.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colors.projector, size: 28),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: OmniaFonts.ui,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: colors.screen,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
