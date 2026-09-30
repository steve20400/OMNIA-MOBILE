import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/content_uri.dart';
import '../theme/omnia_theme.dart';
import 'player_screen.dart';

/// Écran d'animation de chargement / démarrage (Splash Screen) d'OMNIA.
///
/// Affiche le logo OMNIA dans son halo ambre, la signature du faisceau
/// lumineux, et effectue un fondu doux vers l'écran du lecteur universel.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({
    super.key,
    this.duration = const Duration(milliseconds: 1400),
    this.targetWidget,
  });

  final Duration duration;
  final Widget? targetWidget;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _beamProgress;
  Timer? _navTimer;
  bool _navigated = false;

  /// La plateforme résout encore le fichier reçu d'une autre application : on
  /// tient l'écran plutôt que d'entrer dans un lecteur vide qui sauterait sur
  /// le média une seconde plus tard.
  bool _waitingForFile = false;

  /// Avancement de la copie de secours (0 à 1), négatif quand rien n'est copié.
  double _prepareProgress = -1;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _logoFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );

    _logoScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutCubic),
      ),
    );

    _beamProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.95, curve: Curves.easeInOutCubic),
    );

    _controller.forward();

    // Vérifie immédiatement si un fichier est transmis via "Ouvrir avec"
    _checkInitialIntent();

    _navTimer = Timer(widget.duration, _onSplashElapsed);
  }

  void _onSplashElapsed() {
    // Un fichier est encore en préparation : on ne part pas sans lui.
    if (_waitingForFile) return;
    _proceed();
  }

  /// Délai entre deux questions à la plateforme pendant qu'elle résout l'URI.
  static const Duration _pollInterval = Duration(milliseconds: 120);

  /// Au-delà, on renonce et l'application s'ouvre normalement : mieux vaut un
  /// accueil qu'un écran de démarrage qui ne finit jamais.
  static const Duration _resolveTimeout = Duration(minutes: 5);

  /// Interroge la plateforme jusqu'à ce qu'elle ait résolu le fichier reçu.
  ///
  /// La résolution se fait sur un fil de fond côté Android : l'écran reste
  /// animé pendant ce temps, là où l'ancienne version bloquait le fil
  /// principal — et donc le premier affichage — le temps de recopier
  /// entièrement le média.
  Future<void> _checkInitialIntent() async {
    const channel = MethodChannel('dev.omnia.mobile/intent');
    final elapsed = Stopwatch()..start();
    while (mounted && !_navigated && elapsed.elapsed < _resolveTimeout) {
      Map<Object?, Object?>? reply;
      try {
        reply = await channel.invokeMethod<Map<Object?, Object?>>('getInitialFile');
      } on Object {
        // Plateforme sans ce canal (bureau, tests) : démarrage normal.
        _giveUpWaiting();
        return;
      }
      if (!mounted || _navigated) return;

      // Aucun fichier transmis : l'application s'ouvre sur son accueil.
      if (reply == null) {
        _giveUpWaiting();
        return;
      }

      if (reply['status'] == 'ready') {
        final path = reply['path'] as String?;
        final name = reply['name'] as String?;
        if (path == null || path.isEmpty) {
          _giveUpWaiting();
          return;
        }
        // Un URI `content://` n'a pas de nom lisible : celui relevé par la
        // plateforme donne au média son type et son titre.
        if (name != null) rememberContentUriName(path, name);
        _clearHold();
        // Transition immédiate vers le lecteur, sans attendre la fin du splash.
        _proceed(initialFile: path);
        return;
      }

      if (reply['status'] != 'pending') {
        _giveUpWaiting();
        return;
      }

      final progress = (reply['progress'] as num?)?.toDouble() ?? -1;
      setState(() {
        _waitingForFile = true;
        _prepareProgress = progress;
      });
      await Future<void>.delayed(_pollInterval);
    }
    _giveUpWaiting();
  }

  /// Retire le voyant d'attente, sans décider de la suite.
  void _clearHold() {
    if (!mounted) return;
    if (!_waitingForFile && _prepareProgress < 0) return;
    setState(() {
      _waitingForFile = false;
      _prepareProgress = -1;
    });
  }

  /// Plus rien à attendre, et aucun fichier à ouvrir : l'écran suivant reprend
  /// son cours, y compris si le délai du splash s'est écoulé pendant l'attente.
  void _giveUpWaiting() {
    final wasWaiting = _waitingForFile;
    _clearHold();
    if (wasWaiting && _navTimer?.isActive != true) _proceed();
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _proceed({String? initialFile}) {
    if (!mounted || _navigated) return;
    _navigated = true;
    _navTimer?.cancel();

    final target = widget.targetWidget ?? PlayerScreen(initialFile: initialFile);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, anim, secAnim) => target,
        transitionsBuilder: (context, anim, secAnim, child) {
          return FadeTransition(opacity: anim, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.velvet,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Toucher l'écran permet de passer immédiatement — sauf pendant la
        // préparation d'un fichier reçu : entrer dans un lecteur vide pour y
        // voir surgir le média une seconde plus tard serait pire qu'attendre.
        onTap: () {
          if (_waitingForFile) return;
          _proceed();
        },
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo OMNIA avec halo et échelle douce
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: colors.projector.withValues(alpha: 0.35 * _logoFade.value),
                              blurRadius: 36,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            'assets/icons/omnia-256.png',
                            width: 96,
                            height: 96,
                            errorBuilder: (_, __, ___) => _FallbackLogo(colors: colors),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Titre OMNIA
                  FadeTransition(
                    opacity: _logoFade,
                    child: Text(
                      'O M N I A',
                      style: TextStyle(
                        fontFamily: OmniaFonts.ui,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 10,
                        color: colors.screen,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Sous-titre
                  FadeTransition(
                    opacity: _logoFade,
                    child: Text(
                      'LECTEUR UNIVERSEL',
                      style: TextStyle(
                        fontFamily: OmniaFonts.ui,
                        fontSize: 11,
                        letterSpacing: 4,
                        fontWeight: FontWeight.w600,
                        color: colors.dust,
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Faisceau lumineux de chargement (Signature OMNIA Beam)
                  SizedBox(
                    width: 140,
                    height: 3,
                    child: Stack(
                      children: [
                        Container(
                          width: 140,
                          height: 3,
                          decoration: BoxDecoration(
                            color: colors.curtain,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: _beamProgress.value.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  colors.projector.withValues(alpha: 0.2),
                                  colors.projector,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color: colors.projector.withValues(alpha: 0.6),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Préparation d'un fichier reçu d'une autre application.
                  // Sans cette ligne, une copie de secours ne serait qu'un
                  // écran figé : l'utilisateur doit voir qu'il se passe
                  // quelque chose, et jusqu'où c'est allé.
                  if (_waitingForFile) ...[
                    const SizedBox(height: 20),
                    Text(
                      _prepareProgress >= 0
                          ? 'Préparation du fichier… ${(_prepareProgress * 100).round()} %'
                          : 'Ouverture du fichier…',
                      style: TextStyle(
                        fontFamily: OmniaFonts.ui,
                        fontSize: 11,
                        letterSpacing: 1.5,
                        color: colors.dust,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FallbackLogo extends StatelessWidget {
  const _FallbackLogo({required this.colors});
  final OmniaColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.curtain,
      child: Center(
        child: Icon(Icons.play_arrow_rounded, color: colors.projector, size: 54),
      ),
    );
  }
}
