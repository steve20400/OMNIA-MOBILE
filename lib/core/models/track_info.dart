/// Une piste (sous-titres ou audio) d'un fichier, telle que l'interface la
/// présente et que la télécommande la recevra.
class TrackInfo {
  const TrackInfo({
    required this.id,
    this.title,
    this.language,
    this.external = false,
  });

  /// Identifiant mpv (`1`, `2`… ou un chemin pour une piste externe).
  final String id;
  final String? title;

  /// Code de langue (`fre`, `eng`…), quand le conteneur le fournit.
  final String? language;

  /// Piste chargée depuis un fichier voisin, pas incluse dans le conteneur.
  final bool external;

  /// Libellé lisible : titre, sinon langue, sinon l'identifiant.
  String get label {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    final l = language?.trim();
    if (l != null && l.isNotEmpty) return l;
    return id;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        if (title != null) 'title': title,
        if (language != null) 'language': language,
        'external': external,
      };

  factory TrackInfo.fromJson(Map<String, Object?> json) => TrackInfo(
        id: json['id']! as String,
        title: json['title'] as String?,
        language: json['language'] as String?,
        external: json['external'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is TrackInfo &&
      other.id == id &&
      other.title == title &&
      other.language == language &&
      other.external == external;

  @override
  int get hashCode => Object.hash(id, title, language, external);

  @override
  String toString() => 'TrackInfo($id, $label)';
}
