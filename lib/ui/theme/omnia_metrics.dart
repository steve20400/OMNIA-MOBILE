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

  // Tiroir de liste de lecture (mobile, sous la scène).

  /// Part de la hauteur disponible au premier affichage : la moitié de l'écran.
  ///
  /// C'est la demande de l'utilisateur, et elle doit être tenue **sans qu'il
  /// ait rien à faire**. Le tiroir valait 240 pixels en dur, soit à peu près un
  /// tiers d'un téléphone courant : ouvrir la liste sur un tiers d'écran et
  /// compter sur la découverte de la poignée, c'était livrer la mise à jour
  /// avec le défaut dont il se plaignait.
  static const double playlistDrawerDefaultFraction = 0.5;

  /// Plancher de ce que l'utilisateur peut choisir au doigt.
  static const double playlistDrawerMinFraction = 0.2;

  /// Plafond : au-delà, la scène disparaîtrait tout à fait. Il dépasse
  /// franchement la moitié, pour qu'une saison entière se parcoure sans
  /// refermer le tiroir.
  static const double playlistDrawerMaxFraction = 0.8;

  /// Hauteur de la poignée de glissement, barrette comprise. Assez haute pour
  /// qu'un pouce la saisisse sans viser.
  static const double playlistDrawerGripHeight = 22;

  /// En dessous, la poignée, l'en-tête et la rangée de filtres mangent tout :
  /// le tiroir n'afficherait plus un seul fichier. La rangée de filtres
  /// s'efface alors pour rendre sa place à la liste.
  static const double playlistDrawerUsableHeight = 148;

  /// Ce que la scène garde toujours, quelle que soit la part demandée : au
  /// moins de quoi loger sa barre de contrôles.
  ///
  /// La moitié d'un écran en portrait est confortable ; la moitié d'une fenêtre
  /// de mini-lecteur ou d'un Picture-in-Picture ne laisse rien. Sans cette
  /// réserve, le tiroir ouvert dans une fenêtre de 170 pixels en prenait 136 et
  /// ne laissait au média ni image ni bouton de lecture.
  static const double playlistDrawerStageReserve = controlBarHeight;

  /// Hauteur maximale du tiroir sur une scène de [available] pixels.
  ///
  /// C'est la réserve de la scène qui borne les fenêtres basses, et la part de
  /// 80 % qui borne les écrans ordinaires. Le résultat ne descend jamais sous
  /// la part minimale : mieux vaut un tiroir serré qu'un tiroir de hauteur
  /// nulle, dont la disposition déborderait.
  static double playlistDrawerHighest(double available) {
    if (available <= 0) return 0;
    return math.max(
      available * playlistDrawerMinFraction,
      math.min(
        available * playlistDrawerMaxFraction,
        available - playlistDrawerStageReserve,
      ),
    );
  }

  /// Hauteur minimale. Le plancher exprimé en pixels ne peut pas dépasser le
  /// plafond : dans une fenêtre de mini-lecteur, c'est le plafond qui gagne.
  static double playlistDrawerLowest(double available) => math.min(
        playlistDrawerHighest(available),
        math.max(
          playlistDrawerUsableHeight,
          available * playlistDrawerMinFraction,
        ),
      );

  /// Hauteur du tiroir pour la part [fraction] choisie par l'utilisateur,
  /// bornée des deux côtés : la scène garde de quoi montrer le média, et le
  /// tiroir de quoi se manipuler.
  static double playlistDrawerHeight(double available, double fraction) =>
      (available * fraction)
          .clamp(playlistDrawerLowest(available), playlistDrawerHighest(available));

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
