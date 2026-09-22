import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../controllers/media_router.dart';
import '../models/media_file.dart';

/// Scanne un dossier pour y trouver les fichiers lisibles par OMNIA.
abstract interface class FolderScanner {
  /// Liste les fichiers lisibles de [folder], sans descendre dans les
  /// sous-dossiers.
  ///
  /// Ne lève jamais : un dossier illisible renvoie une liste vide.
  Future<List<MediaFile>> scan(String folder);
}

/// Implémentation réelle : le parcours et les `stat()` partent dans un isolate
/// pour que l'interface ne gèle jamais, même sur un dossier de 2000 fichiers.
class IsolateFolderScanner implements FolderScanner {
  const IsolateFolderScanner();

  @override
  Future<List<MediaFile>> scan(String folder) async {
    try {
      final raw = await Isolate.run(() => scanFolderSync(folder));
      return raw.map(MediaFile.fromJson).toList();
    } on Object {
      // Isolate indisponible (certains environnements de test) : repli
      // synchrone, correct mais bloquant.
      return scanFolderSync(folder).map(MediaFile.fromJson).toList();
    }
  }
}

/// Parcours synchrone d'un dossier. Exposé pour l'isolate et pour les tests.
///
/// Retourne du JSON plutôt que des [MediaFile] : seules des valeurs simples
/// franchissent la frontière d'isolate, quelle que soit la version de Dart.
List<Map<String, Object?>> scanFolderSync(String folder) {
  final dir = Directory(folder);
  final List<FileSystemEntity> entities;
  try {
    entities = dir.listSync(followLinks: false);
  } on FileSystemException {
    return const [];
  }

  final result = <Map<String, Object?>>[];
  for (final entity in entities) {
    if (entity is! File) continue;
    final path = entity.path;
    final type = MediaRouter.typeForPath(path);
    if (!type.isSupported) continue;

    int? size;
    DateTime? modified;
    try {
      final stat = entity.statSync();
      size = stat.size;
      modified = stat.modified;
    } on FileSystemException {
      // Fichier disparu ou illisible entre le listing et le stat : on le garde
      // sans métadonnées plutôt que de le faire disparaître de la liste.
    }

    result.add(
      MediaFile(path: path, type: type, size: size, modifiedAt: modified).toJson(),
    );
  }
  return result;
}

/// Scanner de test : renvoie une liste fixée, avec un délai optionnel.
class FakeFolderScanner implements FolderScanner {
  FakeFolderScanner(this.filesByFolder, {this.delay = Duration.zero});

  final Map<String, List<MediaFile>> filesByFolder;
  final Duration delay;
  final List<String> scannedFolders = [];

  @override
  Future<List<MediaFile>> scan(String folder) async {
    scannedFolders.add(folder);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return filesByFolder[folder] ?? const [];
  }
}
