import 'package:flutter/foundation.dart';

/// Une occurrence trouvée dans un document.
class SearchMatch {
  const SearchMatch({required this.page, required this.start, required this.end});

  /// Page (1-based) pour un PDF ; 0 pour un texte.
  final int page;

  /// Bornes dans le texte (offsets de caractères), pour le surlignage.
  final int start;
  final int end;
}

/// Résultat courant d'une recherche.
class SearchState {
  const SearchState({
    this.query = '',
    this.matches = const [],
    this.current = -1,
    this.searching = false,
  });

  final String query;
  final List<SearchMatch> matches;

  /// Index de l'occurrence courante dans [matches], -1 si aucune.
  final int current;
  final bool searching;

  int get count => matches.length;
  SearchMatch? get currentMatch => current >= 0 && current < matches.length ? matches[current] : null;

  SearchState copyWith({
    String? query,
    List<SearchMatch>? matches,
    int? current,
    bool? searching,
  }) =>
      SearchState(
        query: query ?? this.query,
        matches: matches ?? this.matches,
        current: current ?? this.current,
        searching: searching ?? this.searching,
      );
}

/// Recherche plein texte dans le document courant.
///
/// Une implémentation par type de document (texte brut, PDF) ; la barre de
/// recherche ne connaît que cette interface.
abstract class DocumentSearch extends ChangeNotifier {
  SearchState get state;

  /// Lance (ou relance) une recherche. Chaîne vide : efface.
  Future<void> search(String query);

  /// Passe à l'occurrence suivante / précédente, en bouclant.
  void next();
  void previous();

  void clear();
}

/// Recherche dans un texte en mémoire : insensible à la casse, sans regex.
class PlainTextSearch extends DocumentSearch {
  PlainTextSearch(this.text);

  final String text;
  SearchState _state = const SearchState();

  @override
  SearchState get state => _state;

  @override
  Future<void> search(String query) async {
    final needle = query.trim();
    if (needle.isEmpty) {
      clear();
      return;
    }
    final matches = findAll(text, needle);
    _state = SearchState(
      query: needle,
      matches: matches,
      current: matches.isEmpty ? -1 : 0,
    );
    notifyListeners();
  }

  /// Toutes les occurrences de [needle] dans [haystack], sans chevauchement.
  static List<SearchMatch> findAll(String haystack, String needle) {
    if (needle.isEmpty) return const [];
    final lowerHay = haystack.toLowerCase();
    final lowerNeedle = needle.toLowerCase();
    final result = <SearchMatch>[];
    var from = 0;
    while (true) {
      final index = lowerHay.indexOf(lowerNeedle, from);
      if (index < 0) break;
      result.add(SearchMatch(page: 0, start: index, end: index + lowerNeedle.length));
      from = index + lowerNeedle.length;
    }
    return result;
  }

  @override
  void next() => _step(1);

  @override
  void previous() => _step(-1);

  void _step(int delta) {
    if (_state.matches.isEmpty) return;
    final count = _state.matches.length;
    _state = _state.copyWith(current: (_state.current + delta + count) % count);
    notifyListeners();
  }

  @override
  void clear() {
    _state = const SearchState();
    notifyListeners();
  }
}
