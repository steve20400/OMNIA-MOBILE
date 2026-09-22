import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/models/history_entry.dart';
import 'package:omnia_mobile/core/services/history_store.dart';

void main() {
  const film = '/films/ep1.mkv';
  final t0 = DateTime(2026, 9, 6, 20);

  group('HistoryEntry — règles de reprise', () {
    HistoryEntry at(Duration position, Duration duration, {bool completed = false}) =>
        HistoryEntry(
          path: film,
          position: position,
          duration: duration,
          lastOpened: t0,
          completed: completed,
        );

    test('sous 30 s, aucune reprise proposée', () {
      expect(at(const Duration(seconds: 29), const Duration(minutes: 90)).resumePosition, isNull);
      expect(at(Duration.zero, const Duration(minutes: 90)).resumePosition, isNull);
    });

    test('à partir de 30 s, la reprise est proposée', () {
      expect(
        at(const Duration(seconds: 30), const Duration(minutes: 90)).resumePosition,
        const Duration(seconds: 30),
      );
    });

    test('au-delà de 95 % de la durée, aucune reprise', () {
      const duration = Duration(minutes: 100);
      expect(at(const Duration(minutes: 95), duration).resumePosition, isNull);
      expect(at(const Duration(minutes: 96), duration).resumePosition, isNull);
      expect(
        at(const Duration(minutes: 94), duration).resumePosition,
        const Duration(minutes: 94),
      );
    });

    test('un fichier terminé repart du début', () {
      expect(
        at(const Duration(minutes: 10), const Duration(minutes: 90), completed: true)
            .resumePosition,
        isNull,
      );
    });

    test('durée inconnue : la seule règle est le seuil de 30 s', () {
      expect(
        at(const Duration(minutes: 5), Duration.zero).resumePosition,
        const Duration(minutes: 5),
      );
      expect(at(const Duration(seconds: 10), Duration.zero).resumePosition, isNull);
    });

    test('aller-retour JSON', () {
      final e = at(const Duration(minutes: 3), const Duration(minutes: 42));
      final restored = HistoryEntry.fromJson(e.toJson());
      expect(restored.toJson(), e.toJson());
      expect(restored.resumePosition, e.resumePosition);
    });

    test('JSON corrompu : valeurs de repli, pas d’exception', () {
      final e = HistoryEntry.fromJson({'path': film});
      expect(e.position, Duration.zero);
      expect(e.completed, isFalse);
      expect(e.resumePosition, isNull);
    });
  });

  group('MemoryHistoryStore', () {
    late MemoryHistoryStore store;

    setUp(() => store = MemoryHistoryStore());

    test('fichier jamais ouvert', () {
      expect(store.entryFor(film), isNull);
    });

    test('une position significative est conservée', () async {
      await store.savePosition(
        film,
        position: const Duration(minutes: 12),
        duration: const Duration(minutes: 90),
        now: t0,
      );
      expect(store.entryFor(film)!.resumePosition, const Duration(minutes: 12));
    });

    test('une position trop précoce laisse une trace sans reprise', () async {
      await store.savePosition(
        film,
        position: const Duration(seconds: 5),
        duration: const Duration(minutes: 90),
        now: t0,
      );
      final entry = store.entryFor(film)!;
      expect(entry.resumePosition, isNull);
      expect(entry.lastOpened, t0);
    });

    test('dépasser 95 % marque le fichier comme vu', () async {
      await store.savePosition(
        film,
        position: const Duration(minutes: 96),
        duration: const Duration(minutes: 100),
        now: t0,
      );
      final entry = store.entryFor(film)!;
      expect(entry.completed, isTrue);
      expect(entry.resumePosition, isNull);
    });

    test('revenir en arrière après avoir terminé remplace la position', () async {
      await store.markCompleted(film, now: t0);
      await store.savePosition(
        film,
        position: const Duration(minutes: 10),
        duration: const Duration(minutes: 90),
        now: t0.add(const Duration(hours: 1)),
      );
      final entry = store.entryFor(film)!;
      expect(entry.completed, isFalse);
      expect(entry.resumePosition, const Duration(minutes: 10));
    });

    test('les récents sont triés du plus récent au plus ancien', () async {
      await store.savePosition('/a.mkv',
          position: const Duration(minutes: 5), duration: const Duration(minutes: 90), now: t0);
      await store.savePosition('/b.mkv',
          position: const Duration(minutes: 5),
          duration: const Duration(minutes: 90),
          now: t0.add(const Duration(hours: 2)));
      await store.savePosition('/c.mkv',
          position: const Duration(minutes: 5),
          duration: const Duration(minutes: 90),
          now: t0.add(const Duration(hours: 1)));

      expect(store.recent().map((e) => e.path), ['/b.mkv', '/c.mkv', '/a.mkv']);
    });

    test('la limite des récents est respectée', () async {
      for (var i = 0; i < 30; i++) {
        await store.savePosition('/f$i.mkv',
            position: const Duration(minutes: 5),
            duration: const Duration(minutes: 90),
            now: t0.add(Duration(minutes: i)));
      }
      expect(store.recent(limit: 10), hasLength(10));
      expect(store.recent(limit: 10).first.path, '/f29.mkv');
    });

    test('touch inscrit un fichier dans les récents sans position', () async {
      await store.touch(film, now: t0);
      final entry = store.entryFor(film)!;
      expect(entry.lastOpened, t0);
      expect(entry.resumePosition, isNull);
      expect(store.recent().map((e) => e.path), [film]);
    });

    test('touch conserve la position mémorisée et met à jour la date', () async {
      await store.savePosition(
        film,
        position: const Duration(minutes: 12),
        duration: const Duration(minutes: 90),
        now: t0,
      );
      final later = t0.add(const Duration(days: 1));
      await store.touch(film, now: later);
      final entry = store.entryFor(film)!;
      expect(entry.resumePosition, const Duration(minutes: 12));
      expect(entry.lastOpened, later);
    });

    test('document : page et nombre de pages, reprise proposée', () async {
      await store.saveDocumentPosition('/doc.pdf', page: 12, pageCount: 40, now: t0);
      final entry = store.entryFor('/doc.pdf')!;
      expect(entry.page, 12);
      expect(entry.pageCount, 40);
      expect(entry.resumePage, 12);
      expect(entry.completed, isFalse);
    });

    test('document : page 1 ou dernière page → pas de reprise', () async {
      await store.saveDocumentPosition('/a.pdf', page: 1, pageCount: 40, now: t0);
      expect(store.entryFor('/a.pdf')!.resumePage, isNull);

      await store.saveDocumentPosition('/b.pdf', page: 40, pageCount: 40, now: t0);
      expect(store.entryFor('/b.pdf')!.resumePage, isNull);
      expect(store.entryFor('/b.pdf')!.completed, isTrue);
    });

    test('texte : défilement mémorisé, négligeable aux extrémités', () async {
      await store.saveDocumentPosition('/n.txt', scrollFraction: 0.4, now: t0);
      expect(store.entryFor('/n.txt')!.resumeScroll, 0.4);

      await store.saveDocumentPosition('/n.txt', scrollFraction: 0.01, now: t0);
      expect(store.entryFor('/n.txt')!.resumeScroll, isNull);

      await store.saveDocumentPosition('/n.txt', scrollFraction: 0.99, now: t0);
      expect(store.entryFor('/n.txt')!.resumeScroll, isNull);
    });

    test('document : la position survit au JSON', () async {
      await store.saveDocumentPosition('/doc.pdf', page: 7, pageCount: 9, now: t0);
      final restored = HistoryEntry.fromJson(store.entryFor('/doc.pdf')!.toJson());
      expect(restored.page, 7);
      expect(restored.pageCount, 9);
    });

    test('effacer les récents garde les positions', () async {
      await store.savePosition(film,
          position: const Duration(minutes: 12), duration: const Duration(minutes: 90), now: t0);
      await store.clearRecent();

      expect(store.recent(), isEmpty);
      expect(store.entryFor(film)!.resumePosition, const Duration(minutes: 12));
    });

    test('rouvrir un fichier le remet dans les récents', () async {
      await store.touch(film, now: t0);
      await store.clearRecent();
      await store.touch(film, now: t0.add(const Duration(hours: 1)));
      expect(store.recent().map((e) => e.path), [film]);
    });

    test('effacer les positions garde les récents', () async {
      await store.savePosition(film,
          position: const Duration(minutes: 12), duration: const Duration(minutes: 90), now: t0);
      await store.markCompleted('/b.mkv', now: t0);
      await store.saveDocumentPosition('/doc.pdf', page: 12, pageCount: 40, now: t0);

      await store.clearPositions();

      expect(store.recent(), hasLength(3));
      expect(store.entryFor(film)!.resumePosition, isNull);
      expect(store.entryFor(film)!.duration, const Duration(minutes: 90),
          reason: 'la durée est un fait sur le fichier, pas sur la lecture');
      expect(store.entryFor('/b.mkv')!.completed, isFalse);
      expect(store.entryFor('/doc.pdf')!.resumePage, isNull);
      expect(store.entryFor('/doc.pdf')!.pageCount, 40);
    });

    test('le drapeau « listé » survit au JSON, et vaut vrai par défaut', () async {
      await store.touch(film, now: t0);
      await store.clearRecent();
      final json = store.entryFor(film)!.toJson();
      expect(HistoryEntry.fromJson(json).listed, isFalse);
      expect(HistoryEntry.fromJson({'path': film}).listed, isTrue);
    });

    test('oublier un fichier, puis tout effacer', () async {
      await store.savePosition('/a.mkv',
          position: const Duration(minutes: 5), duration: const Duration(minutes: 90), now: t0);
      await store.savePosition('/b.mkv',
          position: const Duration(minutes: 5), duration: const Duration(minutes: 90), now: t0);

      await store.forget('/a.mkv');
      expect(store.entryFor('/a.mkv'), isNull);
      expect(store.entryFor('/b.mkv'), isNotNull);

      await store.clear();
      expect(store.recent(), isEmpty);
    });

    test('pruneExpired purge les entrées au-delà du seuil de jours', () async {
      await store.savePosition('/recent.mkv',
          position: const Duration(minutes: 10), duration: const Duration(minutes: 90), now: t0);
      await store.savePosition('/old.mkv',
          position: const Duration(minutes: 10),
          duration: const Duration(minutes: 90),
          now: t0.subtract(const Duration(days: 35)));

      await store.pruneExpired(30, now: t0);
      expect(store.entryFor('/recent.mkv'), isNotNull);
      expect(store.entryFor('/old.mkv'), isNull);

      // Si jours <= 0, rien n'est purgé
      await store.savePosition('/very_old.mkv',
          position: const Duration(minutes: 10),
          duration: const Duration(minutes: 90),
          now: t0.subtract(const Duration(days: 100)));
      await store.pruneExpired(0, now: t0);
      expect(store.entryFor('/very_old.mkv'), isNotNull);
    });
  });
}
