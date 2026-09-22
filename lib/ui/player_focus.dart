import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Le nœud de focus du lecteur, celui qui reçoit les raccourcis clavier.
///
/// Quand un champ perd le focus (`Échap` dans une recherche) ou qu'un panneau
/// se ferme (aide, paramètres, recherche), Flutter rend le focus à la portée
/// englobante, pas au lecteur : les raccourcis resteraient muets jusqu'au
/// prochain clic. [restore] le rend explicitement au lecteur.
class PlayerFocus {
  FocusNode? _node;

  void attach(FocusNode node) => _node = node;

  void detach(FocusNode node) {
    if (identical(_node, node)) _node = null;
  }

  void restore() {
    final node = _node;
    if (node == null) return;
    node.requestFocus();
    // Le panneau qui se ferme est retiré de l'arbre dans la même trame, et
    // emporte parfois le focus avec lui : on réaffirme à la trame suivante.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(_node, node) && node.context != null) node.requestFocus();
    });
  }
}

final playerFocusProvider = Provider<PlayerFocus>((_) => PlayerFocus());
