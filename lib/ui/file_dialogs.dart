import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/commands/player_command.dart';
import '../core/controllers/media_router.dart';
import '../core/models/media_file.dart';
import '../core/models/playlist_entry.dart';
import '../core/providers.dart';

/// Lance une nouvelle fenêtre OMNIA avec le fichier spécifié.
Future<void> openInNewWindow(String path) async {
  try {
    final exe = Platform.resolvedExecutable;
    await Process.start(
      exe,
      ['--new-window', path],
      mode: ProcessStartMode.detached,
    );
  } catch (_) {
    // Échec silencieux
  }
}

/// Extensions proposées par le dialogue d'ouverture.
List<String> mediaPickerExtensions() {
  final extensions = <String>{};
  for (final ext in MediaRouter.allExtensions) {
    extensions.add(ext);
    extensions.add(ext.toUpperCase());
  }
  return extensions.toList()..sort();
}

/// Sélectionne un fichier média ou document via le sélecteur natif.
Future<void> pickAndOpenFile(WidgetRef ref) async {
  final bus = ref.read(commandBusProvider);
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: 'OMNIA',
    type: FileType.custom,
    allowedExtensions: mediaPickerExtensions(),
    allowMultiple: true,
  );
  if (result != null && result.files.isNotEmpty) {
    final first = result.files.first.path;
    if (first != null) {
      bus.dispatch(OpenFile(first));
      if (result.files.length > 1) {
        final playlist = ref.read(playlistServiceProvider);
        for (final f in result.files.skip(1)) {
          final p = f.path;
          if (p != null) {
            final type = MediaRouter.typeForPath(p);
            if (type.isSupported) {
              playlist.addEntry(PlaylistEntry(file: MediaFile(path: p, type: type)));
            }
          }
        }
      }
    }
  }
}

/// Sélectionne un dossier de médias.
Future<void> pickAndOpenFolder(WidgetRef ref) async {
  final bus = ref.read(commandBusProvider);
  final dir = await FilePicker.getDirectoryPath(
    dialogTitle: 'OMNIA',
  );
  if (dir != null) {
    bus.dispatch(OpenFolder(dir));
  }
}
