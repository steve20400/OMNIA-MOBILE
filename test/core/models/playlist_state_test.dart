import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/models/media_file.dart';
import 'package:omnia_mobile/core/models/media_type.dart';
import 'package:omnia_mobile/core/models/playlist_entry.dart';
import 'package:omnia_mobile/core/models/playlist_sort.dart';
import 'package:omnia_mobile/core/models/playlist_state.dart';

PlaylistEntry entry(
  String name,
  MediaType type, {
  int? size,
  DateTime? modified,
  Duration? resume,
  Duration? duration,
  bool completed = false,
}) {
  return PlaylistEntry(
    file: MediaFile(
      path: '/dossier/$name',
      type: type,
      size: size,
      modifiedAt: modified,
    ),
    resumePosition: resume,
    duration: duration,
    completed: completed,
  );
}

void main() {
  final sample = [
    entry('ep10.mkv', MediaType.video, size: 300, modified: DateTime(2026, 1, 3)),
    entry('ep2.mkv', MediaType.video, size: 100, modified: DateTime(2026, 1, 5)),
    entry('notes.txt', MediaType.text, size: 10, modified: DateTime(2026, 1, 1)),
    entry('musique.mp3', MediaType.audio, size: 200, modified: DateTime(2026, 1, 4)),
    entry('manuel.pdf', MediaType.pdf, size: 50, modified: DateTime(2026, 1, 2)),
  ];

  List<String> names(PlaylistState s) => s.visible.map((e) => e.file.name).toList();

  group('PlaylistState — tri', () {
    test('nom par défaut, en tri naturel', () {
      final s = PlaylistState(entries: sample);
      expect(names(s), ['ep2.mkv', 'ep10.mkv', 'manuel.pdf', 'musique.mp3', 'notes.txt']);
    });

    test('nom, ordre inverse', () {
      final s = PlaylistState(entries: sample, descending: true);
      expect(names(s), ['notes.txt', 'musique.mp3', 'manuel.pdf', 'ep10.mkv', 'ep2.mkv']);
    });

    test('taille', () {
      final s = PlaylistState(entries: sample, sort: PlaylistSort.size);
      expect(names(s), ['notes.txt', 'manuel.pdf', 'ep2.mkv', 'musique.mp3', 'ep10.mkv']);
    });

    test('date', () {
      final s = PlaylistState(entries: sample, sort: PlaylistSort.date);
      expect(names(s), ['notes.txt', 'manuel.pdf', 'ep10.mkv', 'musique.mp3', 'ep2.mkv']);
    });

    test('type, puis nom naturel', () {
      final s = PlaylistState(entries: sample, sort: PlaylistSort.type);
      expect(names(s), ['ep2.mkv', 'ep10.mkv', 'musique.mp3', 'manuel.pdf', 'notes.txt']);
    });

    test('les métadonnées inconnues passent en dernier', () {
      final s = PlaylistState(
        entries: [
          entry('sans-taille.mkv', MediaType.video),
          entry('petit.mkv', MediaType.video, size: 5),
        ],
        sort: PlaylistSort.size,
      );
      expect(names(s), ['petit.mkv', 'sans-taille.mkv']);
    });

    test('le tri ne modifie pas la liste brute', () {
      final s = PlaylistState(entries: sample, sort: PlaylistSort.size);
      s.visible;
      expect(sample.first.file.name, 'ep10.mkv');
    });
  });

  group('PlaylistState — filtre et recherche', () {
    test('filtre par type', () {
      expect(
        names(PlaylistState(entries: sample, filter: PlaylistFilter.video)),
        ['ep2.mkv', 'ep10.mkv'],
      );
      expect(
        names(PlaylistState(entries: sample, filter: PlaylistFilter.audio)),
        ['musique.mp3'],
      );
      expect(
        names(PlaylistState(entries: sample, filter: PlaylistFilter.documents)),
        ['manuel.pdf', 'notes.txt'],
      );
    });

    test('recherche insensible à la casse, sur une sous-chaîne', () {
      expect(names(PlaylistState(entries: sample, query: 'EP')), ['ep2.mkv', 'ep10.mkv']);
      expect(names(PlaylistState(entries: sample, query: 'mkv')), ['ep2.mkv', 'ep10.mkv']);
      expect(names(PlaylistState(entries: sample, query: 'nu')), ['manuel.pdf']);
    });

    test('les espaces autour de la recherche sont ignorés', () {
      expect(names(PlaylistState(entries: sample, query: '   ')).length, sample.length);
      expect(names(PlaylistState(entries: sample, query: '  ep2  ')), ['ep2.mkv']);
    });

    test('recherche sans résultat', () {
      expect(names(PlaylistState(entries: sample, query: 'zzz')), isEmpty);
    });

    test('filtre et recherche se combinent', () {
      final s = PlaylistState(
        entries: sample,
        filter: PlaylistFilter.video,
        query: '10',
      );
      expect(names(s), ['ep10.mkv']);
    });
  });

  group('PlaylistState — fichier courant', () {
    test('currentIndex suit l’ordre affiché', () {
      final s = PlaylistState(entries: sample, currentPath: '/dossier/ep10.mkv');
      expect(s.currentIndex, 1);
      expect(s.copyWith(descending: true).currentIndex, 3);
    });

    test('currentIndex vaut -1 si le fichier est filtré', () {
      final s = PlaylistState(
        entries: sample,
        currentPath: '/dossier/notes.txt',
        filter: PlaylistFilter.video,
      );
      expect(s.currentIndex, -1);
    });

    test('currentIndex vaut -1 sans fichier courant', () {
      expect(PlaylistState(entries: sample).currentIndex, -1);
    });

    test('entryFor retrouve une entrée par chemin', () {
      final s = PlaylistState(entries: sample);
      expect(s.entryFor('/dossier/ep2.mkv')?.file.name, 'ep2.mkv');
      expect(s.entryFor('/ailleurs/x.mkv'), isNull);
    });

    test('visiblePaths reflète l’ordre affiché', () {
      final s = PlaylistState(entries: sample, filter: PlaylistFilter.video);
      expect(s.visiblePaths, ['/dossier/ep2.mkv', '/dossier/ep10.mkv']);
    });
  });

  group('PlaylistEntry — pastille de progression', () {
    test('fichier terminé', () {
      final e = entry('a.mkv', MediaType.video, completed: true);
      expect(e.hasProgressBadge, isTrue);
      expect(e.progress, 1);
    });

    test('position mémorisée avec durée connue', () {
      final e = entry(
        'a.mkv',
        MediaType.video,
        resume: const Duration(minutes: 5),
        duration: const Duration(minutes: 20),
      );
      expect(e.hasProgressBadge, isTrue);
      expect(e.progress, closeTo(0.25, 1e-9));
    });

    test('position mémorisée sans durée : pastille sans pourcentage', () {
      final e = entry('a.mkv', MediaType.video, resume: const Duration(minutes: 5));
      expect(e.hasProgressBadge, isTrue);
      expect(e.progress, isNull);
    });

    test('jamais ouvert : aucune pastille', () {
      final e = entry('a.mkv', MediaType.video);
      expect(e.hasProgressBadge, isFalse);
      expect(e.progress, isNull);
    });

    test('document PDF : progression par page', () {
      const e = PlaylistEntry(
        file: MediaFile(path: '/d/x.pdf', type: MediaType.pdf),
        pageCount: 40,
        resumePage: 10,
      );
      expect(e.hasProgressBadge, isTrue);
      expect(e.progress, closeTo(0.25, 1e-9));
      expect(PlaylistEntry.fromJson(e.toJson()).progress, closeTo(0.25, 1e-9));
    });

    test('texte : progression par défilement', () {
      const e = PlaylistEntry(
        file: MediaFile(path: '/d/x.txt', type: MediaType.text),
        resumeScroll: 0.6,
      );
      expect(e.hasProgressBadge, isTrue);
      expect(e.progress, closeTo(0.6, 1e-9));
    });

    test('durée nulle ne provoque pas de division par zéro', () {
      final e = entry(
        'a.mkv',
        MediaType.video,
        resume: const Duration(minutes: 5),
        duration: Duration.zero,
      );
      expect(e.progress, isNull);
    });
  });

  test('PlaylistState — aller-retour JSON', () {
    final s = PlaylistState(
      folder: '/dossier',
      entries: sample,
      sort: PlaylistSort.size,
      descending: true,
      filter: PlaylistFilter.video,
      query: 'ep',
      currentPath: '/dossier/ep2.mkv',
    );
    final restored = PlaylistState.fromJson(s.toJson());
    expect(restored.toJson(), s.toJson());
    expect(restored.visiblePaths, s.visiblePaths);
  });
}
