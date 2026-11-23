/// Une note posée sur une page de PDF.
///
/// C'est une annotation « Texte » au sens de la norme PDF — la bulle que
/// tous les lecteurs savent afficher : Acrobat, Firefox, l'aperçu du
/// système. Une note écrite par OMNIA se relit ailleurs, et inversement.
///
/// Les coordonnées sont celles de la page PDF, en points, origine en bas à
/// gauche : [top] est plus grand que [bottom].
class PdfNote {
  const PdfNote({
    required this.page,
    required this.index,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.text,
    this.author,
    this.highlight = false,
  });

  /// Page, à partir de 1.
  final int page;

  /// Rang de l'annotation parmi celles de sa page, dans le fichier : c'est
  /// par lui qu'on la retrouve pour la modifier ou l'effacer.
  final int index;

  final double left;
  final double top;
  final double right;
  final double bottom;

  /// Le texte de la note ; vide si son auteur n'en a pas mis.
  final String text;

  /// Son auteur, tel que le fichier le nomme.
  final String? author;

  /// Vrai pour un commentaire posé sur un passage surligné, plutôt qu'une
  /// bulle posée sur la page. Le rectangle est alors celui du passage.
  final bool highlight;

  @override
  bool operator ==(Object other) =>
      other is PdfNote &&
      other.page == page &&
      other.index == index &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.text == text &&
      other.author == author &&
      other.highlight == highlight;

  @override
  int get hashCode => Object.hash(page, index, left, top, right, bottom, text, author, highlight);

  @override
  String toString() => 'PdfNote(page $page #$index, « $text »)';
}

/// Une modification de notes à écrire dans le PDF.
sealed class PdfNoteChange {
  const PdfNoteChange();
}

/// Une note neuve, son coin haut gauche au point ([x], [y]) de la page.
final class PdfNoteAdded extends PdfNoteChange {
  const PdfNoteAdded({required this.page, required this.x, required this.y, required this.text});

  final int page;
  final double x;
  final double y;
  final String text;
}

/// Un passage surligné et commenté. [quads] donne, ligne par ligne, le
/// rectangle du texte : gauche, haut, droite, bas — quatre nombres par ligne,
/// en coordonnées de la page PDF.
final class PdfHighlightAdded extends PdfNoteChange {
  const PdfHighlightAdded({required this.page, required this.quads, required this.text});

  final int page;
  final List<double> quads;
  final String text;
}

/// Le texte d'une note change.
final class PdfNoteEdited extends PdfNoteChange {
  const PdfNoteEdited({required this.page, required this.index, required this.text});

  final int page;
  final int index;
  final String text;
}

/// Une note s'efface, avec sa fenêtre surgissante s'il en a une.
final class PdfNoteDeleted extends PdfNoteChange {
  const PdfNoteDeleted({required this.page, required this.index});

  final int page;
  final int index;
}
