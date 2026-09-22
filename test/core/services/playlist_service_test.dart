import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/commands/player_command.dart';
import 'package:omnia_mobile/core/commands/player_command_bus.dart';
import 'package:omnia_mobile/core/models/end_of_playback_mode.dart';
import 'package:omnia_mobile/core/models/media_file.dart';
import 'package:omnia_mobile/core/models/media_type.dart';
import 'package:omnia_mobile/core/models/playlist_sort.dart';
import 'package:omnia_mobile/core/services/folder_scanner.dart';
import 'package:omnia_mobile/core/services/history_store.dart';
import 'package:omnia_mobile/core/services/playlist_service.dart';
import 'package:omnia_mobile/core/services/settings_store.dart';

/// Générateur déterministe, pour tester la lecture aléatoire.
class _FixedRandom implements Random {
  _FixedRandom(this.values);
  final List<int> values;
  int _i = 0;

  @override
  int nextInt(int max) => values[_i++ % values.length] % max;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

MediaFile file(String name, MediaType type, {int? size}) =>
    MediaFile(path: '/serie/$name', type: type, size: size);

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  final folderFiles = <String, List<MediaFile>>{
    '/serie': [
      file('ep10.mkv', MediaType.video, size: 300),
      file('ep2.mkv', MediaType.video, size: 100),
      file('ep1.mkv', MediaType.video, size: 200),
      file('bande-son.mp3', MediaType.audio, size: 50),
      file('resume.pdf', MediaType.pdf, size: 20),
    ],
    '/vide': [],
  };

  late PlayerCommandBus bus;
  late FakeFolderScanner scanner;
  late MemoryHistoryStore history;
  late PlaylistService service;

  setUp(() {
    bus = PlayerCommandBus();
    scanner = FakeFolderScanner(folderFiles);
    history = MemoryHistoryStore();
    service = PlaylistService(bus: bus, scanner: scanner, history: history);
  });

  tearDown(() async {
    await service.dispose();
    await bus.dispose();
  });

  group('Scan du dossier', () {
    test('ouvrir un fichier scanne son dossier parent', () async {
      await service.ensureFolderFor('/serie/ep1.mkv');
      expect(scanner.scannedFolders, ['/serie']);
      expect(service.state.entries, hasLength(5));
      expect(service.state.folder, '/serie');
      expect(service.state.scanning, isFalse);
    });

    test('le tri naturel est appliqué par défaut', () async {
      await service.scanFolder('/serie');
      expect(service.state.visiblePaths.map((p) => p.split('/').last), [
        'bande-son.mp3',
        'ep1.mkv',
        'ep2.mkv',
        'ep10.mkv',
        'resume.pdf',
      ]);
    });

    test('rouvrir un fichier du même dossier ne relance pas le scan', () async {
      await service.ensureFolderFor('/serie/ep1.mkv');
      await service.ensureFolderFor('/serie/ep2.mkv');
      expect(scanner.scannedFolders, ['/serie']);
    });

    test('un fichier absent du scan est ajouté à la liste', () async {
      await service.ensureFolderFor('/serie/ep1.mkv');
      await service.ensureFolderFor('/serie/nouveau.mkv');
      expect(service.state.entries, hasLength(6));
      expect(service.state.visiblePaths, contains('/serie/nouveau.mkv'));
    });

    test('un fichier non lisible n’est pas ajouté', () async {
      await service.ensureFolderFor('/serie/ep1.mkv');
      await service.ensureFolderFor('/serie/archive.zip');
      expect(service.state.entries, hasLength(5));
    });

    test('l’état signale le scan en cours', () async {
      final slow = PlaylistService(
        bus: bus,
        scanner: FakeFolderScanner(folderFiles, delay: const Duration(milliseconds: 50)),
      );
      final states = <bool>[];
      final sub = slow.stream.listen((s) => states.add(s.scanning));

      final future = slow.scanFolder('/serie');
      await settle();
      expect(states.first, isTrue);
      await future;
      // Le flux est diffusé de façon asynchrone : on laisse passer l'événement
      // de fin avant de l'observer.
      await settle();
      expect(states.last, isFalse);

      await sub.cancel();
      await slow.dispose();
    });

    test('un scan dépassé n’écrase pas le résultat du plus récent', () async {
      final slow = PlaylistService(
        bus: bus,
        scanner: FakeFolderScanner(folderFiles, delay: const Duration(milliseconds: 60)),
      );
      final first = slow.scanFolder('/serie');
      final second = slow.scanFolder('/vide');
      await Future.wait([first, second]);

      expect(slow.state.folder, '/vide');
      expect(slow.state.entries, isEmpty);
      await slow.dispose();
    });

    test('dossier vide : liste vide, sans erreur', () async {
      await service.scanFolder('/vide');
      expect(service.state.entries, isEmpty);
      expect(service.state.scanning, isFalse);
    });

    test('changer de dossier vide la liste dès le début du scan', () async {
      final slow = PlaylistService(
        bus: bus,
        scanner: FakeFolderScanner(folderFiles, delay: const Duration(milliseconds: 60)),
      );
      await slow.scanFolder('/serie');
      expect(slow.state.entries, hasLength(5));

      final future = slow.scanFolder('/vide');
      await settle();
      // Pendant le scan du nouveau dossier, les anciens fichiers ne doivent
      // plus être affichés sous le nom du nouveau dossier.
      expect(slow.state.folder, '/vide');
      expect(slow.state.entries, isEmpty);

      await future;
      await slow.dispose();
    });

    test('rescanner le même dossier n’efface pas la liste affichée', () async {
      final slow = PlaylistService(
        bus: bus,
        scanner: FakeFolderScanner(folderFiles, delay: const Duration(milliseconds: 60)),
      );
      await slow.scanFolder('/serie');

      final future = slow.scanFolder('/serie');
      await settle();
      expect(slow.state.entries, hasLength(5));

      await future;
      await slow.dispose();
    });
  });

  group('Persistance et changement de dossier', () {
    test('le tri est relu au démarrage et sauvegardé à chaque changement', () async {
      final store = MemorySettingsStore();
      await store.setPlaylistSort('size', true);

      final ownBus = PlayerCommandBus();
      final restored = PlaylistService(bus: ownBus, scanner: scanner, settings: store);
      expect(restored.state.sort, PlaylistSort.size);
      expect(restored.state.descending, isTrue);

      ownBus.dispatch(const SetPlaylistSort(PlaylistSort.date));
      await settle();
      expect(store.playlistSort, 'date');
      expect(store.playlistDescending, isFalse);

      await restored.dispose();
      await ownBus.dispose();
    });

    test('un tri inconnu en mémoire retombe sur le nom', () {
      final store = MemorySettingsStore();
      store.setPlaylistSort('bidon', false);
      final restored = PlaylistService(bus: PlayerCommandBus(), scanner: scanner, settings: store);
      expect(restored.state.sort, PlaylistSort.name);
    });

    test('changer de dossier efface la recherche mais garde tri et filtre', () async {
      await service.scanFolder('/serie');
      bus.dispatch(const SetPlaylistQuery('ep'));
      bus.dispatch(const SetPlaylistSort(PlaylistSort.size));
      bus.dispatch(const SetPlaylistFilter(PlaylistFilter.video));
      await settle();

      await service.scanFolder('/vide');
      expect(service.state.query, isEmpty);
      expect(service.state.sort, PlaylistSort.size);
      expect(service.state.filter, PlaylistFilter.video);
    });

    test('rescanner le même dossier conserve la recherche', () async {
      await service.scanFolder('/serie');
      bus.dispatch(const SetPlaylistQuery('ep'));
      await settle();
      await service.scanFolder('/serie');
      expect(service.state.query, 'ep');
    });
  });

  group('Fichiers non ouvrables', () {
    late PlaylistService filtered;

    setUp(() async {
      filtered = PlaylistService(
        bus: PlayerCommandBus(),
        scanner: FakeFolderScanner(folderFiles),
        // Seuls les médias audio/vidéo sont ouvrables, comme en Phase 2.
        isPlayable: (path) => !path.endsWith('.pdf'),
      );
      await filtered.scanFolder('/serie');
    });

    tearDown(() => filtered.dispose());

    test('le panneau les affiche quand même', () {
      expect(filtered.state.visiblePaths, contains('/serie/resume.pdf'));
    });

    test('la navigation les enjambe', () {
      filtered.setCurrent('/serie/ep10.mkv'); // juste avant resume.pdf
      expect(filtered.nextPath(), '/serie/bande-son.mp3');
      filtered.setCurrent('/serie/bande-son.mp3');
      expect(filtered.previousPath(), '/serie/ep10.mkv');
    });

    test('la fin de lecture les enjambe aussi', () {
      filtered.setCurrent('/serie/ep10.mkv');
      expect(filtered.nextForEndMode(EndOfPlaybackMode.next), isNull);
      expect(
        filtered.nextForEndMode(EndOfPlaybackMode.loopFolder),
        '/serie/bande-son.mp3',
      );
    });
  });

  group('Commandes du panneau', () {
    setUp(() => service.scanFolder('/serie'));

    test('changer le tri', () async {
      await service.scanFolder('/serie');
      bus.dispatch(const SetPlaylistSort(PlaylistSort.size));
      await settle();
      expect(service.state.sort, PlaylistSort.size);
      expect(service.state.visiblePaths.first, '/serie/resume.pdf');

      bus.dispatch(const SetPlaylistSort(PlaylistSort.size, descending: true));
      await settle();
      expect(service.state.visiblePaths.first, '/serie/ep10.mkv');
    });

    test('filtrer par type', () async {
      await service.scanFolder('/serie');
      bus.dispatch(const SetPlaylistFilter(PlaylistFilter.audio));
      await settle();
      expect(service.state.visiblePaths, ['/serie/bande-son.mp3']);
    });

    test('rechercher', () async {
      await service.scanFolder('/serie');
      bus.dispatch(const SetPlaylistQuery('ep1'));
      await settle();
      expect(service.state.visiblePaths, ['/serie/ep1.mkv', '/serie/ep10.mkv']);
    });

    test('retirer un élément ne touche pas au disque', () async {
      await service.scanFolder('/serie');
      bus.dispatch(const RemoveFromPlaylist('/serie/ep2.mkv'));
      await settle();
      expect(service.state.entries, hasLength(4));
      expect(service.state.visiblePaths, isNot(contains('/serie/ep2.mkv')));
    });

    test('relancer le scan', () async {
      await service.scanFolder('/serie');
      scanner.scannedFolders.clear();
      bus.dispatch(const RescanFolder());
      await settle();
      expect(scanner.scannedFolders, ['/serie']);
    });

    test('relancer le scan sans dossier ouvert ne fait rien', () async {
      // Bus dédié : le service du `setUp` écoute déjà le bus partagé et a,
      // lui, un dossier ouvert.
      final ownBus = PlayerCommandBus();
      final ownScanner = FakeFolderScanner(folderFiles);
      final fresh = PlaylistService(bus: ownBus, scanner: ownScanner);

      ownBus.dispatch(const RescanFolder());
      await settle();

      expect(ownScanner.scannedFolders, isEmpty);
      await fresh.dispose();
      await ownBus.dispose();
    });
  });

  group('Navigation suivant / précédent', () {
    setUp(() async {
      await service.scanFolder('/serie');
      service.setCurrent('/serie/ep1.mkv');
    });

    test('suit l’ordre affiché', () {
      expect(service.nextPath(), '/serie/ep2.mkv');
      service.setCurrent('/serie/ep2.mkv');
      expect(service.nextPath(), '/serie/ep10.mkv');
      expect(service.previousPath(), '/serie/ep1.mkv');
    });

    test('boucle aux extrémités', () {
      service.setCurrent('/serie/resume.pdf'); // dernier
      expect(service.nextPath(), '/serie/bande-son.mp3');
      service.setCurrent('/serie/bande-son.mp3'); // premier
      expect(service.previousPath(), '/serie/resume.pdf');
    });

    test('respecte le filtre courant', () async {
      bus.dispatch(const SetPlaylistFilter(PlaylistFilter.video));
      await settle();
      service.setCurrent('/serie/ep10.mkv');
      expect(service.nextPath(), '/serie/ep1.mkv');
      expect(service.previousPath(), '/serie/ep2.mkv');
    });

    test('respecte le tri courant', () async {
      bus.dispatch(const SetPlaylistSort(PlaylistSort.size, descending: true));
      await settle();
      service.setCurrent('/serie/ep10.mkv'); // le plus gros, donc premier
      expect(service.nextPath(), '/serie/ep1.mkv');
    });

    test('si le fichier courant est filtré, on repart du bord', () async {
      bus.dispatch(const SetPlaylistFilter(PlaylistFilter.audio));
      await settle();
      expect(service.state.currentIndex, -1);
      expect(service.nextPath(), '/serie/bande-son.mp3');
      expect(service.previousPath(), '/serie/bande-son.mp3');
    });

    test('liste vide : aucune navigation', () async {
      await service.scanFolder('/vide');
      expect(service.nextPath(), isNull);
      expect(service.previousPath(), isNull);
    });
  });

  group('Fin de lecture', () {
    setUp(() async {
      await service.scanFolder('/serie');
      service.setCurrent('/serie/ep2.mkv');
    });

    test('stop : rien', () {
      expect(service.nextForEndMode(EndOfPlaybackMode.stop), isNull);
    });

    test('suivant : passe au suivant mais ne reboucle pas', () {
      expect(service.nextForEndMode(EndOfPlaybackMode.next), '/serie/ep10.mkv');
      service.setCurrent('/serie/resume.pdf'); // dernier
      expect(service.nextForEndMode(EndOfPlaybackMode.next), isNull);
    });

    test('répéter : rejoue le même fichier', () {
      expect(service.nextForEndMode(EndOfPlaybackMode.repeatOne), '/serie/ep2.mkv');
    });

    test('boucler le dossier : revient au début à la fin', () {
      service.setCurrent('/serie/resume.pdf');
      expect(
        service.nextForEndMode(EndOfPlaybackMode.loopFolder),
        '/serie/bande-son.mp3',
      );
    });

    test('aléatoire : ne rejoue jamais le fichier courant', () async {
      final shuffled = PlaylistService(
        bus: bus,
        scanner: scanner,
        random: _FixedRandom([0, 1, 2, 3]),
      );
      await shuffled.scanFolder('/serie');
      for (final path in shuffled.state.visiblePaths) {
        shuffled.setCurrent(path);
        for (var i = 0; i < 4; i++) {
          expect(shuffled.nextForEndMode(EndOfPlaybackMode.shuffle), isNot(path));
        }
      }
      await shuffled.dispose();
    });

    test('aléatoire avec un seul fichier : le rejoue', () async {
      final single = PlaylistService(
        bus: bus,
        scanner: FakeFolderScanner({
          '/un': [file('seul.mkv', MediaType.video)],
        }),
        random: _FixedRandom([0]),
      );
      await single.scanFolder('/un');
      single.setCurrent('/serie/seul.mkv');
      expect(single.nextForEndMode(EndOfPlaybackMode.shuffle), isNotNull);
      await single.dispose();
    });
  });

  group('Historique et pastilles', () {
    test('les positions mémorisées enrichissent les entrées', () async {
      await history.savePosition(
        '/serie/ep1.mkv',
        position: const Duration(minutes: 12),
        duration: const Duration(minutes: 40),
        now: DateTime(2026, 9, 6),
      );
      await history.markCompleted('/serie/ep2.mkv', now: DateTime(2026, 9, 6));

      await service.scanFolder('/serie');

      final ep1 = service.state.entryFor('/serie/ep1.mkv')!;
      expect(ep1.resumePosition, const Duration(minutes: 12));
      expect(ep1.duration, const Duration(minutes: 40));
      expect(ep1.hasProgressBadge, isTrue);

      final ep2 = service.state.entryFor('/serie/ep2.mkv')!;
      expect(ep2.completed, isTrue);

      expect(service.state.entryFor('/serie/ep10.mkv')!.hasProgressBadge, isFalse);
    });

    test('refreshEntry relit l’historique d’un seul fichier', () async {
      await service.scanFolder('/serie');
      expect(service.state.entryFor('/serie/ep1.mkv')!.hasProgressBadge, isFalse);

      await history.savePosition(
        '/serie/ep1.mkv',
        position: const Duration(minutes: 12),
        duration: const Duration(minutes: 40),
        now: DateTime(2026, 9, 6),
      );
      service.refreshEntry('/serie/ep1.mkv');

      expect(service.state.entryFor('/serie/ep1.mkv')!.resumePosition,
          const Duration(minutes: 12));
    });

    test('refreshEntry sur un fichier absent ne fait rien', () async {
      await service.scanFolder('/serie');
      expect(() => service.refreshEntry('/ailleurs/x.mkv'), returnsNormally);
    });
  });
}
