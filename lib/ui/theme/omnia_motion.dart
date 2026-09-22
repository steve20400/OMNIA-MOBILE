import 'package:flutter/animation.dart';

/// Durées et courbes d'animation (DESIGN.md §6).
///
/// Le motion répond toujours à une action de l'utilisateur ; aucune boucle
/// décorative.
abstract final class OmniaMotion {
  /// Survol : couleur, épaisseur.
  static const hover = Duration(milliseconds: 150);
  static const hoverCurve = Curves.easeOut;

  /// Apparition / disparition des contrôles et de l'OSD.
  static const reveal = Duration(milliseconds: 200);
  static const revealCurve = Curves.easeOutCubic;
  static const concealCurve = Curves.easeIn;

  /// Rétraction du panneau latéral.
  static const panel = Duration(milliseconds: 240);
  static const panelCurve = Curves.easeInOutCubic;

  /// Transition entre types de média.
  static const stage = Duration(milliseconds: 250);
  static const stageCurve = Curves.easeOutCubic;

  /// Délai d'inactivité avant masquage des contrôles, dans tous les modes.
  static const idleHide = Duration(seconds: 2);

  /// Délai de masquage quand le pointeur quitte la zone du média.
  static const chromeLeaveHide = Duration(milliseconds: 600);

  /// Durée d'affichage d'un message OSD après la dernière action.
  static const osdLinger = Duration(milliseconds: 1100);
}
