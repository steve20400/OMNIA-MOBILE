import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/utils/qr_code.dart';

/// Ce que cette suite prouve, et comment.
///
/// Le symptôme à l'origine de ces tests : « la caméra voit le QR affiché par
/// le PC mais rien n'est jamais décodé ». Un test qui se contente de relire la
/// matrice avec les outils de l'encodeur ne prouve rien — c'est précisément
/// l'erreur qui avait laissé passer le bug. Chaque groupe ci-dessous s'appuie
/// donc sur quelque chose d'extérieur à `qr_code.dart` :
///
/// 1. les tables publiées de la norme ISO/IEC 18004 (information de format
///    table 25, information de version table 26, capacités en mode octet) ;
/// 2. des **matrices de référence produites par un encodeur tiers**
///    (`cv2.QRCodeEncoder` d'OpenCV 5.0), recopiées ici module par module ;
/// 3. un **décodeur indépendant** écrit dans ce fichier depuis la norme, et
///    lui-même validé sur une matrice de référence qu'OMNIA ne sait pas
///    produire (mode alphanumérique, masque 0) ;
/// 4. les invariants structurels de la norme, et la propriété mathématique
///    des syndromes Reed-Solomon, qui ne dépend d'aucune implémentation.
void main() {
  group('Ancrage sur les tables publiées de la norme', () {
    test('information de format, niveau M : table 25 d\'ISO/IEC 18004', () {
      // Les 8 mots de 15 bits du niveau M, tels que la norme les publie. Un
      // seul bit faux ici et aucun lecteur ne regarde les données.
      const table25M = [
        0x5412, 0x5125, 0x5E7C, 0x5B4B,
        0x45F9, 0x40CE, 0x4F97, 0x4AA0,
      ];
      for (var mask = 0; mask < 8; mask++) {
        expect(
          QrCode.formatInformation(QrCode.errorCorrectionLevel, mask),
          table25M[mask],
          reason: 'masque $mask',
        );
      }
    });

    test('information de format, les quatre niveaux : table 25 complète', () {
      // Indexée par les bits de niveau de la norme : L=01, M=00, Q=11, H=10.
      const table25 = {
        1: [0x77C4, 0x72F3, 0x7DAA, 0x789D, 0x662F, 0x6318, 0x6C41, 0x6976],
        0: [0x5412, 0x5125, 0x5E7C, 0x5B4B, 0x45F9, 0x40CE, 0x4F97, 0x4AA0],
        3: [0x355F, 0x3068, 0x3F31, 0x3A06, 0x24B4, 0x2183, 0x2EDA, 0x2BED],
        2: [0x1689, 0x13BE, 0x1CE7, 0x19D0, 0x0762, 0x0255, 0x0D0C, 0x083B],
      };
      table25.forEach((level, words) {
        for (var mask = 0; mask < 8; mask++) {
          expect(QrCode.formatInformation(level, mask), words[mask],
              reason: 'niveau $level masque $mask');
        }
      });
    });

    test('le code de format garde la distance de Hamming 7 de BCH(15,5)', () {
      // Propriété mathématique du code, indépendante de toute table : c'est
      // elle qui permet au lecteur de corriger jusqu'à trois bits abîmés.
      final words = <int>[
        for (final level in [0, 1, 2, 3])
          for (var mask = 0; mask < 8; mask++)
            QrCode.formatInformation(level, mask),
      ];
      var minimum = 99;
      for (var i = 0; i < words.length; i++) {
        for (var j = i + 1; j < words.length; j++) {
          final distance = _popCount(words[i] ^ words[j]);
          if (distance < minimum) minimum = distance;
        }
      }
      expect(minimum, 7);
    });

    test('information de version : table 26 d\'ISO/IEC 18004', () {
      const table26 = {
        7: 0x07C94,
        8: 0x085BC,
        9: 0x09A99,
        10: 0x0A4D3,
      };
      table26.forEach((version, expected) {
        expect(QrCode.versionInformation(version), expected,
            reason: 'version $version');
      });
    });

    test('capacités en mode octet, niveau M : table 7 de la norme', () {
      const published = [14, 26, 42, 62, 84, 106, 122, 152, 180, 213];
      for (var version = 1; version <= 10; version++) {
        expect(QrCode.byteCapacity(version), published[version - 1],
            reason: 'version $version');
      }
    });

    test('la version retenue est la plus petite qui suffit', () {
      expect(QrCode.versionFor(14), 1);
      expect(QrCode.versionFor(15), 2);
      expect(QrCode.versionFor(26), 2);
      expect(QrCode.versionFor(27), 3);
      expect(QrCode.versionFor(213), 10);
      expect(QrCode.versionFor(214), isNull);
    });

    test('un texte trop long échoue au lieu d\'être tronqué', () {
      expect(() => QrCode.encode('A' * 214), throwsArgumentError);
    });
  });

  group('Vecteurs de référence : matrices produites par un encodeur tiers', () {
    // Matrices obtenues avec `cv2.QRCodeEncoder` (OpenCV 5.0), niveau M,
    // version 1, puis recopiées ici module par module. Chacune de ces chaînes
    // est encodée en mode octet par OpenCV comme par OMNIA, et les deux
    // implémentations retiennent le même masque : la comparaison porte donc
    // sur les 441 modules, information de format comprise.
    //
    // C'est l'ancrage le plus fort de cette suite : il ne reste aucune place
    // pour une convention « cohérente avec elle-même mais fausse ».
    const references = <String, List<String>>{
      'omnia-connect': [
        '#######....##.#######',
        '#.....#..##...#.....#',
        '#.###.#.####..#.###.#',
        '#.###.#.###...#.###.#',
        '#.###.#.###.#.#.###.#',
        '#.....#.#..#..#.....#',
        '#######.#.#.#.#######',
        '........##...........',
        '#.#####..###..#####..',
        '###..#.#.##.######..#',
        '#.###.#.#.#.###..###.',
        '.....#.#..#.##..#####',
        '#####.###..##.##...##',
        '........##.#.#####..#',
        '#######...###.#....#.',
        '#.....#.####.#...###.',
        '#.###.#.#...#.#.#..##',
        '#.###.#.#....####....',
        '#.###.#.#####.##.##..',
        '#.....#..#####...##..',
        '#######.#.###.##...#.',
      ],
      'test': [
        '#######...#...#######',
        '#.....#.#.#.#.#.....#',
        '#.###.#....#..#.###.#',
        '#.###.#..##...#.###.#',
        '#.###.#.##.##.#.###.#',
        '#.....#..#.#..#.....#',
        '#######.#.#.#.#######',
        '.........##..........',
        '#.#.#.#...#.#...#..#.',
        '..####.#..##.#.#...##',
        '#.#...######.###.####',
        '...###..######.##..#.',
        '#.#.#.#..###.###.#.##',
        '........#.....#..#..#',
        '#######..#..#...##.##',
        '#.....#...#...#....#.',
        '#.###.#.###.#.#.##.##',
        '#.###.#...##.#.#...#.',
        '#.###.#.####.###..#.#',
        '#.....#...####.###.#.',
        '#######.####.###..###',
      ],
      'OMNIA Connect': [
        '#######..#..#.#######',
        '#.....#..#.##.#.....#',
        '#.###.#...###.#.###.#',
        '#.###.#...#.#.#.###.#',
        '#.###.#..#..#.#.###.#',
        '#.....#.##.##.#.....#',
        '#######.#.#.#.#######',
        '.........#.##........',
        '#..#.##.#....#.#.....',
        '#.#.#..#.#.#..###.##.',
        '#..##.####..#..#.##.#',
        '.#.#...#.##...#.##...',
        '###.#.#.##.##...#.##.',
        '........#...#####.#..',
        '#######..##.#.####.#.',
        '#.....#.##..#..#.....',
        '#.###.#..#..##....#..',
        '#.###.#.#...#..##.###',
        '#.###.#..#.##...###.#',
        '#.....#..#...#..#....',
        '#######.###.#.#.####.',
      ],
      'a': [
        '#######..#.##.#######',
        '#.....#.#.##..#.....#',
        '#.###.#.##.#..#.###.#',
        '#.###.#.#.##..#.###.#',
        '#.###.#..#..#.#.###.#',
        '#.....#...##..#.....#',
        '#######.#.#.#.#######',
        '........##...........',
        '#.....#.#.##.##..###.',
        '#..##......###.###..#',
        '..#.###..##.#.##.....',
        '.#.#.#.##..#####.#.#.',
        '##.#..####.##########',
        '........##..#.....#.#',
        '#######..###.#..####.',
        '#.....#...#...#...###',
        '#.###.#..###.#..###..',
        '#.###.#..#.#####.#...',
        '#.###.#..#.###.###.##',
        '#.....#...######.#...',
        '#######.#.#.#..#..##.',
      ],
    };

    references.forEach((text, expected) {
      test('« $text » reproduit la matrice d\'OpenCV module par module', () {
        final code = QrCode.encode(text);
        expect(code.version, 1);
        expect(code.size, 21);
        expect(_render(code), expected);
      });
    });

    test('les quatre références couvrent quatre masques différents', () {
      // Un masque faux ne se voit que si plusieurs masques sont exercés : le
      // choix du masque dépend des pénalités, et c'est lui qui s'écrit dans
      // l'information de format.
      final masks = {
        for (final text in references.keys) QrCode.encode(text).mask,
      };
      expect(masks.length, greaterThanOrEqualTo(4));
    });
  });

  group('Décodeur indépendant : validation du décodeur lui-même', () {
    test('décode une matrice tierce qu\'OMNIA ne sait pas produire', () {
      // « HELLO WORLD » encodé par OpenCV en **mode alphanumérique**, masque
      // 0 : deux choses qu'OMNIA n'émet jamais (toujours mode octet, et le
      // masque 0 n'est pas retenu ici). Si le décodeur de ce fichier lit cette
      // matrice, c'est qu'il suit la norme et non les conventions de
      // `qr_code.dart`. Sans ce test, l'aller-retour qui suit ne prouverait
      // qu'une cohérence interne.
      const openCvHelloWorld = [
        '#######...#.#.#######',
        '#.....#.###...#.....#',
        '#.###.#...#.#.#.###.#',
        '#.###.#...#.#.#.###.#',
        '#.###.#.#.###.#.###.#',
        '#.....#..###..#.....#',
        '#######.#.#.#.#######',
        '.....................',
        '#.#.#.#..#..#...#..#.',
        '.####...#..#....#...#',
        '...#######.#..#.##...',
        '####.#.##..###.#.###.',
        '.#..####.#.#..###.#.#',
        '........#.#...#...#.#',
        '#######.....#..#.##..',
        '#.....#..##...##.#...',
        '#.###.#.##..#.#######',
        '#.###.#...##.#.#...#.',
        '#.###.#.####.###.#..#',
        '#.....#....###...#.##',
        '#######.##.#.###....#',
      ];

      final matrix = _parse(openCvHelloWorld);
      final read = _QrReader(matrix, 1);

      // Les deux copies de l'information de format disent la même chose, et
      // ce mot figure dans la table 25 du niveau M.
      expect(read.formatCopy1, 0x5412);
      expect(read.formatCopy2, 0x5412);
      expect(read.mask, 0);

      // Les syndromes Reed-Solomon s'annulent : le mot de code est bien
      // divisible par le polynôme générateur de la norme.
      expect(read.syndromesAreZero, isTrue);

      expect(read.mode, 2, reason: 'mode alphanumérique');
      expect(read.characterCount, 11);
      expect(read.alphanumericText, 'HELLO WORLD');
    });

    test('le corps de Galois du décodeur est celui de la norme', () {
      // α^8 = 0x1D avec le polynôme primitif 0x11D : vérification du corps
      // avant de s'appuyer sur lui pour les syndromes.
      expect(_gfExp[8], 0x1D);
      expect(_gfExp[0], 1);
      expect(_gfExp[254], 0x8E);
      expect(_gfMul(0x53, 0x8C), 0x01, reason: 'inverses dans GF(256)');
    });
  });

  group('Aller-retour : tout ce qui est encodé se relit', () {
    const payload =
        '{"protocol":"omnia-connect","version":"1.0","name":"OMNIA Desktop",'
        '"host":"192.168.1.24","port":41530,"token":"q4Zx7Jb1kLmN0pQrStUvWw=="}';

    final samples = <String>[
      'a',
      'OMNIA',
      'omnia-connect',
      '192.168.1.24:41530',
      payload,
      'Éàç — accents UTF-8 ✓',
      // Longueurs limites : juste avant et juste après chaque changement de
      // version. C'est là que se cassent les en-têtes de longueur, le
      // bourrage et l'entrelacement.
      'A' * 14, 'A' * 15,
      'A' * 26, 'A' * 27,
      'A' * 42, 'A' * 43,
      'A' * 122, 'A' * 123,
      'A' * 152, 'A' * 153,
      'A' * 180, 'A' * 181,
      'A' * 213,
    ];

    for (final text in samples) {
      final label = text.length > 24 ? '${text.substring(0, 21)}… (${text.length})' : text;
      test('« $label » se relit à l\'identique', () {
        final code = QrCode.encode(text);
        final read = _QrReader(
          [for (final row in code.modules) List<bool>.from(row)],
          code.version,
        );

        expect(read.formatCopy1, read.formatCopy2,
            reason: 'les deux copies du format doivent concorder');
        expect(_formatTableM.contains(read.formatCopy1), isTrue,
            reason: 'format 0x${read.formatCopy1.toRadixString(16)} '
                'absent de la table 25 du niveau M');
        expect(read.mask, code.mask,
            reason: 'le masque inscrit doit être celui appliqué');
        expect(read.syndromesAreZero, isTrue,
            reason: 'syndromes Reed-Solomon non nuls : correction d\'erreur '
                'fausse ou entrelacement faux');
        expect(read.mode, 4, reason: 'mode octet');
        expect(read.characterCount, utf8.encode(text).length);
        expect(read.byteText, text);
      });
    }
  });

  group('Invariants structurels de la norme', () {
    // Une version par taille, du plus petit au plus grand code géré. Les
    // versions 7 et plus portent en outre l'information de version.
    final byVersion = <int, QrCode>{
      1: QrCode.encode('A' * 14),
      2: QrCode.encode('A' * 26),
      3: QrCode.encode('A' * 42),
      4: QrCode.encode('A' * 62),
      5: QrCode.encode('A' * 84),
      6: QrCode.encode('A' * 106),
      7: QrCode.encode('A' * 122),
      8: QrCode.encode('A' * 152),
      9: QrCode.encode('A' * 180),
      10: QrCode.encode('A' * 213),
    };

    byVersion.forEach((version, code) {
      group('version $version', () {
        test('taille 17 + 4×version', () {
          expect(code.version, version);
          expect(code.size, 17 + 4 * version);
        });

        test('trois motifs de détection, au module près', () {
          final size = code.size;
          for (final corner in [
            const [0, 0],
            [0, size - 7],
            [size - 7, 0],
          ]) {
            for (var r = 0; r < 7; r++) {
              for (var c = 0; c < 7; c++) {
                final onBorder = r == 0 || r == 6 || c == 0 || c == 6;
                final inCore = r >= 2 && r <= 4 && c >= 2 && c <= 4;
                expect(
                  code.isDark(corner[0] + r, corner[1] + c),
                  onBorder || inCore,
                  reason: 'motif en (${corner[0]}, ${corner[1]}) '
                      'module ($r, $c)',
                );
              }
            }
          }
        });

        test('séparateurs clairs autour des trois motifs', () {
          final size = code.size;
          for (var i = 0; i < 8; i++) {
            expect(code.isDark(7, i), isFalse, reason: 'ligne 7 col $i');
            expect(code.isDark(i, 7), isFalse, reason: 'col 7 ligne $i');
            expect(code.isDark(7, size - 1 - i), isFalse);
            expect(code.isDark(i, size - 8), isFalse);
            expect(code.isDark(size - 8, i), isFalse);
            expect(code.isDark(size - 1 - i, 7), isFalse);
          }
        });

        test('deux lignes de synchronisation, sombres aux rangs pairs', () {
          for (var i = 8; i < code.size - 8; i++) {
            expect(code.isDark(6, i), i.isEven, reason: 'ligne 6 col $i');
            expect(code.isDark(i, 6), i.isEven, reason: 'col 6 ligne $i');
          }
        });

        test('motifs d\'alignement 5×5 à chaque centre', () {
          final centers = _alignmentCentersForTest[version]!;
          final size = code.size;
          for (final row in centers) {
            for (final col in centers) {
              final onFinder = (row == 6 && col == 6) ||
                  (row == 6 && col == size - 7) ||
                  (row == size - 7 && col == 6);
              if (onFinder) continue;
              for (var dr = -2; dr <= 2; dr++) {
                for (var dc = -2; dc <= 2; dc++) {
                  final onEdge = dr.abs() == 2 || dc.abs() == 2;
                  final atCenter = dr == 0 && dc == 0;
                  expect(
                    code.isDark(row + dr, col + dc),
                    onEdge || atCenter,
                    reason: 'alignement ($row, $col) module ($dr, $dc)',
                  );
                }
              }
            }
          }
        });

        test('module sombre obligatoire en (taille − 8, 8)', () {
          expect(code.isDark(code.size - 8, 8), isTrue);
        });

        test('les deux zones d\'information de format concordent', () {
          final read = _QrReader(
            [for (final row in code.modules) List<bool>.from(row)],
            version,
          );
          expect(read.formatCopy1, read.formatCopy2);
          expect(_formatTableM.contains(read.formatCopy1), isTrue);
        });

        if (version >= 7) {
          test('les deux blocs d\'information de version portent le BCH', () {
            final expected = QrCode.versionInformation(version);
            expect(expected, _versionTable26[version]);
            final size = code.size;
            for (var i = 0; i < 18; i++) {
              final bit = ((expected >> i) & 1) == 1;
              expect(code.isDark(size - 11 + i % 3, i ~/ 3), bit,
                  reason: 'bloc inférieur gauche, bit $i');
              expect(code.isDark(i ~/ 3, size - 11 + i % 3), bit,
                  reason: 'bloc supérieur droit, bit $i');
            }
          });
        }
      });
    });
  });
}

// --- Rendu et comparaison ----------------------------------------------------

List<String> _render(QrCode code) => [
      for (var r = 0; r < code.size; r++)
        [
          for (var c = 0; c < code.size; c++) code.isDark(r, c) ? '#' : '.',
        ].join(),
    ];

List<List<bool>> _parse(List<String> rows) =>
    [for (final row in rows) [for (final ch in row.split('')) ch == '#']];

int _popCount(int value) {
  var n = 0;
  var v = value;
  while (v != 0) {
    n += v & 1;
    v >>= 1;
  }
  return n;
}

// --- Décodeur indépendant ----------------------------------------------------
//
// Écrit depuis la norme, sans rien emprunter à `qr_code.dart` : ses tables, son
// corps de Galois et son parcours lui sont propres. Validé plus haut sur une
// matrice produite par OpenCV.

/// Table 25 de la norme, niveau M : c'est elle qui donne le masque, et non
/// une fonction de l'encodeur.
const List<int> _formatTableM = [
  0x5412, 0x5125, 0x5E7C, 0x5B4B, 0x45F9, 0x40CE, 0x4F97, 0x4AA0,
];

const Map<int, int> _versionTable26 = {
  7: 0x07C94,
  8: 0x085BC,
  9: 0x09A99,
  10: 0x0A4D3,
};

const Map<int, List<int>> _alignmentCentersForTest = {
  1: [],
  2: [6, 18],
  3: [6, 22],
  4: [6, 26],
  5: [6, 30],
  6: [6, 34],
  7: [6, 22, 38],
  8: [6, 24, 42],
  9: [6, 26, 46],
  10: [6, 28, 50],
};

/// Découpage en blocs du niveau M : (correction par bloc, blocs du groupe 1,
/// données du groupe 1, blocs du groupe 2, données du groupe 2).
const Map<int, List<int>> _blocksM = {
  1: [10, 1, 16, 0, 0],
  2: [16, 1, 28, 0, 0],
  3: [26, 1, 44, 0, 0],
  4: [18, 2, 32, 0, 0],
  5: [24, 2, 43, 0, 0],
  6: [16, 4, 27, 0, 0],
  7: [18, 4, 31, 0, 0],
  8: [22, 2, 38, 2, 39],
  9: [22, 3, 36, 2, 37],
  10: [26, 4, 43, 1, 44],
};

const String _alphanumericAlphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ \$%*+-./:';

final List<int> _gfExp = _buildExp();
final List<int> _gfLog = _buildLog();

List<int> _buildExp() {
  final exp = List<int>.filled(512, 0);
  var x = 1;
  for (var i = 0; i < 255; i++) {
    exp[i] = x;
    x <<= 1;
    if (x & 0x100 != 0) x ^= 0x11D;
  }
  for (var i = 255; i < 512; i++) {
    exp[i] = exp[i - 255];
  }
  return exp;
}

List<int> _buildLog() {
  final log = List<int>.filled(256, 0);
  for (var i = 0; i < 255; i++) {
    log[_gfExp[i]] = i;
  }
  return log;
}

int _gfMul(int a, int b) {
  if (a == 0 || b == 0) return 0;
  return _gfExp[_gfLog[a] + _gfLog[b]];
}

/// Lecteur de matrice QR : démasquage, extraction des mots de code,
/// désentrelacement, vérification des syndromes et lecture du segment.
class _QrReader {
  _QrReader(this._modules, this.version) : size = 17 + 4 * version {
    _function = _functionMap();
    _bits = _readDataBits();
  }

  final List<List<bool>> _modules;
  final int version;
  final int size;
  late final List<List<bool>> _function;
  late final List<bool> _bits;

  /// Première copie : bits 0 à 5 dans la **colonne** 8 (lignes 0 à 5), coude
  /// en (7, 8) et (8, 8), puis bits 9 à 14 sur la **ligne** 8 vers la gauche.
  int get formatCopy1 {
    var bits = 0;
    for (var i = 0; i <= 5; i++) {
      if (_modules[i][8]) bits |= 1 << i;
    }
    if (_modules[7][8]) bits |= 1 << 6;
    if (_modules[8][8]) bits |= 1 << 7;
    if (_modules[8][7]) bits |= 1 << 8;
    for (var i = 9; i < 15; i++) {
      if (_modules[8][14 - i]) bits |= 1 << i;
    }
    return bits;
  }

  /// Seconde copie : bits 0 à 7 sur la ligne 8 depuis le bord droit, bits 8 à
  /// 14 dans la colonne 8 jusqu'au coin inférieur gauche.
  int get formatCopy2 {
    var bits = 0;
    for (var i = 0; i <= 7; i++) {
      if (_modules[8][size - 1 - i]) bits |= 1 << i;
    }
    for (var i = 8; i < 15; i++) {
      if (_modules[size - 15 + i][8]) bits |= 1 << i;
    }
    return bits;
  }

  int get mask => _formatTableM.indexOf(formatCopy1);

  List<List<bool>> _functionMap() {
    final map = List.generate(size, (_) => List<bool>.filled(size, false));
    void mark(int r, int c) {
      if (r >= 0 && c >= 0 && r < size && c < size) map[r][c] = true;
    }

    // Motifs de détection avec leur séparateur.
    for (final corner in [
      const [0, 0],
      [0, size - 7],
      [size - 7, 0],
    ]) {
      for (var r = -1; r <= 7; r++) {
        for (var c = -1; c <= 7; c++) {
          mark(corner[0] + r, corner[1] + c);
        }
      }
    }
    // Synchronisation.
    for (var i = 0; i < size; i++) {
      mark(6, i);
      mark(i, 6);
    }
    // Alignement.
    final centers = _alignmentCentersForTest[version]!;
    for (final row in centers) {
      for (final col in centers) {
        if ((row == 6 && col == 6) ||
            (row == 6 && col == size - 7) ||
            (row == size - 7 && col == 6)) {
          continue;
        }
        for (var dr = -2; dr <= 2; dr++) {
          for (var dc = -2; dc <= 2; dc++) {
            mark(row + dr, col + dc);
          }
        }
      }
    }
    // Information de format, module sombre compris.
    for (var i = 0; i <= 8; i++) {
      mark(8, i);
      mark(i, 8);
    }
    for (var i = 0; i < 8; i++) {
      mark(8, size - 1 - i);
    }
    for (var i = 1; i <= 8; i++) {
      mark(size - i, 8);
    }
    // Information de version.
    if (version >= 7) {
      for (var i = 0; i < 18; i++) {
        mark(size - 11 + i % 3, i ~/ 3);
        mark(i ~/ 3, size - 11 + i % 3);
      }
    }
    return map;
  }

  bool _maskedAt(int row, int col) {
    switch (mask) {
      case 0:
        return (row + col) % 2 == 0;
      case 1:
        return row % 2 == 0;
      case 2:
        return col % 3 == 0;
      case 3:
        return (row + col) % 3 == 0;
      case 4:
        return (row ~/ 2 + col ~/ 3) % 2 == 0;
      case 5:
        return (row * col) % 2 + (row * col) % 3 == 0;
      case 6:
        return ((row * col) % 2 + (row * col) % 3) % 2 == 0;
      default:
        return ((row + col) % 2 + (row * col) % 3) % 2 == 0;
    }
  }

  /// Parcours de la norme, écrit indépendamment de l'encodeur : paires de
  /// colonnes de droite à gauche, sens de lecture déduit de la position de la
  /// colonne et non d'un compteur.
  List<bool> _readDataBits() {
    final bits = <bool>[];
    var right = size - 1;
    while (right >= 1) {
      if (right == 6) right = 5;
      final upward = ((right + 1) & 2) == 0;
      for (var vertical = 0; vertical < size; vertical++) {
        for (var offset = 0; offset < 2; offset++) {
          final col = right - offset;
          final row = upward ? size - 1 - vertical : vertical;
          if (_function[row][col]) continue;
          final module = _modules[row][col];
          bits.add(_maskedAt(row, col) ? !module : module);
        }
      }
      right -= 2;
    }
    return bits;
  }

  List<int> get _codewords {
    final words = <int>[];
    for (var i = 0; i + 8 <= _bits.length; i += 8) {
      var value = 0;
      for (var j = 0; j < 8; j++) {
        value = (value << 1) | (_bits[i + j] ? 1 : 0);
      }
      words.add(value);
    }
    return words;
  }

  /// Blocs désentrelacés : données d'abord, correction ensuite.
  ({List<List<int>> data, List<List<int>> ec, int ecLength}) get _blocks {
    final layout = _blocksM[version]!;
    final ecLength = layout[0];
    final lengths = <int>[
      for (var i = 0; i < layout[1]; i++) layout[2],
      for (var i = 0; i < layout[3]; i++) layout[4],
    ];
    final words = _codewords;
    final data = [for (final _ in lengths) <int>[]];
    final ec = [for (final _ in lengths) <int>[]];
    var index = 0;
    final longest = lengths.reduce((a, b) => a > b ? a : b);
    for (var i = 0; i < longest; i++) {
      for (var b = 0; b < lengths.length; b++) {
        if (i < lengths[b]) data[b].add(words[index++]);
      }
    }
    for (var i = 0; i < ecLength; i++) {
      for (var b = 0; b < lengths.length; b++) {
        ec[b].add(words[index++]);
      }
    }
    return (data: data, ec: ec, ecLength: ecLength);
  }

  /// Un mot de code Reed-Solomon valide s'annule en α^0 … α^(n−1) : propriété
  /// mathématique du code, qui ne dépend d'aucune implémentation. Un
  /// générateur faux, un bloc mal découpé ou un entrelacement inversé la
  /// violent aussitôt.
  bool get syndromesAreZero {
    final blocks = _blocks;
    for (var b = 0; b < blocks.data.length; b++) {
      final word = [...blocks.data[b], ...blocks.ec[b]];
      for (var k = 0; k < blocks.ecLength; k++) {
        var accumulator = 0;
        for (final coefficient in word) {
          accumulator = _gfMul(accumulator, _gfExp[k]) ^ coefficient;
        }
        if (accumulator != 0) return false;
      }
    }
    return true;
  }

  List<bool> get _payloadBits {
    final bits = <bool>[];
    for (final block in _blocks.data) {
      for (final byte in block) {
        for (var i = 7; i >= 0; i--) {
          bits.add(((byte >> i) & 1) == 1);
        }
      }
    }
    return bits;
  }

  int _value(List<bool> bits, int start, int count) {
    var value = 0;
    for (var i = 0; i < count; i++) {
      value = (value << 1) | (bits[start + i] ? 1 : 0);
    }
    return value;
  }

  int get mode => _value(_payloadBits, 0, 4);

  int get _countBits => switch (mode) {
        1 => version < 10 ? 10 : 12,
        2 => version < 10 ? 9 : 11,
        _ => version < 10 ? 8 : 16,
      };

  int get characterCount => _value(_payloadBits, 4, _countBits);

  /// Segment en mode octet, relu en UTF-8.
  String get byteText {
    final bits = _payloadBits;
    final start = 4 + _countBits;
    final bytes = <int>[
      for (var i = 0; i < characterCount; i++) _value(bits, start + 8 * i, 8),
    ];
    return utf8.decode(bytes);
  }

  /// Segment en mode alphanumérique : paires de caractères sur 11 bits, un
  /// caractère seul sur 6. Présent pour valider ce lecteur sur une matrice
  /// tierce, OMNIA n'émettant que du mode octet.
  String get alphanumericText {
    final bits = _payloadBits;
    var position = 4 + _countBits;
    final out = StringBuffer();
    var remaining = characterCount;
    while (remaining >= 2) {
      final pair = _value(bits, position, 11);
      position += 11;
      out.write(_alphanumericAlphabet[pair ~/ 45]);
      out.write(_alphanumericAlphabet[pair % 45]);
      remaining -= 2;
    }
    if (remaining == 1) {
      out.write(_alphanumericAlphabet[_value(bits, position, 6)]);
    }
    return out.toString();
  }
}
