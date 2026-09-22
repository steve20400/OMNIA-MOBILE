/// Une entrée du sommaire, aplatie avec sa profondeur pour l'affichage.
class OutlineItem {
  const OutlineItem({required this.title, required this.page, required this.depth});

  final String title;

  /// Page cible (1-based), `null` si l'entrée ne pointe nulle part.
  final int? page;

  /// Niveau d'imbrication, 0 pour la racine.
  final int depth;
}

/// Aplatit un arbre de sommaire (n'importe quelle structure d'arbre) en liste
/// ordonnée, en parcourant en profondeur d'abord.
///
/// Générique sur le type de nœud pour rester indépendant de pdfrx et testable.
List<OutlineItem> flattenOutline<N>(
  Iterable<N> roots, {
  required String Function(N) title,
  required int? Function(N) page,
  required Iterable<N> Function(N) children,
  int maxDepth = 8,
}) {
  final result = <OutlineItem>[];

  void visit(N node, int depth) {
    result.add(OutlineItem(title: title(node).trim(), page: page(node), depth: depth));
    if (depth >= maxDepth) return;
    for (final child in children(node)) {
      visit(child, depth + 1);
    }
  }

  for (final root in roots) {
    visit(root, 0);
  }
  return result;
}
