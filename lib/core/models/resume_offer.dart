/// Proposition de reprise, publiée quand la politique de reprise est
/// « demander » : l'interface l'affiche, l'utilisateur accepte ou refuse.
///
/// Un seul des trois champs est renseigné selon le type de fichier : position
/// pour un média, page pour un PDF, défilement pour un texte.
class ResumeOffer {
  const ResumeOffer({this.position, this.page, this.scroll});

  final Duration? position;

  /// Page (1-based).
  final int? page;

  /// Défilement 0–1.
  final double? scroll;

  bool get isEmpty => position == null && page == null && scroll == null;

  Map<String, Object?> toJson() => {
        if (position != null) 'positionMs': position!.inMilliseconds,
        if (page != null) 'page': page,
        if (scroll != null) 'scroll': scroll,
      };

  /// `null` si la carte ne décrit aucune reprise.
  static ResumeOffer? fromJson(Object? json) {
    if (json is! Map) return null;
    final offer = ResumeOffer(
      position: json['positionMs'] is num
          ? Duration(milliseconds: (json['positionMs']! as num).toInt())
          : null,
      page: (json['page'] as num?)?.toInt(),
      scroll: (json['scroll'] as num?)?.toDouble(),
    );
    return offer.isEmpty ? null : offer;
  }

  @override
  bool operator ==(Object other) =>
      other is ResumeOffer &&
      other.position == position &&
      other.page == page &&
      other.scroll == scroll;

  @override
  int get hashCode => Object.hash(position, page, scroll);

  @override
  String toString() => 'ResumeOffer(${toJson()})';
}
