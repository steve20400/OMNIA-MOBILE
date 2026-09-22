import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';

/// Résultat du décodage d'un fichier texte.
class DecodedText {
  const DecodedText({required this.text, required this.encoding});

  final String text;

  /// Nom lisible de l'encodage retenu (« UTF-8 », « Windows-1252 »…).
  final String encoding;
}

/// Décode des octets en texte en devinant l'encodage.
///
/// Stratégie, du plus sûr au moins sûr :
/// 1. marque d'ordre d'octets (BOM) UTF-8, UTF-16 LE/BE ;
/// 2. UTF-8 strict : s'il décode sans erreur, c'est presque à coup sûr lui ;
/// 3. sinon Windows-1252, sur-ensemble de Latin-1 le plus courant sur les
///    fichiers venus de Windows (guillemets typographiques, €, œ…).
///
/// Aucun contenu n'est jamais rejeté : au pire, quelques caractères sont
/// approximatifs, mais le fichier s'ouvre.
DecodedText decodeText(Uint8List bytes) {
  if (bytes.isEmpty) return const DecodedText(text: '', encoding: 'UTF-8');

  // BOM UTF-8.
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return DecodedText(
      text: utf8.decode(bytes.sublist(3), allowMalformed: true),
      encoding: 'UTF-8',
    );
  }

  // BOM UTF-16.
  if (bytes.length >= 2) {
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return DecodedText(text: _decodeUtf16(bytes.sublist(2), bigEndian: false), encoding: 'UTF-16 LE');
    }
    if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return DecodedText(text: _decodeUtf16(bytes.sublist(2), bigEndian: true), encoding: 'UTF-16 BE');
    }
  }

  try {
    return DecodedText(text: utf8.decode(bytes), encoding: 'UTF-8');
  } on FormatException {
    // Pas de l'UTF-8 valide : Latin-1 étendu.
  }

  try {
    return DecodedText(text: windows1252.decode(bytes), encoding: 'Windows-1252');
  } on Object {
    // Cinq positions (0x81, 0x8D, 0x8F, 0x90, 0x9D) ne sont pas définies en
    // Windows-1252 et font échouer le décodeur. Latin-1 pur, lui, accepte
    // tout octet : le fichier s'ouvre, quitte à afficher un caractère de
    // contrôle à ces endroits.
    return DecodedText(text: latin1.decode(bytes), encoding: 'ISO-8859-1');
  }
}

String _decodeUtf16(List<int> bytes, {required bool bigEndian}) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(bigEndian ? (bytes[i] << 8) | bytes[i + 1] : (bytes[i + 1] << 8) | bytes[i]);
  }
  return String.fromCharCodes(units);
}

/// Normalise les fins de ligne pour l'affichage (`\r\n` et `\r` → `\n`).
String normaliseLineEndings(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
