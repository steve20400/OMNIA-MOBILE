import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/utils/subtitle_sidecars.dart';
import 'package:path/path.dart' as p;

void main() {
  const media = '/films/Le.Film.2024.mkv';

  List<String> ids(List<String> names) =>
      findSubtitleSidecars(media, candidates: names).map((t) => p.basename(t.id)).toList();

  test('même nom de base, extensions reconnues', () {
    expect(
      ids(['Le.Film.2024.srt', 'Le.Film.2024.ass', 'Le.Film.2024.vtt', 'Le.Film.2024.nfo', 'autre.srt']),
      ['Le.Film.2024.ass', 'Le.Film.2024.srt', 'Le.Film.2024.vtt'],
    );
  });

  test('insensible à la casse', () {
    expect(ids(['LE.FILM.2024.SRT']), ['LE.FILM.2024.SRT']);
  });

  test('suffixe de langue reconnu', () {
    final tracks = findSubtitleSidecars(media, candidates: ['Le.Film.2024.fr.srt', 'Le.Film.2024.eng.srt']);
    expect(tracks.map((t) => t.language), ['eng', 'fr']);
    expect(tracks.every((t) => t.external), isTrue);
  });

  test('sans suffixe d’abord, puis par nom', () {
    expect(
      ids(['Le.Film.2024.fr.srt', 'Le.Film.2024.srt', 'Le.Film.2024.en.srt']),
      ['Le.Film.2024.srt', 'Le.Film.2024.en.srt', 'Le.Film.2024.fr.srt'],
    );
  });

  test('un fichier qui commence pareil mais n’est pas une langue est ignoré', () {
    expect(ids(['Le.Film.2024.commentaires-realisateur.srt']), isEmpty);
    expect(ids(['Le.Film.2024.2.srt']), ['Le.Film.2024.2.srt']); // suffixe court : accepté
  });

  test('dossier illisible → liste vide', () {
    expect(findSubtitleSidecars('/dossier/inexistant/x.mkv'), isEmpty);
  });
}
