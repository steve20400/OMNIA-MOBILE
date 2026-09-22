import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/commands/player_command.dart';
import '../core/models/history_entry.dart';
import '../core/providers.dart';

/// Un fichier récent tel que l'interface le présente.
class RecentFile {
  const RecentFile({required this.entry, required this.exists});

  final HistoryEntry entry;

  /// Faux si le fichier a été déplacé ou supprimé depuis : l'entrée reste
  /// listée, grisée, pour que l'utilisateur comprenne où il en est.
  final bool exists;

  String get path => entry.path;
}

/// Liste des fichiers récents, du plus récent au plus ancien.
final recentFilesProvider =
    NotifierProvider<RecentFilesNotifier, List<RecentFile>>(RecentFilesNotifier.new);

class RecentFilesNotifier extends Notifier<List<RecentFile>> {
  static const int limit = 12;
  StreamSubscription<PlayerCommand>? _subscription;

  @override
  List<RecentFile> build() {
    final bus = ref.watch(commandBusProvider);
    final service = ref.watch(playbackServiceProvider);

    // L'historique n'a pas de flux de changements : on se rafraîchit après
    // chaque commande susceptible de le modifier, une fois celle-ci traitée.
    _subscription = bus.commands.listen((command) async {
      switch (command) {
        case OpenFile() || OpenFolder() || NextFile() || PreviousFile() ||
              Stop() || ClearHistory() || ClearRecentFiles() || ClearResumePositions():
          await service.idle;
          refresh();
        default:
          break;
      }
    });
    ref.onDispose(() => _subscription?.cancel());

    return _load();
  }

  void refresh() => state = _load();

  List<RecentFile> _load() {
    final history = ref.read(historyStoreProvider);
    return history
        .recent(limit: limit)
        .map((e) => RecentFile(entry: e, exists: File(e.path).existsSync()))
        .toList();
  }
}
