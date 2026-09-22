import 'dart:async';
import 'dart:io';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models/history_entry.dart';
import 'local_storage.dart';

/// Mémoire de lecture d'OMNIA : positions reprises et fichiers récents.
abstract interface class HistoryStore {
  /// Ce qui est retenu de [path], ou `null` si le fichier n'a jamais été ouvert.
  HistoryEntry? entryFor(String path);

  /// Enregistre la progression. Les positions trop proches du début ou de la
  /// fin sont effacées plutôt que conservées (voir [HistoryEntry]).
  Future<void> savePosition(
    String path, {
    required Duration position,
    required Duration duration,
    DateTime? now,
  });

  /// Marque le fichier comme vu en entier.
  Future<void> markCompleted(String path, {DateTime? now});

  /// Note que le fichier vient d'être ouvert, sans toucher à sa position.
  ///
  /// C'est ce qui l'inscrit dans les récents dès l'ouverture : attendre la
  /// première sauvegarde de position laisserait de côté un fichier fermé
  /// avant la première minute.
  Future<void> touch(String path, {DateTime? now});

  /// Documents : mémorise la page courante et le nombre de pages (PDF), ou la
  /// position de défilement (texte).
  Future<void> saveDocumentPosition(
    String path, {
    int? page,
    int? pageCount,
    double? scrollFraction,
    DateTime? now,
  });

  /// Fichiers récemment ouverts, du plus récent au plus ancien.
  List<HistoryEntry> recent({int limit = 20});

  /// Oublie un fichier.
  Future<void> forget(String path);

  /// Vide la liste des récents, en gardant les positions mémorisées.
  Future<void> clearRecent();

  /// Oublie toutes les positions, en gardant la liste des récents.
  Future<void> clearPositions();

  /// Efface tout l'historique.
  Future<void> clear();

  /// Élimine les entrées de progression plus anciennes que [retentionDays] jours.
  /// Si [retentionDays] <= 0 (sans limite), aucune entrée n'est purgée.
  Future<void> pruneExpired(int retentionDays, {DateTime? now});
}

/// Implémentation Hive, sur une boîte dédiée.
class HiveHistoryStore implements HistoryStore {
  HiveHistoryStore(this._box, [this._dataDir]);

  final Box<dynamic> _box;
  final Directory? _dataDir;

  static const boxName = 'history';

  static Future<HiveHistoryStore> open({Directory? dataDirectory}) async {
    await initialiseLocalStorage();
    final dir = dataDirectory ?? await localStorageDirectory();
    return HiveHistoryStore(await Hive.openBox<dynamic>(boxName), dir);
  }

  @override
  HistoryEntry? entryFor(String path) {
    final raw = _box.get(path);
    if (raw is! Map) return null;
    try {
      return HistoryEntry.fromJson(Map<String, Object?>.from(raw));
    } on Object {
      // Entrée écrite par une version antérieure : on l'ignore plutôt que de
      // faire échouer l'ouverture du fichier.
      return null;
    }
  }

  @override
  Future<void> savePosition(
    String path, {
    required Duration position,
    required Duration duration,
    DateTime? now,
  }) async {
    final reached = duration > Duration.zero &&
        position.inMilliseconds / duration.inMilliseconds >=
            HistoryEntry.completionThreshold;

    if (reached) {
      await markCompleted(path, now: now);
      return;
    }
    if (!HistoryEntry.isWorthSaving(position, duration)) {
      // Trop tôt dans le fichier : on garde une trace « déjà ouvert » sans
      // position, pour la liste des récents.
      final existing = entryFor(path);
      await _put(
        HistoryEntry(
          path: path,
          position: Duration.zero,
          duration: duration,
          lastOpened: now ?? DateTime.now(),
          completed: existing?.completed ?? false,
        ),
      );
      return;
    }

    await _put(
      HistoryEntry(
        path: path,
        position: position,
        duration: duration,
        lastOpened: now ?? DateTime.now(),
      ),
    );
  }

  @override
  Future<void> markCompleted(String path, {DateTime? now}) async {
    final existing = entryFor(path);
    await _put(
      HistoryEntry(
        path: path,
        position: Duration.zero,
        duration: existing?.duration ?? Duration.zero,
        lastOpened: now ?? DateTime.now(),
        completed: true,
        pageCount: existing?.pageCount ?? 0,
      ),
    );
  }

  Future<void> _put(HistoryEntry entry) async {
    await _box.put(entry.path, entry.toJson());
    await _box.flush();
    final dir = _dataDir;
    if (dir != null) {
      unawaited(writeHistorySnapshot(dir, {for (final e in _all()) e.path: e.toJson()}));
    }
  }

  @override
  Future<void> touch(String path, {DateTime? now}) async {
    final existing = entryFor(path);
    await _put(
      existing?.copyWith(lastOpened: now ?? DateTime.now(), listed: true) ??
          HistoryEntry(
            path: path,
            position: Duration.zero,
            duration: Duration.zero,
            lastOpened: now ?? DateTime.now(),
          ),
    );
  }

  List<HistoryEntry> _all() {
    final entries = <HistoryEntry>[];
    for (final key in _box.keys) {
      final entry = entryFor(key as String);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  @override
  Future<void> clearRecent() async {
    for (final entry in _all()) {
      if (entry.listed) await _put(entry.copyWith(listed: false));
    }
  }

  @override
  Future<void> clearPositions() async {
    for (final entry in _all()) {
      await _put(entry.withoutProgress());
    }
  }

  @override
  Future<void> saveDocumentPosition(
    String path, {
    int? page,
    int? pageCount,
    double? scrollFraction,
    DateTime? now,
  }) async {
    final existing = entryFor(path) ??
        HistoryEntry(
          path: path,
          position: Duration.zero,
          duration: Duration.zero,
          lastOpened: now ?? DateTime.now(),
        );
    await _put(
      existing.copyWith(
        page: page,
        pageCount: pageCount,
        scrollFraction: scrollFraction?.clamp(0.0, 1.0),
        lastOpened: now ?? DateTime.now(),
        // Lu jusqu'à la dernière page : on le note, comme pour un média.
        completed: (page != null && pageCount != null && pageCount > 0)
            ? (page >= pageCount)
            : existing.completed,
      ),
    );
  }

  @override
  List<HistoryEntry> recent({int limit = 20}) {
    final entries = _all().where((e) => e.listed).toList()
      ..sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    return entries.take(limit).toList();
  }

  @override
  Future<void> forget(String path) => _box.delete(path);

  @override
  Future<void> clear() => _box.clear();

  @override
  Future<void> pruneExpired(int retentionDays, {DateTime? now}) async {
    if (retentionDays <= 0) return;
    final stamp = now ?? DateTime.now();
    for (final entry in _all()) {
      if (stamp.difference(entry.lastOpened).inDays >= retentionDays) {
        await forget(entry.path);
      }
    }
  }
}

/// Implémentation en mémoire, pour les tests.
class MemoryHistoryStore implements HistoryStore {
  final Map<String, HistoryEntry> entries = {};

  @override
  HistoryEntry? entryFor(String path) => entries[path];

  @override
  Future<void> savePosition(
    String path, {
    required Duration position,
    required Duration duration,
    DateTime? now,
  }) async {
    final stamp = now ?? DateTime.now();
    final reached = duration > Duration.zero &&
        position.inMilliseconds / duration.inMilliseconds >=
            HistoryEntry.completionThreshold;
    if (reached) {
      await markCompleted(path, now: stamp);
      return;
    }
    if (!HistoryEntry.isWorthSaving(position, duration)) {
      entries[path] = HistoryEntry(
        path: path,
        position: Duration.zero,
        duration: duration,
        lastOpened: stamp,
        completed: entries[path]?.completed ?? false,
      );
      return;
    }
    entries[path] = HistoryEntry(
      path: path,
      position: position,
      duration: duration,
      lastOpened: stamp,
    );
  }

  @override
  Future<void> markCompleted(String path, {DateTime? now}) async {
    final existing = entries[path];
    entries[path] = HistoryEntry(
      path: path,
      position: Duration.zero,
      duration: existing?.duration ?? Duration.zero,
      lastOpened: now ?? DateTime.now(),
      completed: true,
      pageCount: existing?.pageCount ?? 0,
    );
  }

  @override
  Future<void> touch(String path, {DateTime? now}) async {
    final stamp = now ?? DateTime.now();
    entries[path] = entries[path]?.copyWith(lastOpened: stamp, listed: true) ??
        HistoryEntry(
          path: path,
          position: Duration.zero,
          duration: Duration.zero,
          lastOpened: stamp,
        );
  }

  @override
  Future<void> clearRecent() async {
    entries.updateAll((_, e) => e.copyWith(listed: false));
  }

  @override
  Future<void> clearPositions() async {
    entries.updateAll((_, e) => e.withoutProgress());
  }

  @override
  Future<void> saveDocumentPosition(
    String path, {
    int? page,
    int? pageCount,
    double? scrollFraction,
    DateTime? now,
  }) async {
    final stamp = now ?? DateTime.now();
    final existing = entries[path] ??
        HistoryEntry(
          path: path,
          position: Duration.zero,
          duration: Duration.zero,
          lastOpened: stamp,
        );
    entries[path] = existing.copyWith(
      page: page,
      pageCount: pageCount,
      scrollFraction: scrollFraction?.clamp(0.0, 1.0),
      lastOpened: stamp,
      completed: (page != null && pageCount != null && pageCount > 0)
          ? (page >= pageCount)
          : existing.completed,
    );
  }

  @override
  List<HistoryEntry> recent({int limit = 20}) {
    final list = entries.values.where((e) => e.listed).toList()
      ..sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    return list.take(limit).toList();
  }

  @override
  Future<void> forget(String path) async => entries.remove(path);

  @override
  Future<void> clear() async => entries.clear();

  @override
  Future<void> pruneExpired(int retentionDays, {DateTime? now}) async {
    if (retentionDays <= 0) return;
    final stamp = now ?? DateTime.now();
    entries.removeWhere((_, e) => stamp.difference(e.lastOpened).inDays >= retentionDays);
  }
}

/// Implémentation basée sur un fichier JSON partagé, utilisée pour les fenêtres
/// secondaires quand Hive est verrouillé par la première instance.
class FileHistoryStore implements HistoryStore {
  FileHistoryStore(this.directory) {
    final raw = readHistorySnapshot(directory);
    for (final entry in raw.entries) {
      if (entry.value is Map) {
        try {
          entries[entry.key] = HistoryEntry.fromJson(
            Map<String, Object?>.from(entry.value as Map),
          );
        } catch (_) {}
      }
    }
  }

  final Directory directory;
  final Map<String, HistoryEntry> entries = {};

  Future<void> _flush() async {
    await writeHistorySnapshot(directory, {for (final e in entries.values) e.path: e.toJson()});
  }

  @override
  HistoryEntry? entryFor(String path) => entries[path];

  @override
  Future<void> savePosition(
    String path, {
    required Duration position,
    required Duration duration,
    DateTime? now,
  }) async {
    final stamp = now ?? DateTime.now();
    final reached = duration > Duration.zero &&
        position.inMilliseconds / duration.inMilliseconds >=
            HistoryEntry.completionThreshold;
    if (reached) {
      await markCompleted(path, now: stamp);
      return;
    }
    if (!HistoryEntry.isWorthSaving(position, duration)) {
      entries[path] = HistoryEntry(
        path: path,
        position: Duration.zero,
        duration: duration,
        lastOpened: stamp,
        completed: entries[path]?.completed ?? false,
      );
      await _flush();
      return;
    }
    entries[path] = HistoryEntry(
      path: path,
      position: position,
      duration: duration,
      lastOpened: stamp,
    );
    await _flush();
  }

  @override
  Future<void> markCompleted(String path, {DateTime? now}) async {
    final existing = entries[path];
    entries[path] = HistoryEntry(
      path: path,
      position: Duration.zero,
      duration: existing?.duration ?? Duration.zero,
      lastOpened: now ?? DateTime.now(),
      completed: true,
      pageCount: existing?.pageCount ?? 0,
    );
    await _flush();
  }

  @override
  Future<void> touch(String path, {DateTime? now}) async {
    final stamp = now ?? DateTime.now();
    entries[path] = entries[path]?.copyWith(lastOpened: stamp, listed: true) ??
        HistoryEntry(
          path: path,
          position: Duration.zero,
          duration: Duration.zero,
          lastOpened: stamp,
        );
    await _flush();
  }

  @override
  Future<void> clearRecent() async {
    entries.updateAll((_, e) => e.copyWith(listed: false));
    await _flush();
  }

  @override
  Future<void> clearPositions() async {
    entries.updateAll((_, e) => e.withoutProgress());
    await _flush();
  }

  @override
  Future<void> saveDocumentPosition(
    String path, {
    int? page,
    int? pageCount,
    double? scrollFraction,
    DateTime? now,
  }) async {
    final stamp = now ?? DateTime.now();
    final existing = entries[path] ??
        HistoryEntry(
          path: path,
          position: Duration.zero,
          duration: Duration.zero,
          lastOpened: stamp,
        );
    entries[path] = existing.copyWith(
      page: page,
      pageCount: pageCount,
      scrollFraction: scrollFraction?.clamp(0.0, 1.0),
      lastOpened: stamp,
      completed: (page != null && pageCount != null && pageCount > 0)
          ? (page >= pageCount)
          : existing.completed,
    );
    await _flush();
  }

  @override
  List<HistoryEntry> recent({int limit = 20}) {
    final list = entries.values.where((e) => e.listed).toList()
      ..sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    return list.take(limit).toList();
  }

  @override
  Future<void> forget(String path) async {
    entries.remove(path);
    await _flush();
  }

  @override
  Future<void> clear() async {
    entries.clear();
    await _flush();
  }

  @override
  Future<void> pruneExpired(int retentionDays, {DateTime? now}) async {
    if (retentionDays <= 0) return;
    final stamp = now ?? DateTime.now();
    entries.removeWhere((_, e) => stamp.difference(e.lastOpened).inDays >= retentionDays);
    await _flush();
  }
}
