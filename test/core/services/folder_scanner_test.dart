import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/models/media_type.dart';
import 'package:omnia_mobile/core/services/folder_scanner.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('omnia_scan_');
  });

  tearDown(() {
    // Sous Windows, un isolate qui vient de se terminer peut encore tenir un
    // handle sur le dossier : un échec de suppression ne doit pas faire
    // échouer le test.
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Le dossier temporaire sera nettoyé par le système.
    }
  });

  /// Écriture synchrone : aucune future en attente ne peut survivre au test.
  void write(String name, {int bytes = 4}) {
    final file = File(p.join(dir.path, name));
    file.createSync(recursive: true);
    file.writeAsBytesSync(List<int>.filled(bytes, 0x41));
  }

  group('IsolateFolderScanner', () {
    test('ne retient que les fichiers lisibles', () async {
      write('film.mkv');
      write('chanson.mp3');
      write('manuel.pdf');
      write('notes.md');
      write('archive.zip');
      write('programme.exe');

      final files = await const IsolateFolderScanner().scan(dir.path);
      final names = files.map((f) => f.name).toList()..sort();

      expect(names, ['chanson.mp3', 'film.mkv', 'manuel.pdf', 'notes.md']);
    });

    test('renseigne le type, la taille et la date', () async {
      write('film.mkv', bytes: 128);
      final files = await const IsolateFolderScanner().scan(dir.path);

      expect(files.single.type, MediaType.video);
      expect(files.single.size, 128);
      expect(files.single.modifiedAt, isNotNull);
    });

    test('ignore les sous-dossiers et ne descend pas dedans', () async {
      write('racine.mkv');
      Directory(p.join(dir.path, 'saison2')).createSync();
      write(p.join('saison2', 'cache.mkv'));

      final files = await const IsolateFolderScanner().scan(dir.path);
      expect(files.map((f) => f.name).toList(), ['racine.mkv']);
    });

    test('dossier vide → liste vide', () async {
      expect(await const IsolateFolderScanner().scan(dir.path), isEmpty);
    });

    test('dossier inexistant → liste vide, sans exception', () async {
      final files =
          await const IsolateFolderScanner().scan(p.join(dir.path, 'absent'));
      expect(files, isEmpty);
    });

    test('les chemins retournés sont utilisables tels quels', () async {
      write('film.mkv');
      final files = await const IsolateFolderScanner().scan(dir.path);
      expect(files, hasLength(1));
      expect(File(files.single.path).existsSync(), isTrue);
    });
  });

  group('scanFolderSync', () {
    test('retourne du JSON simple, franchissable par un isolate', () {
      write('film.mkv');
      final raw = scanFolderSync(dir.path);
      expect(raw, hasLength(1));
      expect(raw.single['type'], 'video');
      expect(raw.single['path'], isA<String>());
      expect(raw.single['size'], isA<int>());
    });

    test('gros dossier : les 1000 fichiers sont vus', () {
      for (var i = 0; i < 1000; i++) {
        write('ep$i.mkv');
      }
      // On mesure le parcours seul, sans le coût de création des fichiers.
      final raw = scanFolderSync(dir.path);
      expect(raw, hasLength(1000));
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
