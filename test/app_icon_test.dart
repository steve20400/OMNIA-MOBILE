import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Test des icônes OMNIA Mobile générées par tool/make_icon.py.
void main() {
  group('Icône Mobile OMNIA', () {
    test('les ressources PNG existent pour toutes les résolutions requises', () {
      for (final size in [16, 24, 32, 48, 64, 128, 256]) {
        final file = File('assets/icons/app_icon_$size.png');
        expect(file.existsSync(), isTrue, reason: 'assets/icons/app_icon_$size.png doit exister');
        final bytes = file.readAsBytesSync();
        expect(bytes.length, greaterThan(0));
        final img = _decodePng(bytes);
        expect(img.width, size);
        expect(img.height, size);
      }
    });

    test('coins arrondis transparents et centre opaque (256 px)', () {
      final bytes = File('assets/icons/app_icon_256.png').readAsBytesSync();
      final img = _decodePng(bytes);
      expect(img.alpha(0, 0), 0);
      expect(img.alpha(128, 128), 255);
    });
  });
}

/// Image RGBA 8 bits, lue pixel par pixel.
class _Rgba {
  _Rgba(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final Uint8List pixels;

  int _index(int x, int y) => (y * width + x) * 4;

  int red(int x, int y) => pixels[_index(x, y)];

  int alpha(int x, int y) => pixels[_index(x, y) + 3];

  String hex(int x, int y) {
    final i = _index(x, y);
    final channels = pixels.sublist(i, i + 4).map((c) => c.toRadixString(16).padLeft(2, '0'));
    return '#${channels.join().toUpperCase()}';
  }
}

/// Décode un PNG RGBA 8 bits non entrelacé.
_Rgba _decodePng(Uint8List png) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < signature.length; i++) {
    if (png[i] != signature[i]) throw const FormatException('signature PNG absente');
  }
  final data = ByteData.sublistView(png);
  var width = 0;
  var height = 0;
  final compressed = <int>[];
  var offset = 8;
  while (offset + 8 <= png.length) {
    final length = data.getUint32(offset);
    final type = String.fromCharCodes(png, offset + 4, offset + 8);
    final body = Uint8List.sublistView(png, offset + 8, offset + 8 + length);
    if (type == 'IHDR') {
      width = data.getUint32(offset + 8);
      height = data.getUint32(offset + 12);
      if (body[8] != 8 || body[9] != 6 || body[12] != 0) {
        throw const FormatException('PNG RGBA 8 bits attendu');
      }
    } else if (type == 'IDAT') {
      compressed.addAll(body);
    } else if (type == 'IEND') {
      break;
    }
    offset += 12 + length;
  }
  final raw = zlib.decode(compressed);
  final stride = width * 4;
  final pixels = Uint8List(height * stride);
  var src = 0;
  for (var y = 0; y < height; y++) {
    final filter = raw[src++];
    for (var x = 0; x < stride; x++) {
      final i = y * stride + x;
      final left = x >= 4 ? pixels[i - 4] : 0;
      final up = y > 0 ? pixels[i - stride] : 0;
      final upLeft = x >= 4 && y > 0 ? pixels[i - stride - 4] : 0;
      final value = raw[src++];
      pixels[i] = switch (filter) {
        0 => value,
        1 => value + left,
        2 => value + up,
        3 => value + (left + up) ~/ 2,
        4 => value + _paeth(left, up, upLeft),
        _ => throw FormatException('filtre PNG inconnu : $filter'),
      };
    }
  }
  return _Rgba(width, height, pixels);
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}
