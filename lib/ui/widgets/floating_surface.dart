import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../theme/omnia_theme.dart';

/// Surface flottante d'OMNIA : rideau translucide, flou d'arrière-plan, coins
/// doux, ombre discrète. Utilisée par la barre de contrôles et les overlays.
///
/// Au-dessus d'une vidéo, pas de flou : chaque image de la vidéo forcerait à
/// recalculer le flou de toute la surface, une charge graphique qui fait
/// clignoter l'image sur une machine modeste (voir le diagnostic de
/// l'itération 2). Le rideau devient alors presque opaque, et l'aspect reste
/// très proche.
class FloatingSurface extends ConsumerWidget {
  const FloatingSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.borderRadius = OmniaMetrics.overlayRadius,
    this.blur,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  /// Force le flou (`true`) ou son absence (`false`). Par défaut : flou, sauf
  /// quand une vidéo est affichée.
  final bool? blur;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final overVideo = ref.watch(playbackStateProvider.select((s) => s.hasFile && s.hasVideo));
    final useBlur = blur ?? !overVideo;

    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: useBlur ? colors.overlay : colors.curtain.withValues(alpha: 0.93),
        borderRadius: borderRadius,
        border: Border.all(color: colors.seam.withValues(alpha: 0.6)),
      ),
      child: child,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: OmniaMetrics.overlayShadowAlpha),
            blurRadius: OmniaMetrics.overlayShadowBlur,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: useBlur
            ? BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: OmniaMetrics.overlayBlur,
                  sigmaY: OmniaMetrics.overlayBlur,
                ),
                child: body,
              )
            : body,
      ),
    );
  }
}
