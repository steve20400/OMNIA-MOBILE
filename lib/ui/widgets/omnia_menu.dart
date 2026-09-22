import 'package:flutter/material.dart';

import '../theme/omnia_theme.dart';

/// Briques de menu d'OMNIA, bâties sur `MenuAnchor` (sous-menus natifs,
/// ouverture à une position donnée) et habillées par le thème.
///
/// Toutes les lignes de menu de l'application passent par ici, pour que
/// menu contextuel, menu des récents et sous-menus se ressemblent.

/// Une ligne cliquable.
class OmniaMenuItem extends StatelessWidget {
  const OmniaMenuItem({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailing,
    this.active = false,
    this.enabled = true,
    this.subtitle,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Texte à droite : raccourci, ou valeur courante.
  final String? trailing;

  /// Ligne mise en avant (valeur sélectionnée).
  final bool active;
  final bool enabled;

  /// Seconde ligne discrète (dossier d'un fichier récent).
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final foreground = !enabled
        ? colors.dust.withValues(alpha: 0.5)
        : active
            ? colors.projector
            : colors.screen;

    return MenuItemButton(
      onPressed: enabled ? onPressed : null,
      leadingIcon: SizedBox(
        width: 18,
        child: icon == null
            ? null
            : Icon(icon, size: 16, color: enabled ? (active ? colors.projector : colors.dust) : foreground),
      ),
      trailingIcon: trailing == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: OmniaMetrics.space4),
              child: Text(trailing!, style: type.timecode.copyWith(fontSize: 11, color: colors.dust)),
            ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: OmniaMetrics.menuMinWidth - 80,
          maxWidth: OmniaMetrics.menuMaxWidth,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: type.body.copyWith(color: foreground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: type.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

/// Une ligne qui ouvre un sous-menu.
class OmniaSubmenu extends StatelessWidget {
  const OmniaSubmenu({
    super.key,
    required this.label,
    required this.children,
    this.icon,
    this.trailing,
  });

  final String label;
  final List<Widget> children;
  final IconData? icon;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return SubmenuButton(
      leadingIcon: SizedBox(
        width: 18,
        child: icon == null ? null : Icon(icon, size: 16, color: colors.dust),
      ),
      trailingIcon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null)
            Text(trailing!, style: type.timecode.copyWith(fontSize: 11, color: colors.dust)),
          const SizedBox(width: OmniaMetrics.space2),
          Icon(Icons.chevron_right_rounded, size: 16, color: colors.dust),
        ],
      ),
      menuChildren: children,
      child: Text(label, style: type.body),
    );
  }
}

/// Séparateur fin.
class OmniaMenuDivider extends StatelessWidget {
  const OmniaMenuDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OmniaMetrics.space1),
      child: Divider(height: 1, thickness: 1, color: context.colors.seam),
    );
  }
}

/// Intitulé de section, non cliquable.
class OmniaMenuHeader extends StatelessWidget {
  const OmniaMenuHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OmniaMetrics.space3,
        OmniaMetrics.space2,
        OmniaMetrics.space3,
        OmniaMetrics.space1,
      ),
      child: Text(
        label.toUpperCase(),
        style: type.caption.copyWith(
          color: colors.dust,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
