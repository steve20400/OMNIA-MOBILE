import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/utils/natural_sort.dart';

void main() {
  group('compareNatural', () {
    test('les nombres se comparent par valeur, pas caractère par caractère', () {
      expect(compareNatural('ep2', 'ep10'), lessThan(0));
      expect(compareNatural('ep10', 'ep2'), greaterThan(0));
      expect(compareNatural('ep9', 'ep10'), lessThan(0));
      expect(compareNatural('ep100', 'ep99'), greaterThan(0));
    });

    test('les zéros de tête ne changent pas la valeur numérique', () {
      expect(compareNatural('ep02', 'ep10'), lessThan(0));
      expect(compareNatural('ep007', 'ep10'), lessThan(0));
      expect(compareNatural('ep010', 'ep9'), greaterThan(0));
    });

    test('deux écritures du même nombre restent départagées, de façon stable', () {
      // `ep02` et `ep2` sont deux fichiers distincts : les déclarer égaux
      // rendrait le tri ambigu. La valeur exacte importe peu, la stabilité oui.
      expect(compareNatural('ep02', 'ep2'), isNot(0));
      expect(
        compareNatural('ep02', 'ep2').sign,
        -compareNatural('ep2', 'ep02').sign,
      );
    });

    test('insensible à la casse', () {
      expect(compareNatural('Episode', 'episode'), isNot(0));
      expect(compareNatural('EPISODE 2', 'episode 10'), lessThan(0));
      expect(compareNatural('avatar.mkv', 'Batman.mkv'), lessThan(0));
    });

    test('tri d’une saison complète', () {
      final files = [
        'Show.S01E10.mkv',
        'Show.S01E02.mkv',
        'Show.S01E01.mkv',
        'Show.S02E01.mkv',
        'Show.S01E20.mkv',
        'Show.S01E03.mkv',
      ]..sort(compareNatural);

      expect(files, [
        'Show.S01E01.mkv',
        'Show.S01E02.mkv',
        'Show.S01E03.mkv',
        'Show.S01E10.mkv',
        'Show.S01E20.mkv',
        'Show.S02E01.mkv',
      ]);
    });

    test('numérotation sans zéros de tête', () {
      final files = ['10 - fin.mp3', '2 - milieu.mp3', '1 - début.mp3']
        ..sort(compareNatural);
      expect(files, ['1 - début.mp3', '2 - milieu.mp3', '10 - fin.mp3']);
    });

    test('le préfixe le plus court vient en premier', () {
      expect(compareNatural('film', 'film2'), lessThan(0));
      expect(compareNatural('film.mkv', 'film'), greaterThan(0));
    });

    test('chaînes égales', () {
      expect(compareNatural('a.mkv', 'a.mkv'), 0);
      expect(compareNatural('', ''), 0);
    });

    test('chaîne vide avant tout le reste', () {
      expect(compareNatural('', 'a'), lessThan(0));
    });

    test('le tri est total et déterministe (antisymétrie)', () {
      final samples = [
        'a1', 'a01', 'a2', 'A2', 'b', 'B', '1', '10', '2', 'x 3 y', 'x 20 y',
      ];
      for (final a in samples) {
        for (final b in samples) {
          final ab = compareNatural(a, b);
          final ba = compareNatural(b, a);
          expect(ab.sign, -ba.sign, reason: '"$a" vs "$b"');
        }
      }
    });

    test('plusieurs groupes de chiffres dans le même nom', () {
      final files = ['cam2_part10.mp4', 'cam2_part2.mp4', 'cam10_part1.mp4']
        ..sort(compareNatural);
      expect(files, ['cam2_part2.mp4', 'cam2_part10.mp4', 'cam10_part1.mp4']);
    });
  });
}
