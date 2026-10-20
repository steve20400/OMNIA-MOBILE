import 'dart:convert';

/// Encodeur QR Code conforme à ISO/IEC 18004 : mode octet, correction M.
///
/// Écrit ici plutôt que pris dans un paquet : l'appairage ne doit dépendre de
/// rien, mais il doit produire un vrai code. La matrice porte donc tout ce que
/// réclame la norme — motifs de recherche et d'alignement, motifs de
/// synchronisation, module sombre, information de format protégée, masque
/// choisi par pénalité, et mots de correction Reed-Solomon entrelacés.
///
/// Ce qui précédait dessinait trois coins et un damier tiré des octets du
/// texte : l'image ressemblait à un QR code, mais aucun lecteur ne pouvait en
/// tirer quoi que ce soit — ni l'appareil photo du téléphone, ni une
/// application tierce. C'est la cause de « la caméra voit le code mais ne le
/// détecte pas ».
class QrCode {
  QrCode._({
    required this.version,
    required this.mask,
    required this.modules,
  });

  /// Construit la matrice du texte [text], encodé en UTF-8.
  ///
  /// Lève une [ArgumentError] si le texte dépasse la capacité de la plus
  /// grande version gérée : mieux vaut un échec visible qu'un code tronqué.
  factory QrCode.encode(String text) {
    final data = utf8.encode(text);
    final version = versionFor(data.length);
    if (version == null) {
      throw ArgumentError.value(
        text,
        'text',
        'Texte trop long pour un QR code de version $maxVersion '
            '(${data.length} octets, maximum ${byteCapacity(maxVersion)})',
      );
    }

    final codewords = _codewords(data, version);
    final builder = _MatrixBuilder(version)..placeFunctionPatterns();
    builder.placeData(codewords);
    final mask = builder.applyBestMask();

    return QrCode._(
      version: version,
      mask: mask,
      modules: builder.modules,
    );
  }

  /// Version maximale gérée. v10 (57×57) laisse 213 octets : bien au-delà du
  /// code d'appairage, qui en compte une cinquantaine.
  static const int maxVersion = 10;

  /// Niveau de correction d'erreurs : M, soit environ 15 % de la matrice
  /// restituable. Le compromis habituel pour un code affiché à l'écran.
  static const int errorCorrectionLevel = _ecLevelM;

  final int version;

  /// Masque retenu (0 à 7), celui qui minimise les pénalités de la norme.
  final int mask;

  /// Matrice carrée, `true` pour un module sombre. Sans zone de silence : le
  /// widget qui dessine ajoute les quatre modules clairs du pourtour.
  final List<List<bool>> modules;

  int get size => modules.length;

  bool isDark(int row, int col) => modules[row][col];

  /// Nombre d'octets qu'une version peut porter en mode octet.
  static int byteCapacity(int version) {
    final layout = blockLayout(version);
    final headerBits = 4 + (version < 10 ? 8 : 16);
    return (layout.dataCodewords * 8 - headerBits) ~/ 8;
  }

  /// Plus petite version capable de porter [byteLength] octets, ou `null`
  /// au-delà de [maxVersion].
  static int? versionFor(int byteLength) {
    for (var version = 1; version <= maxVersion; version++) {
      if (byteLength <= byteCapacity(version)) return version;
    }
    return null;
  }

  /// Découpage en blocs d'une version : ce qu'il faut connaître pour
  /// entrelacer — ou désentrelacer — les mots de code.
  static QrBlockLayout blockLayout(int version) {
    final layout = _layouts[version];
    if (layout == null) {
      throw ArgumentError.value(version, 'version', 'Version non gérée');
    }
    return layout;
  }

  /// Information de format de la norme : cinq bits (niveau de correction et
  /// masque) protégés par un code BCH(15,5), puis masqués par 0x5412.
  ///
  /// Exposée parce que c'est elle que lit un décodeur avant tout le reste :
  /// un bit faux ici et le lecteur abandonne.
  static int formatInformation(int errorCorrection, int mask) {
    final data = (errorCorrection << 3) | mask;
    var remainder = data << 10;
    for (var i = 0; i < 5; i++) {
      if ((remainder >> (14 - i)) & 1 == 1) {
        remainder ^= 0x537 << (4 - i);
      }
    }
    return ((data << 10) | remainder) ^ 0x5412;
  }

  /// Information de version, obligatoire à partir de la version 7 : six bits
  /// protégés par un code BCH(18,6).
  static int versionInformation(int version) {
    var remainder = version << 12;
    for (var i = 0; i < 6; i++) {
      if ((remainder >> (17 - i)) & 1 == 1) {
        remainder ^= 0x1F25 << (5 - i);
      }
    }
    return (version << 12) | remainder;
  }

  /// Suite complète des mots de code : données et correction, entrelacées
  /// comme l'exige la norme dès qu'il y a plus d'un bloc.
  static List<int> _codewords(List<int> data, int version) {
    final layout = blockLayout(version);
    final bits = _BitBuffer();

    // En-tête : mode octet, puis la longueur sur 8 bits (v1–9) ou 16 (v10+).
    bits.put(0x4, 4);
    bits.put(data.length, version < 10 ? 8 : 16);
    for (final byte in data) {
      bits.put(byte, 8);
    }

    // Terminateur, puis remplissage jusqu'à l'octet, puis les octets de
    // bourrage alternés de la norme.
    final capacityBits = layout.dataCodewords * 8;
    final terminator = capacityBits - bits.length;
    bits.put(0, terminator < 4 ? terminator : 4);
    while (bits.length % 8 != 0) {
      bits.putBit(false);
    }
    const padding = [0xEC, 0x11];
    var padIndex = 0;
    while (bits.length < capacityBits) {
      bits.put(padding[padIndex++ % 2], 8);
    }

    // Découpage en blocs, correction bloc par bloc.
    final dataBlocks = <List<int>>[];
    final ecBlocks = <List<int>>[];
    var offset = 0;
    for (var i = 0; i < layout.blockCount; i++) {
      final length = i < layout.blocksGroup1
          ? layout.dataCodewordsGroup1
          : layout.dataCodewordsGroup2;
      final block = bits.bytes.sublist(offset, offset + length);
      offset += length;
      dataBlocks.add(block);
      ecBlocks.add(_reedSolomon(block, layout.ecCodewordsPerBlock));
    }

    // Entrelacement : un mot de chaque bloc à tour de rôle. Sans lui, une
    // rayure sur le code emporterait un bloc entier au lieu d'être répartie.
    final result = <int>[];
    final longest = layout.dataCodewordsGroup2 > layout.dataCodewordsGroup1
        ? layout.dataCodewordsGroup2
        : layout.dataCodewordsGroup1;
    for (var i = 0; i < longest; i++) {
      for (final block in dataBlocks) {
        if (i < block.length) result.add(block[i]);
      }
    }
    for (var i = 0; i < layout.ecCodewordsPerBlock; i++) {
      for (final block in ecBlocks) {
        result.add(block[i]);
      }
    }
    return result;
  }

  /// Mots de correction d'un bloc : reste de la division polynomiale du bloc
  /// par le polynôme générateur, dans le corps de Galois GF(256).
  static List<int> _reedSolomon(List<int> block, int ecLength) {
    final generator = _generatorPolynomial(ecLength);
    // Registre à décalage : le reste doit pouvoir perdre sa tête et gagner un
    // zéro en queue. Sans `growable`, `List.filled` rend une liste de longueur
    // fixe et le premier octet traité lève « Cannot remove from a
    // fixed-length list » : l'encodage échouait avant d'avoir produit un seul
    // mot de correction, et le QR code n'était jamais affiché.
    final remainder = List<int>.filled(ecLength, 0, growable: true);

    for (final byte in block) {
      final factor = byte ^ remainder[0];
      remainder.removeAt(0);
      remainder.add(0);
      if (factor != 0) {
        for (var i = 0; i < ecLength; i++) {
          remainder[i] ^= _gfMultiply(generator[i + 1], factor);
        }
      }
    }
    return remainder;
  }
}

/// Reed-Solomon public pour les vérifications : même calcul que celui de
/// l'encodeur, utile à qui veut contrôler une matrice décodée.
List<int> qrErrorCorrection(List<int> block, int ecLength) =>
    QrCode._reedSolomon(block, ecLength);

/// Niveau de correction M, tel qu'il s'écrit dans l'information de format.
const int _ecLevelM = 0;

/// Découpage en blocs d'une version, au niveau de correction M.
class QrBlockLayout {
  const QrBlockLayout({
    required this.ecCodewordsPerBlock,
    required this.blocksGroup1,
    required this.dataCodewordsGroup1,
    this.blocksGroup2 = 0,
    this.dataCodewordsGroup2 = 0,
  });

  final int ecCodewordsPerBlock;
  final int blocksGroup1;
  final int dataCodewordsGroup1;
  final int blocksGroup2;
  final int dataCodewordsGroup2;

  int get blockCount => blocksGroup1 + blocksGroup2;

  int get dataCodewords =>
      blocksGroup1 * dataCodewordsGroup1 + blocksGroup2 * dataCodewordsGroup2;

  int get ecCodewords => blockCount * ecCodewordsPerBlock;

  int get totalCodewords => dataCodewords + ecCodewords;
}

/// Table de la norme pour le niveau M, versions 1 à 10.
const Map<int, QrBlockLayout> _layouts = {
  1: QrBlockLayout(
      ecCodewordsPerBlock: 10, blocksGroup1: 1, dataCodewordsGroup1: 16),
  2: QrBlockLayout(
      ecCodewordsPerBlock: 16, blocksGroup1: 1, dataCodewordsGroup1: 28),
  3: QrBlockLayout(
      ecCodewordsPerBlock: 26, blocksGroup1: 1, dataCodewordsGroup1: 44),
  4: QrBlockLayout(
      ecCodewordsPerBlock: 18, blocksGroup1: 2, dataCodewordsGroup1: 32),
  5: QrBlockLayout(
      ecCodewordsPerBlock: 24, blocksGroup1: 2, dataCodewordsGroup1: 43),
  6: QrBlockLayout(
      ecCodewordsPerBlock: 16, blocksGroup1: 4, dataCodewordsGroup1: 27),
  7: QrBlockLayout(
      ecCodewordsPerBlock: 18, blocksGroup1: 4, dataCodewordsGroup1: 31),
  8: QrBlockLayout(
    ecCodewordsPerBlock: 22,
    blocksGroup1: 2,
    dataCodewordsGroup1: 38,
    blocksGroup2: 2,
    dataCodewordsGroup2: 39,
  ),
  9: QrBlockLayout(
    ecCodewordsPerBlock: 22,
    blocksGroup1: 3,
    dataCodewordsGroup1: 36,
    blocksGroup2: 2,
    dataCodewordsGroup2: 37,
  ),
  10: QrBlockLayout(
    ecCodewordsPerBlock: 26,
    blocksGroup1: 4,
    dataCodewordsGroup1: 43,
    blocksGroup2: 1,
    dataCodewordsGroup2: 44,
  ),
};

/// Centres des motifs d'alignement, par version.
const Map<int, List<int>> _alignmentCenters = {
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

/// Tampon de bits, du plus significatif au moins significatif.
class _BitBuffer {
  final List<int> _bytes = [];
  int _length = 0;

  int get length => _length;

  List<int> get bytes => _bytes;

  void putBit(bool bit) {
    if (_length % 8 == 0) _bytes.add(0);
    if (bit) _bytes[_bytes.length - 1] |= 0x80 >> (_length % 8);
    _length++;
  }

  void put(int value, int bitCount) {
    for (var i = bitCount - 1; i >= 0; i--) {
      putBit(((value >> i) & 1) == 1);
    }
  }
}

// --- Corps de Galois GF(256), polynôme primitif 0x11D ------------------------

final List<int> _gfExp = List<int>.filled(512, 0);
final List<int> _gfLog = List<int>.filled(256, 0);
bool _gfReady = false;

void _initGaloisField() {
  if (_gfReady) return;
  var x = 1;
  for (var i = 0; i < 255; i++) {
    _gfExp[i] = x;
    _gfLog[x] = i;
    x <<= 1;
    if (x & 0x100 != 0) x ^= 0x11D;
  }
  for (var i = 255; i < 512; i++) {
    _gfExp[i] = _gfExp[i - 255];
  }
  _gfReady = true;
}

int _gfMultiply(int a, int b) {
  if (a == 0 || b == 0) return 0;
  _initGaloisField();
  return _gfExp[_gfLog[a] + _gfLog[b]];
}

/// Polynôme générateur de degré [degree] : produit des (x - α^i).
List<int> _generatorPolynomial(int degree) {
  _initGaloisField();
  var poly = <int>[1];
  for (var i = 0; i < degree; i++) {
    final next = List<int>.filled(poly.length + 1, 0);
    for (var j = 0; j < poly.length; j++) {
      next[j] ^= poly[j];
      next[j + 1] ^= _gfMultiply(poly[j], _gfExp[i]);
    }
    poly = next;
  }
  return poly;
}

// --- Construction de la matrice ---------------------------------------------

/// Assemble la matrice : motifs de service d'abord, données ensuite, masque
/// enfin. [_reserved] distingue les modules de service, que le masque ne doit
/// jamais toucher et où aucune donnée ne se place.
class _MatrixBuilder {
  _MatrixBuilder(this.version)
      : size = 17 + 4 * version,
        modules = List.generate(
          17 + 4 * version,
          (_) => List<bool>.filled(17 + 4 * version, false),
        ),
        _reserved = List.generate(
          17 + 4 * version,
          (_) => List<bool>.filled(17 + 4 * version, false),
        );

  final int version;
  final int size;
  final List<List<bool>> modules;
  final List<List<bool>> _reserved;

  void placeFunctionPatterns() {
    _placeFinder(0, 0);
    _placeFinder(0, size - 7);
    _placeFinder(size - 7, 0);
    _placeSeparators();
    _placeTimingPatterns();
    _placeAlignmentPatterns();

    // Module sombre : toujours à (4×version + 9, 8).
    _set(4 * version + 9, 8, true);

    _reserveFormatAreas();
    if (version >= 7) _placeVersionInformation();
  }

  void _placeFinder(int row, int col) {
    for (var r = 0; r < 7; r++) {
      for (var c = 0; c < 7; c++) {
        final border = r == 0 || r == 6 || c == 0 || c == 6;
        final core = r >= 2 && r <= 4 && c >= 2 && c <= 4;
        _set(row + r, col + c, border || core);
      }
    }
  }

  /// Séparateurs : une ligne claire autour de chaque motif de recherche. Ils
  /// sont clairs mais réservés, sinon une donnée s'y glisserait.
  void _placeSeparators() {
    for (var i = 0; i < 8; i++) {
      _set(7, i, false);
      _set(i, 7, false);
      _set(7, size - 1 - i, false);
      _set(i, size - 8, false);
      _set(size - 8, i, false);
      _set(size - 1 - i, 7, false);
    }
  }

  void _placeTimingPatterns() {
    for (var i = 8; i < size - 8; i++) {
      final dark = i % 2 == 0;
      _set(6, i, dark);
      _set(i, 6, dark);
    }
  }

  void _placeAlignmentPatterns() {
    final centers = _alignmentCenters[version]!;
    for (final row in centers) {
      for (final col in centers) {
        // Les trois coins portent déjà un motif de recherche.
        if (row == 6 && col == 6) continue;
        if (row == 6 && col == size - 7) continue;
        if (row == size - 7 && col == 6) continue;
        for (var r = -2; r <= 2; r++) {
          for (var c = -2; c <= 2; c++) {
            final edge = r.abs() == 2 || c.abs() == 2;
            final center = r == 0 && c == 0;
            _set(row + r, col + c, edge || center);
          }
        }
      }
    }
  }

  /// Réserve l'emplacement de l'information de format, écrite après le choix
  /// du masque. Deux copies : l'une autour du coin supérieur gauche, l'autre
  /// répartie entre le coin supérieur droit et le coin inférieur gauche.
  void _reserveFormatAreas() {
    for (var i = 0; i <= 8; i++) {
      _reserve(8, i);
      _reserve(i, 8);
    }
    for (var i = 0; i < 8; i++) {
      _reserve(8, size - 1 - i);
    }
    for (var i = 1; i <= 7; i++) {
      _reserve(size - i, 8);
    }
  }

  void _placeVersionInformation() {
    final bits = QrCode.versionInformation(version);
    for (var i = 0; i < 18; i++) {
      final dark = ((bits >> i) & 1) == 1;
      // Bloc de 3×6 en bas à gauche, et son symétrique en haut à droite.
      _set(size - 11 + (i % 3), i ~/ 3, dark);
      _set(i ~/ 3, size - 11 + (i % 3), dark);
    }
  }

  /// Parcours en zigzag de la norme : colonnes par paires, de droite à
  /// gauche, alternativement vers le haut et vers le bas, la colonne 6 (motif
  /// de synchronisation vertical) étant sautée.
  void placeData(List<int> codewords) {
    var bitIndex = 0;
    var upward = true;

    for (var right = size - 1; right >= 1; right -= 2) {
      final rightColumn = right <= 6 ? right - 1 : right;
      for (var step = 0; step < size; step++) {
        final row = upward ? size - 1 - step : step;
        for (var offset = 0; offset < 2; offset++) {
          final col = rightColumn - offset;
          if (col < 0 || _reserved[row][col]) continue;
          var dark = false;
          if (bitIndex < codewords.length * 8) {
            final byte = codewords[bitIndex ~/ 8];
            dark = ((byte >> (7 - bitIndex % 8)) & 1) == 1;
          }
          modules[row][col] = dark;
          bitIndex++;
        }
      }
      upward = !upward;
    }
  }

  /// Applique les huit masques, garde celui qui obtient la plus faible
  /// pénalité, et écrit l'information de format correspondante.
  int applyBestMask() {
    final data = [
      for (final row in modules) List<bool>.from(row),
    ];

    var bestMask = 0;
    var bestPenalty = -1;
    List<List<bool>>? bestModules;

    for (var mask = 0; mask < 8; mask++) {
      final candidate = [
        for (final row in data) List<bool>.from(row),
      ];
      for (var r = 0; r < size; r++) {
        for (var c = 0; c < size; c++) {
          if (_reserved[r][c]) continue;
          if (_maskCondition(mask, r, c)) candidate[r][c] = !candidate[r][c];
        }
      }
      _writeFormatInformation(candidate, mask);

      final penalty = _penalty(candidate);
      if (bestPenalty < 0 || penalty < bestPenalty) {
        bestPenalty = penalty;
        bestMask = mask;
        bestModules = candidate;
      }
    }

    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        modules[r][c] = bestModules![r][c];
      }
    }
    return bestMask;
  }

  bool _maskCondition(int mask, int row, int col) {
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

  /// Écrit les deux copies de l'information de format, au placement exact de
  /// la norme (ISO/IEC 18004, figure 25).
  ///
  /// Ce bloc a longtemps été écrit en miroir de la diagonale : les bits de
  /// poids faible de la première copie couraient le long de la *ligne* 8 au
  /// lieu de la *colonne* 8, et la seconde copie se partageait en 7 + 8 bits
  /// au lieu de 8 + 7. Or l'information de format est la première chose que
  /// lit un décodeur : il y trouvait un mot absent de la table de la norme et
  /// renonçait sans même regarder les données. C'est la cause exacte de « la
  /// caméra voit le code mais rien n'est jamais décodé » — tout le reste de la
  /// matrice était pourtant juste.
  void _writeFormatInformation(List<List<bool>> target, int mask) {
    final bits = QrCode.formatInformation(QrCode.errorCorrectionLevel, mask);
    bool bit(int i) => ((bits >> i) & 1) == 1;

    // Première copie : les six bits de poids faible descendent la colonne 8,
    // puis le coude en (7, 8) et (8, 8), et les six de poids fort remontent la
    // ligne 8 vers la gauche.
    for (var i = 0; i <= 5; i++) {
      target[i][8] = bit(i);
    }
    target[7][8] = bit(6);
    target[8][8] = bit(7);
    target[8][7] = bit(8);
    for (var i = 9; i < 15; i++) {
      target[8][14 - i] = bit(i);
    }

    // Seconde copie, répartie sur les deux autres coins : c'est elle qui sauve
    // la lecture quand le premier coin est abîmé. Les huit bits de poids
    // faible longent la ligne 8 depuis le bord droit, les sept autres
    // descendent la colonne 8 jusqu'au coin inférieur gauche — le module
    // sombre de (taille-8, 8) restant en dehors.
    for (var i = 0; i <= 7; i++) {
      target[8][size - 1 - i] = bit(i);
    }
    for (var i = 8; i < 15; i++) {
      target[size - 15 + i][8] = bit(i);
    }
  }

  /// Pénalités de la norme : les quatre règles qui écartent les matrices
  /// difficiles à lire (longues plages, carrés uniformes, faux motifs de
  /// recherche, déséquilibre clair/sombre).
  int _penalty(List<List<bool>> m) {
    var score = 0;

    // Règle 1 : plages de cinq modules ou plus de même teinte.
    for (var i = 0; i < size; i++) {
      var runRow = 1;
      var runCol = 1;
      for (var j = 1; j < size; j++) {
        runRow = m[i][j] == m[i][j - 1] ? runRow + 1 : 1;
        if (runRow == 5) {
          score += 3;
        } else if (runRow > 5) {
          score += 1;
        }
        runCol = m[j][i] == m[j - 1][i] ? runCol + 1 : 1;
        if (runCol == 5) {
          score += 3;
        } else if (runCol > 5) {
          score += 1;
        }
      }
    }

    // Règle 2 : carrés de 2×2 uniformes.
    for (var r = 0; r < size - 1; r++) {
      for (var c = 0; c < size - 1; c++) {
        final v = m[r][c];
        if (m[r][c + 1] == v && m[r + 1][c] == v && m[r + 1][c + 1] == v) {
          score += 3;
        }
      }
    }

    // Règle 3 : la signature 1:1:3:1:1 suivie ou précédée de quatre modules
    // clairs, qu'un lecteur prendrait pour un motif de recherche.
    const pattern = [
      true, false, true, true, true, false, true,
      false, false, false, false,
    ];
    const reversed = [
      false, false, false, false,
      true, false, true, true, true, false, true,
    ];
    for (var i = 0; i < size; i++) {
      for (var j = 0; j <= size - 11; j++) {
        var matchRow = true;
        var matchRowReversed = true;
        var matchCol = true;
        var matchColReversed = true;
        for (var k = 0; k < 11; k++) {
          if (m[i][j + k] != pattern[k]) matchRow = false;
          if (m[i][j + k] != reversed[k]) matchRowReversed = false;
          if (m[j + k][i] != pattern[k]) matchCol = false;
          if (m[j + k][i] != reversed[k]) matchColReversed = false;
        }
        if (matchRow) score += 40;
        if (matchRowReversed) score += 40;
        if (matchCol) score += 40;
        if (matchColReversed) score += 40;
      }
    }

    // Règle 4 : écart à la moitié de modules sombres.
    var dark = 0;
    for (final row in m) {
      for (final module in row) {
        if (module) dark++;
      }
    }
    final percent = dark * 100 ~/ (size * size);
    final deviation = (percent - 50).abs() ~/ 5;
    score += deviation * 10;

    return score;
  }

  void _set(int row, int col, bool dark) {
    if (row < 0 || col < 0 || row >= size || col >= size) return;
    modules[row][col] = dark;
    _reserved[row][col] = true;
  }

  void _reserve(int row, int col) {
    if (row < 0 || col < 0 || row >= size || col >= size) return;
    _reserved[row][col] = true;
  }
}
