import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/utils/time_format.dart';

void main() {
  group('formatTimecode', () {
    test('minutes:secondes sous une heure', () {
      expect(formatTimecode(Duration.zero), '00:00');
      expect(formatTimecode(const Duration(seconds: 5)), '00:05');
      expect(formatTimecode(const Duration(minutes: 4, seconds: 12)), '04:12');
      expect(formatTimecode(const Duration(minutes: 59, seconds: 59)), '59:59');
    });

    test('heures au-delà d’une heure', () {
      expect(formatTimecode(const Duration(hours: 1)), '1:00:00');
      expect(formatTimecode(const Duration(hours: 2, minutes: 3, seconds: 4)), '2:03:04');
    });

    test('la référence aligne l’écoulé sur la durée', () {
      expect(
        formatTimecode(const Duration(minutes: 4, seconds: 12), reference: const Duration(hours: 2)),
        '0:04:12',
      );
    });

    test('les durées négatives sont ramenées à zéro', () {
      expect(formatTimecode(const Duration(seconds: -3)), '00:00');
    });

    test('les millisecondes sont tronquées, pas arrondies', () {
      expect(formatTimecode(const Duration(milliseconds: 4999)), '00:04');
    });
  });

  group('formatSpeed', () {
    test('entiers sans décimale', () {
      expect(formatSpeed(1), '1');
      expect(formatSpeed(2.0), '2');
    });

    test('décimales sans zéros superflus', () {
      expect(formatSpeed(1.5), '1.5');
      expect(formatSpeed(0.75), '0.75');
      expect(formatSpeed(1.25), '1.25');
    });
  });
}
