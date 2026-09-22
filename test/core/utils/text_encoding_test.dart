import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/utils/text_encoding.dart';

void main() {
  group('decodeText', () {
    test('vide', () {
      final d = decodeText(Uint8List(0));
      expect(d.text, '');
      expect(d.encoding, 'UTF-8');
    });

    test('UTF-8 sans BOM, avec accents', () {
      final d = decodeText(Uint8List.fromList(utf8.encode('Élève — « été »')));
      expect(d.text, 'Élève — « été »');
      expect(d.encoding, 'UTF-8');
    });

    test('UTF-8 avec BOM : la marque est retirée', () {
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('bonjour')]);
      final d = decodeText(bytes);
      expect(d.text, 'bonjour');
      expect(d.encoding, 'UTF-8');
    });

    test('Latin-1 / Windows-1252 : accents et euro', () {
      // « café » en Latin-1 : é = 0xE9 ; € = 0x80 en Windows-1252.
      final d = decodeText(Uint8List.fromList([0x63, 0x61, 0x66, 0xE9, 0x20, 0x80]));
      expect(d.text, 'café €');
      expect(d.encoding, 'Windows-1252');
    });

    test('UTF-16 LE avec BOM', () {
      final units = 'été'.codeUnits;
      final bytes = <int>[0xFF, 0xFE];
      for (final u in units) {
        bytes.add(u & 0xFF);
        bytes.add(u >> 8);
      }
      final d = decodeText(Uint8List.fromList(bytes));
      expect(d.text, 'été');
      expect(d.encoding, 'UTF-16 LE');
    });

    test('UTF-16 BE avec BOM', () {
      final units = 'été'.codeUnits;
      final bytes = <int>[0xFE, 0xFF];
      for (final u in units) {
        bytes.add(u >> 8);
        bytes.add(u & 0xFF);
      }
      final d = decodeText(Uint8List.fromList(bytes));
      expect(d.text, 'été');
      expect(d.encoding, 'UTF-16 BE');
    });

    test('ASCII pur est de l’UTF-8', () {
      final d = decodeText(Uint8List.fromList('hello'.codeUnits));
      expect(d.text, 'hello');
      expect(d.encoding, 'UTF-8');
    });

    test('des octets arbitraires s’ouvrent quand même', () {
      // 0x81, 0x8D… ne sont pas définis en Windows-1252 : repli Latin-1.
      final d = decodeText(Uint8List.fromList(List.generate(256, (i) => i)));
      expect(d.text.length, 256);
      expect(d.encoding, 'ISO-8859-1');
    });

    test('Windows-1252 valide reste reconnu comme tel', () {
      final d = decodeText(Uint8List.fromList([0x93, 0x63, 0x61, 0x66, 0xE9, 0x94]));
      expect(d.text, '“café”');
      expect(d.encoding, 'Windows-1252');
    });
  });

  test('normaliseLineEndings', () {
    expect(normaliseLineEndings('a\r\nb\rc\nd'), 'a\nb\nc\nd');
  });
}
