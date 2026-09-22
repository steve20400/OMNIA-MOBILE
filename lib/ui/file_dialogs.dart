import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/commands/player_command.dart';
import '../core/controllers/media_router.dart';
import '../core/providers.dart';

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
  );
  final path = result?.files.singleOrNull?.path;
  if (path != null) {
    bus.dispatch(OpenFile(path));
  }
}

/// Sélectionne un dossier de médias.
Future<void> pickAndOpenFolder(WidgetRef ref) async {
  final bus = ref.read(commandBusProvider);
  final dir = await FilePicker.platform.getDirectoryPath(
    dialogTitle: 'OMNIA',
  );
  if (dir != null) {
    bus.dispatch(OpenFolder(dir));
  }
}
