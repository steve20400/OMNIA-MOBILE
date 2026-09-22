import 'package:flutter/material.dart';

/// Palette d'OMNIA, exposée comme extension de thème.
///
/// Les noms viennent de DESIGN.md (salle de projection). Aucun widget ne doit
/// utiliser une couleur en dur : tout passe par `context.colors`.
@immutable
class OmniaColors extends ThemeExtension<OmniaColors> {
  const OmniaColors({
    required this.velvet,
    required this.curtain,
    required this.seam,
    required this.projector,
    required this.ember,
    required this.screen,
    required this.dust,
    required this.alert,
    required this.overlayScrim,
  });

  /// Fond principal.
  final Color velvet;

  /// Surfaces surélevées (panneau, barre de titre, overlays).
  final Color curtain;

  /// Bordures, séparateurs, pistes au repos.
  final Color seam;

  /// Accent unique : la lumière du projecteur.
  final Color projector;

  /// Accent pressé / secondaire.
  final Color ember;

  /// Texte principal.
  final Color screen;

  /// Texte secondaire, icônes inactives.
  final Color dust;

  /// Erreurs uniquement.
  final Color alert;

  /// Voile posé sur le contenu (dépôt de fichier, chargement).
  final Color overlayScrim;

  /// Surface flottante translucide (à combiner avec un flou d'arrière-plan).
  Color get overlay => curtain.withValues(alpha: 0.78);

  /// Survol : éclaircissement discret, sans changement de teinte.
  Color get hover => screen.withValues(alpha: 0.06);
  Color get pressed => screen.withValues(alpha: 0.10);

  /// Thème sombre — la salle dans le noir.
  static const dark = OmniaColors(
    velvet: Color(0xFF120F14),
    curtain: Color(0xFF1C1720),
    seam: Color(0xFF2E2734),
    projector: Color(0xFFF2B441),
    ember: Color(0xFFC9822B),
    screen: Color(0xFFF3EFE6),
    dust: Color(0xFF9C9199),
    alert: Color(0xFFE0573C),
    overlayScrim: Color(0xB3120F14),
  );

  /// Thème clair — secondaire.
  static const light = OmniaColors(
    velvet: Color(0xFFF6F1EA),
    curtain: Color(0xFFFFFDF9),
    seam: Color(0xFFE3DBD1),
    projector: Color(0xFFC98A17),
    ember: Color(0xFFA36B0C),
    screen: Color(0xFF1E181F),
    dust: Color(0xFF6E6469),
    alert: Color(0xFFC94B33),
    overlayScrim: Color(0xB3F6F1EA),
  );

  @override
  OmniaColors copyWith({
    Color? velvet,
    Color? curtain,
    Color? seam,
    Color? projector,
    Color? ember,
    Color? screen,
    Color? dust,
    Color? alert,
    Color? overlayScrim,
  }) {
    return OmniaColors(
      velvet: velvet ?? this.velvet,
      curtain: curtain ?? this.curtain,
      seam: seam ?? this.seam,
      projector: projector ?? this.projector,
      ember: ember ?? this.ember,
      screen: screen ?? this.screen,
      dust: dust ?? this.dust,
      alert: alert ?? this.alert,
      overlayScrim: overlayScrim ?? this.overlayScrim,
    );
  }

  @override
  OmniaColors lerp(ThemeExtension<OmniaColors>? other, double t) {
    if (other is! OmniaColors) return this;
    return OmniaColors(
      velvet: Color.lerp(velvet, other.velvet, t)!,
      curtain: Color.lerp(curtain, other.curtain, t)!,
      seam: Color.lerp(seam, other.seam, t)!,
      projector: Color.lerp(projector, other.projector, t)!,
      ember: Color.lerp(ember, other.ember, t)!,
      screen: Color.lerp(screen, other.screen, t)!,
      dust: Color.lerp(dust, other.dust, t)!,
      alert: Color.lerp(alert, other.alert, t)!,
      overlayScrim: Color.lerp(overlayScrim, other.overlayScrim, t)!,
    );
  }
}
