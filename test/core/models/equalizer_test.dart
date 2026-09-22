import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/models/equalizer.dart';

void main() {
  test('dix bandes, dix gains dans chaque préréglage', () {
    expect(Equalizer.bands, hasLength(10));
    for (final entry in Equalizer.presets.entries) {
      expect(entry.value, hasLength(10), reason: entry.key);
      for (final g in entry.value) {
        expect(g, inInclusiveRange(Equalizer.minGain, Equalizer.maxGain), reason: entry.key);
      }
    }
  });

  test('« normal » est plat et ne produit aucun filtre', () {
    expect(Equalizer.presets['normal'], Equalizer.flat);
    expect(Equalizer.filterFor(Equalizer.flat), isEmpty);
  });

  test('le filtre mpv liste une bande par fréquence', () {
    final filter = Equalizer.filterFor(Equalizer.presets['bass']!);
    expect(filter, startsWith('lavfi=['));
    expect(filter, endsWith(']'));
    expect('equalizer='.allMatches(filter).length, 10);
    expect(filter, contains('equalizer=f=31:t=o:w=1:g=7.0'));
    expect(filter, contains('equalizer=f=16000:t=o:w=1:g=0.0'));
  });

  test('normalise borne et complète', () {
    final g = Equalizer.normalise([20, -20, 3]);
    expect(g, hasLength(10));
    expect(g[0], Equalizer.maxGain);
    expect(g[1], Equalizer.minGain);
    expect(g[2], 3);
    expect(g[9], 0);
  });

  test('presetFor reconnaît un préréglage exact, et rien d’autre', () {
    expect(Equalizer.presetFor(Equalizer.presets['rock']!), 'rock');
    expect(Equalizer.presetFor([5, 4, 3, 1, -1, -1, 1, 3, 4, 4.5]), isNull);
    expect(Equalizer.presetFor(Equalizer.flat), 'normal');
  });
}
