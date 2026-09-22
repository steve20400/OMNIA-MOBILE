import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Dimensions, rayons et espacements (aucune valeur en dur dans les widgets).
abstract final class OmniaMetrics {
  // Espacements.
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;
  static const double space6 = 32;
  static const double space8 = 48;

  // Rayons.
  static const double radiusSmall = 6;
  static const double radiusMedium = 10;
  static const double radiusLarge = 14;
  static const BorderRadius overlayRadius = BorderRadius.all(Radius.circular(radiusLarge));
  static const BorderRadius controlRadius = BorderRadius.all(Radius.circular(radiusMedium));

  // Flou et ombre des surfaces flottantes.
  static const double overlayBlur = 18;
  static const double overlayShadowBlur = 24;
  static const double overlayShadowAlpha = 0.35;

  // Barre de titre et contrôles.
  static const double titleBarHeight = 40;
  static const double windowButtonWidth = 46;
  static const double controlBarMargin = 16;
  static const double controlBarPadding = 12;
  static const double controlBarMaxWidth = 1120;

  /// Hauteur de la barre de contrôles, marge intérieure comprise : le faisceau
  /// et la rangée de commandes. Ce que les surfaces posées sur la scène
  /// doivent laisser libre en bas pour ne pas la recouvrir.
  static const double controlBarHeight = 96;

  /// Hauteur de scène en dessous de laquelle la barre de contrôles occupe déjà
  /// presque tout : ce qui se pose au-dessus d'elle doit se serrer.
  static const double shortStageHeight = 320;

  /// Largeur minimale choisie à la souris : lecture, temps et menu « ⋯ ».
  static const double controlBarMinWidth = 300;

  /// Zone de saisie des poignées de redimensionnement, sur les bords de la
  /// barre (dans sa marge intérieure, hors des commandes).
  static const double controlBarGripWidth = 12;
  static const double iconButtonSize = 34;
  static const double iconSize = 20;
  static const double iconSizeLarge = 26;
  static const double playButtonSize = 44;

  // Faisceau (barre de progression).
  static const double beamHitHeight = 28;
  /// Hauteur de la bande qui réagit au clic, centrée sur le trait : assez
  /// pour viser sans peine, trop peu pour qu'un clic à côté déplace la lecture.
  static const double beamGrabHeight = 16;
  static const double beamRestThickness = 2;
  static const double beamHoverThickness = 6;
  static const double beamLampRadiusRest = 3;
  static const double beamLampRadiusHover = 6;
  static const double beamGlowSigmaRest = 6;
  static const double beamGlowSigmaHover = 9;
  static const double beamTooltipHeight = 24;

  // Curseur de volume.
  static const double volumeSliderWidth = 88;
  static const double volumeSliderThickness = 3;
  static const double volumeThumbRadius = 5;

  // Panneau latéral (Phase 2).
  static const double panelDefaultWidth = 300;
  static const double panelMinWidth = 220;
  static const double panelMaxWidth = 520;

  /// Largeur de scène à préserver : ancrer le panneau en laisserait moins, il
  /// s'ouvre alors en tiroir par-dessus la scène (le média garde sa place).
  static const double panelDrawerBreakpoint = 420;

  // OSD (Phase 3).
  static const double osdLevelWidth = 96;

  // Menus (contextuel, récents).
  static const double menuMinWidth = 220;
  static const double menuMaxWidth = 380;
  static const double menuItemHeight = 34;

  // Écran Paramètres (Phase 6).
  static const double settingsMaxWidth = 940;
  static const double settingsMaxHeight = 680;
  static const double settingsNavWidth = 208;
  static const double settingsRowBreakpoint = 520;
  static const double settingsSliderWidth = 160;
  static const double settingsValueWidth = 64;
  static const double switchWidth = 38;
  static const double switchHeight = 22;
  static const double keyCapMinWidth = 28;

  /// Invite de reprise : au-dessus de la barre de contrôles.
  static const double resumePromptBottom = controlBarMargin + controlBarHeight + space4;

  /// Hauteur gardée libre au-dessus de l'invite de reprise, pour qu'elle
  /// tienne entière.
  static const double resumePromptClearance = 200;

  /// Place à réserver en bas d'une scène de [stageHeight] pour ne pas
  /// recouvrir la barre de contrôles. Sur une scène courte, la barre prend
  /// presque toute la hauteur : lui laisser sa place entière ne laisserait
  /// rien au-dessus, on se contente donc d'une part.
  static double controlBarClearance(double stageHeight) {
    const full = controlBarMargin + controlBarHeight;
    if (stageHeight >= shortStageHeight) return full;
    return math.min(full, math.max(controlBarMargin, stageHeight * 0.35));
  }

  /// Hauteur à laquelle poser l'invite de reprise sur une scène de
  /// [stageHeight] : au-dessus de la barre dès que la scène est haute, de plus
  /// en plus bas quand elle se réduit — quitte à couvrir la barre, ce qui vaut
  /// mieux que de sortir de la scène par le haut.
  static double resumePromptBottomFor(double stageHeight) => math.min(
        resumePromptBottom,
        math.max(space2, stageHeight - resumePromptClearance),
      );

  // Fenêtre : voir `WindowSizes` (core), source unique des tailles, partagée
  // avec le mini-lecteur.
}
