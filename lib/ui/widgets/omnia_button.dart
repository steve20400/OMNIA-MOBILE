import 'package:flutter/material.dart';

import '../theme/omnia_theme.dart';

/// Bouton texte d'OMNIA, avec icône et étiquette de raccourci optionnelles.
///
/// [primary] : fond projecteur, texte velours — un seul par écran.
/// Sinon : contour couture, texte écran.
class OmniaButton extends StatefulWidget {
  const OmniaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.shortcut,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? shortcut;
  final bool primary;

  @override
  State<OmniaButton> createState() => _OmniaButtonState();
}

class _OmniaButtonState extends State<OmniaButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final enabled = widget.onPressed != null;

    final restBg = widget.primary ? colors.projector : Colors.transparent;
    final hoverBg = widget.primary
        ? Color.lerp(colors.projector, colors.screen, 0.12)!
        : colors.hover;
    final fg = widget.primary ? colors.velvet : colors.screen;
    final shortcutColor = widget.primary
        ? colors.velvet.withValues(alpha: 0.7)
        : colors.dust;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: _hovered && enabled ? 1 : 0),
          duration: OmniaMotion.hover,
          curve: OmniaMotion.hoverCurve,
          builder: (context, t, _) => Container(
            padding: const EdgeInsets.symmetric(
              horizontal: OmniaMetrics.space4,
              vertical: OmniaMetrics.space2 + 2,
            ),
            decoration: BoxDecoration(
              color: Color.lerp(restBg, hoverBg, t),
              borderRadius: OmniaMetrics.controlRadius,
              border: widget.primary
                  ? null
                  : Border.all(color: Color.lerp(colors.seam, colors.dust, t * 0.5)!),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: OmniaMetrics.iconSize - 2, color: fg),
                  const SizedBox(width: OmniaMetrics.space2),
                ],
                // Souple : dans une fenêtre étroite, le libellé s'abrège au
                // lieu de faire déborder le bouton. Il garde sa largeur
                // naturelle dès qu'il y a la place.
                Flexible(
                  child: Text(
                    widget.label,
                    style: type.bodyStrong.copyWith(color: fg),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.shortcut != null) ...[
                  const SizedBox(width: OmniaMetrics.space3),
                  Text(widget.shortcut!, style: type.shortcut.copyWith(color: shortcutColor)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
