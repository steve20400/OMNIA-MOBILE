import 'package:flutter/material.dart';

import '../theme/omnia_theme.dart';

/// Une touche affichée comme sur un clavier : capsule bordée, texte en mono.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key, this.highlighted = false, this.muted = false});

  final String label;

  /// Mise en avant (raccourci en cours de saisie, personnalisé).
  final bool highlighted;

  /// Estompé (aucun raccourci).
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Container(
      constraints: const BoxConstraints(minWidth: OmniaMetrics.keyCapMinWidth),
      padding: const EdgeInsets.symmetric(horizontal: OmniaMetrics.space2, vertical: 3),
      decoration: BoxDecoration(
        color: colors.velvet,
        borderRadius: const BorderRadius.all(Radius.circular(OmniaMetrics.radiusSmall)),
        border: Border.all(color: highlighted ? colors.projector : colors.seam),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: type.timecode.copyWith(
          fontSize: 12,
          color: muted ? colors.dust : (highlighted ? colors.projector : colors.screen),
        ),
      ),
    );
  }
}
