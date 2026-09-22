/// Répartition des commandes de la barre de contrôles selon la place.
///
/// Fonction pure, testée seule : la barre lui donne ses commandes (largeur,
/// priorité) et la largeur disponible ; elle rend celles qui restent visibles
/// et celles qui passent dans le menu « ⋯ ». Le menu n'existe que s'il reçoit
/// au moins une commande.
library;

/// Une commande de la barre, vue par la répartition.
class ControlSlot {
  const ControlSlot({required this.id, required this.width, required this.priority});

  final String id;

  /// Largeur occupée, marges comprises.
  final double width;

  /// 0 : toujours visible. Plus le nombre est grand, plus la commande cède
  /// tôt sa place au menu.
  final int priority;
}

/// Résultat : identifiants visibles et identifiants passés au menu, chacun
/// dans l'ordre d'origine de la barre.
class ControlFit {
  const ControlFit(this.shown, this.overflow);

  final List<String> shown;
  final List<String> overflow;

  bool get hasOverflow => overflow.isNotEmpty;
}

/// Place les commandes [slots] dans [available] pixels.
///
/// Tout tient : pas de menu. Sinon, le bouton « ⋯ » ([overflowWidth]) prend sa
/// place, et les commandes cèdent la leur une à une, par priorité décroissante
/// puis de droite à gauche, jusqu'à ce que le reste tienne. Les commandes de
/// priorité 0 ne cèdent jamais.
ControlFit fitControls(
  List<ControlSlot> slots,
  double available, {
  required double overflowWidth,
}) {
  final total = slots.fold<double>(0, (sum, s) => sum + s.width);
  if (total <= available) {
    return ControlFit([for (final s in slots) s.id], const []);
  }

  final budget = available - overflowWidth;
  final order = [for (var i = 0; i < slots.length; i++) i]
    ..sort((a, b) {
      final byPriority = slots[b].priority.compareTo(slots[a].priority);
      return byPriority != 0 ? byPriority : b.compareTo(a);
    });

  final hidden = <int>{};
  var width = total;
  for (final i in order) {
    if (width <= budget) break;
    if (slots[i].priority == 0) continue;
    hidden.add(i);
    width -= slots[i].width;
  }

  return ControlFit(
    [for (var i = 0; i < slots.length; i++) if (!hidden.contains(i)) slots[i].id],
    [for (var i = 0; i < slots.length; i++) if (hidden.contains(i)) slots[i].id],
  );
}
