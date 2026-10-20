import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/utils/pairing_code.dart';

/// La saisie manuelle est le repli quand le scan échoue : si elle flanche, il
/// ne reste plus rien à l'utilisateur. Chaque cas ci-dessous est une façon
/// dont on recopie réellement un code lu sur un autre écran.
void main() {
  group('Ce que le desktop affiche', () {
    test('le code affiché ne contient que des chiffres et deux séparateurs', () {
      final code = PairingCode.format(host: '192.168.1.24', port: 41530);
      expect(code, '192.168.1.24:41530');
      // Aucune lettre : donc aucune confusion possible entre O et 0, ni entre
      // l, I et 1, au moment de le recopier.
      expect(RegExp(r'^[0-9.:]+$').hasMatch(code), isTrue);
    });

    test('ce qui est affiché se relit tel quel', () {
      final code = PairingCode.format(host: '10.0.0.7', port: 41530);
      expect(PairingCode.parse(code),
          const PairingTarget(host: '10.0.0.7', port: 41530));
    });
  });

  group('Ce que l\'utilisateur tape', () {
    const expected = PairingTarget(host: '192.168.1.24', port: 41530);

    final variants = <String, String>{
      'forme canonique': '192.168.1.24:41530',
      'espaces autour': '   192.168.1.24:41530  ',
      'espaces autour du deux-points': '192.168.1.24 : 41530',
      'deux-points oublié': '192.168.1.24 41530',
      'point-virgule au lieu du deux-points': '192.168.1.24;41530',
      'espaces autour des points': '192. 168. 1. 24 : 41530',
      'port avec une espace fine': '192.168.1.24:41 530',
      'guillemets français d\'un copier-coller': '« 192.168.1.24:41530 »',
      'guillemets droits': '"192.168.1.24:41530"',
      'parenthèses': '(192.168.1.24:41530)',
      'point final de la phrase': 'Code : 192.168.1.24:41530.',
      'O majuscule lu pour un zéro': '192.168.1.24:4153O',
      'l minuscule lu pour un un': 'l92.168.l.24:41530',
      'I majuscule lu pour un un': 'I92.168.I.24:41530',
      'URL de flux copiée': 'ws://192.168.1.24:41530/api/ws',
      'URL http': 'http://192.168.1.24:41530/',
    };

    variants.forEach((label, raw) {
      test('$label : « $raw »', () {
        expect(PairingCode.parse(raw), expected);
      });
    });

    test('l\'adresse seule prend le port d\'OMNIA Connect', () {
      expect(PairingCode.parse('192.168.1.24'),
          const PairingTarget(host: '192.168.1.24', port: 41530));
      expect(PairingCode.defaultPort, 41530);
    });

    test('un nom d\'hôte garde ses lettres', () {
      // Ici un « l » est un « l » : on ne corrige les glyphes que dans les
      // groupes déjà reconnus comme numériques.
      expect(PairingCode.parse('omnia-local:41530'),
          const PairingTarget(host: 'omnia-local', port: 41530));
      expect(PairingCode.parse('portable.local'),
          const PairingTarget(host: 'portable.local', port: 41530));
    });

    test('le payload du QR code se lit aussi à la main', () {
      // Cas du presse-papier : l'utilisateur copie tout le payload affiché
      // plutôt que la seule adresse.
      const payload = '{"protocol":"omnia-connect","version":"1.0",'
          '"name":"OMNIA Desktop","host":"192.168.1.24","port":41530,'
          '"token":"q4Zx7Jb1kLmN0pQrStUvWw=="}';
      expect(
        PairingCode.parse(payload),
        const PairingTarget(
          host: '192.168.1.24',
          port: 41530,
          token: 'q4Zx7Jb1kLmN0pQrStUvWw==',
        ),
      );
    });

    test('un jeton collé après l\'adresse est conservé tel quel', () {
      final target =
          PairingCode.parse('192.168.1.24 41530 q4Zx7Jb1kLmN0pQrStUvWw==');
      expect(target?.host, '192.168.1.24');
      expect(target?.port, 41530);
      // Un jeton est opaque : le « corriger » le casserait, la casse et les
      // glyphes y restent intacts.
      expect(target?.token, 'q4Zx7Jb1kLmN0pQrStUvWw==');
    });

    test('le jeton d\'une URL de flux est repris', () {
      final target = PairingCode.parse(
          'ws://192.168.1.24:41530/api/ws?token=AbC-dEf_123');
      expect(target?.token, 'AbC-dEf_123');
    });
  });

  group('Ce que l\'on refuse plutôt que de tenter au hasard', () {
    test('une saisie vide', () {
      expect(PairingCode.parse(''), isNull);
      expect(PairingCode.parse('    '), isNull);
    });

    test('un octet impossible', () {
      expect(PairingCode.parse('192.168.1.300'), isNull);
    });

    test('un nombre nu n\'est pas une adresse', () {
      // Taper le seul port ne donne pas d'adresse : mieux vaut le dire que
      // d'essayer de joindre un hôte nommé « 41530 ».
      expect(PairingCode.parse('41530'), isNull);
    });

    test('du texte sans adresse', () {
      expect(PairingCode.parse('bonjour'), isNotNull,
          reason: 'un mot seul reste un nom d\'hôte plausible');
      expect(PairingCode.parse('!!! ???'), isNull);
    });

    test('un port hors bornes retombe sur le port par défaut', () {
      expect(PairingCode.parse('192.168.1.24:99999')?.port,
          PairingCode.defaultPort);
    });

    test('un JSON tronqué ne fait pas échouer la lecture en clair', () {
      // Copier-coller partiel : on retrouve quand même l'adresse.
      final target =
          PairingCode.parse('{"host":"192.168.1.24","port":41530');
      expect(target?.host, '192.168.1.24');
      expect(target?.port, 41530);
    });
  });
}
