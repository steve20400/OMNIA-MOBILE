import 'package:flutter/material.dart';

import '../theme/omnia_theme.dart';

/// Bouton icône d'OMNIA : sans ondulation Material, avec un survol animé.
///
/// [active] allume l'icône en couleur projecteur ; [danger] réserve le rouge
/// d'alerte au survol (bouton de fermeture de fenêtre).
class OmniaIconButton extends StatefulWidget {
  const OmniaIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = OmniaMetrics.iconButtonSize,
    this.iconSize = OmniaMetrics.iconSize,
    this.active = false,
    this.activeColor,
    this.danger = false,
    this.borderRadius = OmniaMetrics.controlRadius,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final bool active;

  /// Couleur de l'icône active ; projecteur par défaut. L'enregistrement en
  /// cours, par exemple, s'allume en rouge.
  final Color? activeColor;
  final bool danger;
  final BorderRadius borderRadius;

  @override
  State<OmniaIconButton> createState() => _OmniaIconButtonState();
}

class _OmniaIconButtonState extends State<OmniaIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = widget.onPressed != null;

    final activeColor = widget.activeColor ?? colors.projector;
    final restIcon = widget.active ? activeColor : colors.dust;
    final hoverIcon = widget.active ? activeColor : colors.screen;
    final hoverBg = widget.danger ? colors.alert : colors.hover;
    final hoverIconFinal = widget.danger ? colors.screen : hoverIcon;

    Widget button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: _hovered && enabled ? 1 : 0),
          duration: OmniaMotion.hover,
          curve: OmniaMotion.hoverCurve,
          builder: (context, t, _) {
            final bg = Color.lerp(Colors.transparent, hoverBg, t)!;
            final fg = Color.lerp(restIcon, hoverIconFinal, t)!;
            return Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: _pressed ? colors.pressed : bg,
                borderRadius: widget.borderRadius,
              ),
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: enabled ? fg : colors.dust.withValues(alpha: 0.4),
              ),
            );
          },
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}
