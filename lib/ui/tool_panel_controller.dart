import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Panneau d'outils flottant ouvert au-dessus de la barre de contrôles.
enum ToolPanel { none, image, equalizer }

final toolPanelProvider =
    NotifierProvider<ToolPanelController, ToolPanel>(ToolPanelController.new);

class ToolPanelController extends Notifier<ToolPanel> {
  @override
  ToolPanel build() => ToolPanel.none;

  void toggle(ToolPanel panel) => state = state == panel ? ToolPanel.none : panel;
  void close() => state = ToolPanel.none;
}
