/// Ce qu'OMNIA retient d'un fichier déjà ouvert.
///
/// Sert à trois choses : reprendre la lecture où on l'a laissée, afficher la
/// pastille « déjà lu » dans le panneau de dossier, et alimenter la liste des
/// fichiers récents.
class HistoryEntry {
  const HistoryEntry({
    required this.path,
    required this.position,
    required this.duration,
    required this.lastOpened,
    this.completed = false,
    this.pageCount = 0,
    this.page = 0,
    this.scrollFraction = 0,
    this.listed = true,
  });

  /// Sous ce seuil, la position n'est pas mémorisée : on vient à peine de
  /// commencer, reprendre n'apporterait rien.
  static const Duration minimumResumePosition = Duration(seconds: 30);

  /// Au-delà de cette fraction de la durée, le fichier est considéré comme vu
  /// jusqu'au bout : on repart du début à la prochaine ouverture.
  static const double completionThreshold = 0.95;

  final String path;

  /// Position atteinte. Pour un document, la page courante encodée en secondes.
  final Duration position;

  /// Durée totale connue, ou [Duration.zero].
  final Duration duration;

  final DateTime lastOpened;

  /// Le fichier a été vu en entier (ou au-delà du seuil de complétion).
  final bool completed;

  /// Nombre de pages, pour les documents.
  final int pageCount;

  /// Dernière page lue (1-based), 0 si inconnue. PDF.
  final int page;

  /// Dernière position de défilement, 0–1. Texte.
  final double scrollFraction;

  /// Figure dans la liste des récents. « Effacer les récents » retire les
  /// fichiers de la liste sans oublier leurs positions.
  final bool listed;

  /// Page à rouvrir, `null` si l'on repart du début : première page, ou
  /// document déjà lu jusqu'à la dernière page.
  int? get resumePage {
    if (page <= 1) return null;
    if (pageCount > 0 && page >= pageCount) return null;
    return page;
  }

  /// Position de défilement à rouvrir, `null` si négligeable ou à la fin.
  double? get resumeScroll {
    if (scrollFraction < 0.02 || scrollFraction > 0.98) return null;
    return scrollFraction;
  }

  /// Position à proposer à la réouverture, `null` s'il faut repartir du début.
  Duration? get resumePosition {
    if (completed) return null;
    if (position < minimumResumePosition) return null;
    if (duration > Duration.zero &&
        position.inMilliseconds / duration.inMilliseconds >= completionThreshold) {
      return null;
    }
    return position;
  }

  /// Vrai si la position mérite d'être conservée sur disque.
  static bool isWorthSaving(Duration position, Duration duration) {
    if (position < minimumResumePosition) return false;
    if (duration > Duration.zero &&
        position.inMilliseconds / duration.inMilliseconds >= completionThreshold) {
      return false;
    }
    return true;
  }

  HistoryEntry copyWith({
    Duration? position,
    Duration? duration,
    DateTime? lastOpened,
    bool? completed,
    int? pageCount,
    int? page,
    double? scrollFraction,
    bool? listed,
  }) {
    return HistoryEntry(
      path: path,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      lastOpened: lastOpened ?? this.lastOpened,
      completed: completed ?? this.completed,
      pageCount: pageCount ?? this.pageCount,
      page: page ?? this.page,
      scrollFraction: scrollFraction ?? this.scrollFraction,
      listed: listed ?? this.listed,
    );
  }

  /// La même entrée, sans aucune position mémorisée (« effacer les positions »).
  /// La durée et le nombre de pages restent : ce sont des faits sur le
  /// fichier, pas sur la lecture.
  HistoryEntry withoutProgress() => HistoryEntry(
        path: path,
        position: Duration.zero,
        duration: duration,
        lastOpened: lastOpened,
        pageCount: pageCount,
        listed: listed,
      );

  Map<String, Object?> toJson() => {
        'path': path,
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
        'lastOpened': lastOpened.toIso8601String(),
        'completed': completed,
        'pageCount': pageCount,
        'page': page,
        'scrollFraction': scrollFraction,
        'listed': listed,
      };

  factory HistoryEntry.fromJson(Map<String, Object?> json) => HistoryEntry(
        path: json['path']! as String,
        position: Duration(milliseconds: (json['positionMs'] as num?)?.toInt() ?? 0),
        duration: Duration(milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0),
        lastOpened:
            DateTime.tryParse(json['lastOpened'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
        completed: json['completed'] as bool? ?? false,
        pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
        page: (json['page'] as num?)?.toInt() ?? 0,
        scrollFraction:
            ((json['scrollFraction'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
        listed: json['listed'] as bool? ?? true,
      );

  @override
  String toString() => 'HistoryEntry($path, $position/$duration)';
}
