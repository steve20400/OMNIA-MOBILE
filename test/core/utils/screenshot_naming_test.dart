import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/utils/screenshot_naming.dart';

void main() {
  final when = DateTime(2026, 9, 7, 21, 4, 5);

  test('nom du média, horodatage lisible, extension', () {
    expect(screenshotFileName('/films/ep1.mkv', when), 'ep1 2026-09-07 21-04-05.png');
  });

  test('les caractères interdits par Windows sont remplacés', () {
    expect(screenshotFileName('/x/a:b?c.mkv', when), 'a_b_c 2026-09-07 21-04-05.png');
  });

  test('un nom vide devient « capture »', () {
    expect(screenshotFileName('', when), 'capture 2026-09-07 21-04-05.png');
    expect(screenshotFileName('/x/???.mkv', when), '___ 2026-09-07 21-04-05.png');
  });

  group('motif', () {
    test('jetons date, heure et position', () {
      expect(
        screenshotFileName(
          '/films/ep1.mkv',
          when,
          pattern: '{name} @ {position}',
          position: const Duration(hours: 1, minutes: 2, seconds: 3),
        ),
        'ep1 @ 01-02-03.png',
      );
      expect(screenshotFileName('/films/ep1.mkv', when, pattern: '{date}_{name}'),
          '2026-09-07_ep1.png');
    });

    test('un motif sans jeton reste un nom valide', () {
      expect(screenshotFileName('/films/ep1.mkv', when, pattern: 'omnia'), 'omnia.png');
    });

    test('un motif qui ne produit rien retombe sur « capture » horodatée', () {
      expect(screenshotFileName('/films/ep1.mkv', when, pattern: '...'),
          'capture 2026-09-07 21-04-05.png');
    });

    test('les caractères interdits du motif sont remplacés aussi', () {
      expect(screenshotFileName('/films/ep1.mkv', when, pattern: '{name}: {time}'),
          'ep1_ 21-04-05.png');
    });
  });

  test('sanitiseFileName retire points et espaces finaux', () {
    expect(sanitiseFileName('fin. '), 'fin');
    expect(sanitiseFileName('  ok  '), 'ok');
  });
}
