import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/controllers/media_router.dart';
import 'package:omnia_mobile/core/models/media_type.dart';
import 'package:omnia_mobile/core/utils/media_sniffer.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Téléchargements inachevés', () {
    test('la marque du navigateur s’efface, l’extension d’origine reste', () {
      expect(withoutPartialSuffix('/dl/Film.2024.mp4.part'), '/dl/Film.2024.mp4');
      expect(withoutPartialSuffix('/dl/clip.webm.crdownload'), '/dl/clip.webm');
      expect(withoutPartialSuffix('/dl/clip.f137.mp4.part-Frag12'), '/dl/clip.f137.mp4');
      expect(withoutPartialSuffix('/dl/album.flac.!qb'), '/dl/album.flac');
      expect(withoutPartialSuffix('/dl/film.mkv'), '/dl/film.mkv');
      expect(isPartialDownload('/dl/a.mkv.PART'), isTrue);
      expect(isPartialDownload('/dl/a.mkv'), isFalse);
    });

    test('un fichier partiel garde le type de son extension d’origine', () {
      expect(MediaRouter.typeForPath('/dl/Film.mp4.part'), MediaType.video);
      expect(MediaRouter.typeForPath('/dl/chanson.mp3.crdownload'), MediaType.audio);
      expect(MediaRouter.isSupported('/dl/serie.mkv.part-Frag3'), isTrue);
    });
  });

  group('Signatures', () {
    List<int> ascii(String text) => text.codeUnits;
    List<int> pad(List<int> head) => [...head, ...List.filled(256 - head.length, 0)];

    test('vidéo, son, image et document se reconnaissent à leurs premiers octets', () {
      expect(sniffMediaType(pad([0x1A, 0x45, 0xDF, 0xA3])), MediaType.video);
      expect(sniffMediaType(pad([0, 0, 0, 0x20, ...ascii('ftypisom')])), MediaType.video);
      expect(sniffMediaType(pad([0, 0, 0, 0x20, ...ascii('ftypM4A ')])), MediaType.audio);
      expect(sniffMediaType(pad([...ascii('RIFF'), 0, 0, 0, 0, ...ascii('AVI ')])), MediaType.video);
      expect(sniffMediaType(pad([...ascii('RIFF'), 0, 0, 0, 0, ...ascii('WAVE')])), MediaType.audio);
      expect(sniffMediaType(pad(ascii('ID3'))), MediaType.audio);
      expect(sniffMediaType(pad([0xFF, 0xFB, 0x90, 0x00])), MediaType.audio);
      expect(sniffMediaType(pad([0xFF, 0xD8, 0xFF, 0xE0])), MediaType.image);
      expect(sniffMediaType(pad(ascii('%PDF-1.7'))), MediaType.pdf);
      final ts = List.filled(256, 0)
        ..[0] = 0x47
        ..[188] = 0x47;
      expect(sniffMediaType(ts), MediaType.video);
    });

    test('des octets quelconques ne sont pas pris pour un média', () {
      expect(sniffMediaType(pad(ascii('Bonjour'))), isNull);
      expect(sniffMediaType(const []), isNull);
    });

    test('un téléchargement de Chrome sans extension d’origine s’ouvre quand même', () {
      final dir = Directory.systemTemp.createTempSync('omnia_partiel_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File(p.join(dir.path, 'Non confirmé 123456.crdownload'))
        ..writeAsBytesSync(pad([0x1A, 0x45, 0xDF, 0xA3, 0x01]));
      expect(MediaRouter.typeForPath(file.path), MediaType.video);
    });
  });
}
