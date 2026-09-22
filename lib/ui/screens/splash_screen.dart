import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/omnia_theme.dart';
import 'home_screen.dart';

/// Écran d'animation de chargement / démarrage (Splash Screen) d'OMNIA.
///
/// Affiche le logo OMNIA dans son halo ambre, la signature du faisceau
/// lumineux, et effectue un fondu doux vers l'écran d'accueil de l'application.
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

    _navTimer = Timer(widget.duration, _proceed);
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _proceed() {
    if (!mounted || _navigated) return;
    _navigated = true;

    final target = widget.targetWidget ?? const HomeScreen();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, anim, secAnim) => target,
        transitionsBuilder: (context, anim, secAnim, child) {
          return FadeTransition(opacity: anim, child: child);
        },
        transitionDuration: const Duration(milliseconds: 350),
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
        onTap: _proceed, // Toucher l'écran permet de passer immédiatement
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
