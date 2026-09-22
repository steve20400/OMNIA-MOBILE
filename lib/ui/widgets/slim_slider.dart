import 'package:flutter/material.dart';

import '../theme/omnia_theme.dart';

/// Curseur fin et sobre (volume). Volontairement sans halo : la lumière est
/// réservée au faisceau de progression.
class SlimSlider extends StatefulWidget {
  const SlimSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = OmniaMetrics.volumeSliderWidth,
    this.muted = false,
  });

  /// Valeur 0–1.
  final double value;
  final ValueChanged<double> onChanged;
  final double width;

  /// Affiche le remplissage en gris (son coupé).
  final bool muted;

  @override
  State<SlimSlider> createState() => _SlimSliderState();
}

class _SlimSliderState extends State<SlimSlider> {
  bool _hovered = false;
  bool _dragging = false;

  /// Position du pointeur rapportée à la largeur RÉELLE du curseur : étiré
  /// dans un panneau (réglages d'image) ou pivoté (égaliseur), il n'a pas la
  /// largeur demandée, et la valeur saturait avant la fin de la course.
  void _set(double dx) {
    final width = context.size?.width ?? widget.width;
    if (width <= 0) return;
    widget.onChanged((dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _set(d.localPosition.dx),
        onHorizontalDragStart: (d) {
          setState(() => _dragging = true);
          _set(d.localPosition.dx);
        },
        onHorizontalDragUpdate: (d) => _set(d.localPosition.dx),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        child: SizedBox(
          width: widget.width,
          height: OmniaMetrics.iconButtonSize,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _hovered || _dragging ? 1 : 0),
            duration: OmniaMotion.hover,
            curve: OmniaMotion.hoverCurve,
            builder: (context, t, _) => CustomPaint(
              painter: _SlimSliderPainter(
                value: widget.value.clamp(0.0, 1.0),
                active: t,
                track: colors.seam,
                fill: widget.muted ? colors.dust : colors.screen,
                thumb: colors.screen,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlimSliderPainter extends CustomPainter {
  const _SlimSliderPainter({
    required this.value,
    required this.active,
    required this.track,
    required this.fill,
    required this.thumb,
  });

  final double value;
  final double active;
  final Color track;
  final Color fill;
  final Color thumb;

  @override
  void paint(Canvas canvas, Size size) {
    const th = OmniaMetrics.volumeSliderThickness;
    final cy = size.height / 2;
    final r = Radius.circular(th / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - th / 2, size.width, th), r),
      Paint()..color = track,
    );
    final w = size.width * value;
    if (w > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - th / 2, w, th), r),
        Paint()..color = fill,
      );
    }
    final thumbR = OmniaMetrics.volumeThumbRadius * active;
    if (thumbR > 0) {
      canvas.drawCircle(Offset(w.clamp(thumbR, size.width - thumbR), cy), thumbR, Paint()..color = thumb);
    }
  }

  @override
  bool shouldRepaint(_SlimSliderPainter old) =>
      old.value != value ||
      old.active != active ||
      old.track != track ||
      old.fill != fill ||
      old.thumb != thumb;
}
