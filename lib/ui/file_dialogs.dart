import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/commands/player_command.dart';
import '../core/controllers/media_router.dart';
import '../core/providers.dart';
import '../core/utils/content_uri.dart';

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
  final file = await FilePicker.pickFile(
    dialogTitle: 'OMNIA',
    type: FileType.custom,
    allowedExtensions: mediaPickerExtensions(),
  );
  if (file == null) return;

  final rawPath = file.path;
  if (rawPath == null || rawPath.isEmpty) {
    // Le sélecteur n'a rendu aucun chemin : sous Android, c'est un URI de
    // fournisseur de contenu. Un média audio ou vidéo s'ouvre tel quel, par
    // descripteur, sans en réclamer de copie. Les documents et les images,
    // eux, se lisent par le système de fichiers : sans chemin, il n'y a rien
    // à leur donner.
    final uri = file.uri.toString();
    if (isContentUri(uri) && MediaRouter.typeForPath(file.name).isAv) {
      rememberContentUriName(uri, file.name);
      bus.dispatch(OpenFile(uri));
    }
    return;
  }

  var finalPath = rawPath;
  // Sous Android, tenter de retrouver le vrai chemin physique sur le stockage
  // si file_picker l'a mis en cache temporaire. Permet de scanner tous les fichiers frères.
  if (Platform.isAndroid && rawPath.contains('/cache/')) {
    try {
      const channel = MethodChannel('dev.omnia.mobile/intent');
      final resolved = await channel.invokeMethod<String>('resolveRealStoragePath', {'path': rawPath});
      if (resolved != null && resolved.isNotEmpty && File(resolved).existsSync()) {
        finalPath = resolved;
      }
    } catch (_) {}
  }
  bus.dispatch(OpenFile(finalPath));
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
