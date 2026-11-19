import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/ui/screens/folders_tab.dart';
import 'package:omnia_mobile/ui/widgets/file_actions.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory racine;

  setUp(() {
    racine = Directory.systemTemp.createTempSync('omnia_dossiers_');
    File(p.join(racine.path, 'Zèbre.mp4')).writeAsStringSync('v');
    File(p.join(racine.path, 'album.mp3')).writeAsStringSync('a');
    File(p.join(racine.path, 'notes.pdf')).writeAsStringSync('d');
    File(p.join(racine.path, 'installeur.apk')).writeAsStringSync('x');
    File(p.join(racine.path, '.cache.mp4')).writeAsStringSync('h');
    Directory(p.join(racine.path, 'Vacances')).createSync();
    Directory(p.join(racine.path, '.cachés')).createSync();
    File(p.join(racine.path, 'Vacances', 'plage.mp4')).writeAsStringSync('v');
    Directory(p.join(racine.path, 'Vacances', 'Jour 2')).createSync();
    File(p.join(racine.path, 'Vacances', 'Jour 2', 'plage du soir.mkv'))
        .writeAsStringSync('v');
  });

  tearDown(() {
    try {
      racine.deleteSync(recursive: true);
    } on FileSystemException {
      // Le système fera le ménage.
    }
  });

  group('Contenu d’un dossier', () {
    test('les dossiers d’abord, puis ce qu’OMNIA sait lire, par ordre alphabétique', () async {
      final noms = (await listFolder(racine.path)).map((e) => e.name).toList();
      expect(noms, ['Vacances', 'album.mp3', 'notes.pdf', 'Zèbre.mp4']);
    });

    test('ni fichiers cachés, ni fichiers qu’OMNIA ne sait pas ouvrir', () async {
      final noms = (await listFolder(racine.path)).map((e) => e.name).toList();
      expect(noms, isNot(contains('.cache.mp4')));
      expect(noms, isNot(contains('.cachés')));
      expect(noms, isNot(contains('installeur.apk')));
    });
  });

  group('Recherche', () {
    test('elle descend dans les sous-dossiers', () async {
      final trouves = await searchFolder(racine.path, 'plage');
      final noms = trouves.map((e) => e.name).toSet();
      expect(noms, {'plage.mp4', 'plage du soir.mkv'});
    });

    test('sans distinction de majuscules, et dossiers compris', () async {
      final trouves = await searchFolder(racine.path, 'vacances');
      expect(trouves.single.isDirectory, isTrue);
    });

    test('elle s’arrête au nombre de résultats demandé', () async {
      final trouves = await searchFolder(racine.path, 'a', maxResults: 2);
      expect(trouves, hasLength(2));
    });
  });

  group('Stockages', () {
    test('la carte mémoire donnée par Android apparaît, sous son nom', () {
      final racines = mergeStorageRoots(
        [
          {'path': internalStoragePath, 'label': 'Stockage interne partagé', 'removable': false},
          {'path': '/storage/1A2B-3C4D', 'label': 'Carte SD SanDisk', 'removable': true},
          {'path': '/storage/9F00-0001', 'label': '', 'removable': true},
        ],
        const [],
      );
      expect(racines.map((r) => r.name), [
        'Mémoire interne',
        'Carte SD SanDisk',
        'Carte mémoire',
      ]);
    });

    test('un volume trouvé deux fois ne compte qu’une fois', () {
      final racines = mergeStorageRoots(
        [
          {'path': '/storage/1A2B-3C4D', 'label': 'Carte SD', 'removable': true},
        ],
        const [
          FolderEntry(path: internalStoragePath, isDirectory: true, label: 'Mémoire interne'),
          FolderEntry(path: '/storage/1A2B-3C4D', isDirectory: true, label: 'Carte (1A2B-3C4D)'),
          FolderEntry(path: '/storage/CLE-USB', isDirectory: true, label: 'Carte (CLE-USB)'),
        ],
      );
      expect(racines.map((r) => r.path), [
        internalStoragePath,
        '/storage/1A2B-3C4D',
        '/storage/CLE-USB',
      ]);
      expect(racines[1].name, 'Carte SD');
    });

    test('le chemin se dit avec le nom du stockage', () {
      final racines = mergeStorageRoots(
        [
          {'path': '/storage/1A2B-3C4D', 'label': 'Carte SD', 'removable': true},
        ],
        const [],
      );
      expect(describeLocation('/storage/1A2B-3C4D/Films/Été', racines), 'Carte SD/Films/Été');
      expect(describeLocation('$internalStoragePath/Download', racines), 'Mémoire interne/Download');
      expect(storageRootOf('/storage/1A2B-3C4D', racines)?.name, 'Carte SD');
      // Un préfixe de nom n'est pas un dossier parent.
      expect(storageRootOf('/storage/1A2B-3C4DX/a', racines), isNull);
    });
  });

  group('Tailles et dates', () {
    test('des tailles lisibles, à la française', () {
      expect(formatFileSize(512), '512 o');
      expect(formatFileSize(1536), '1,5 Ko');
      expect(formatFileSize(2400000), '2,3 Mo');
      expect(formatFileSize(1500 * 1024 * 1024), '1,5 Go');
    });

    test('une date avec son heure', () {
      expect(formatFileDate(DateTime(2026, 11, 7, 10, 4)), '7/11/2026 à 10:04');
    });
  });
}
