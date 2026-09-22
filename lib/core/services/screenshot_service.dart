import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_preferences.dart';
import '../utils/screenshot_naming.dart';
import 'local_storage.dart';
import 'settings_store.dart';

/// Enregistre les captures d'écran sur disque, et choisit où écrire les
/// extraits enregistrés : dossiers séparés (images vs audio), même motif de nom.
class ScreenshotService {
  ScreenshotService({
    this.settings,
    Future<Directory> Function()? defaultFolder,
    Future<Directory> Function()? defaultRecordingFolder,
  })  : _defaultFolder = defaultFolder ?? defaultScreenshotFolder,
        _defaultRecordingFolder =
            defaultRecordingFolder ?? defaultFolder ?? defaultScreenshotFolder;


  final SettingsStore? settings;
  final Future<Directory> Function() _defaultFolder;
  final Future<Directory> Function() _defaultRecordingFolder;

  /// Dossier de destination pour les captures d'écran vidéo (images PNG).
  Future<Directory> screenshotFolder() async {
    final configured = settings?.screenshotFolder;
    if (configured != null && configured.isNotEmpty) return Directory(configured);
    return _defaultFolder();
  }

  /// Dossier de destination pour les extraits / enregistrements audio.
  Future<Directory> recordingFolder() async {
    final configured = settings?.recordingFolder;
    if (configured != null && configured.isNotEmpty) return Directory(configured);
    return _defaultRecordingFolder();
  }

  /// Dossier de repli pour la rétrocompatibilité : captures d'écran.
  Future<Directory> folder() => screenshotFolder();

  /// Écrit [png] et retourne le chemin du fichier créé. Le nom suit le motif
  /// des préférences ([position] sert au jeton `{position}`).
  ///
  /// Lève une [FileSystemException] si le dossier est inaccessible : c'est à
  /// l'appelant d'en faire un message.
  Future<String> save(
    Uint8List png, {
    required String mediaPath,
    Duration position = Duration.zero,
    DateTime? now,
  }) async {
    final dir = await screenshotFolder();
    await dir.create(recursive: true);
    final pattern =
        settings?.preferences.screenshotNamePattern ?? AppPreferences.defaultScreenshotPattern;
    final path = await _freePath(
      dir,
      screenshotFileName(mediaPath, now ?? DateTime.now(), pattern: pattern, position: position),
      'png',
    );
    await File(path).writeAsBytes(png, flush: true);
    return path;
  }

  /// Chemin libre pour un extrait : dossier des enregistrements audio/vidéo
  /// et motif de nom des captures, conteneur Matroska, qui accepte tous les
  /// codecs (`.mkv`, ou `.mka` pour un son seul). Crée le dossier ; lève une
  /// [FileSystemException] s'il est inaccessible.
  Future<String> recordingPath({
    required String mediaPath,
    required bool audioOnly,
    Duration position = Duration.zero,
    DateTime? now,
  }) async {
    final dir = await recordingFolder();
    await dir.create(recursive: true);
    final pattern =
        settings?.preferences.screenshotNamePattern ?? AppPreferences.defaultScreenshotPattern;
    final extension = audioOnly ? 'mka' : 'mkv';
    return _freePath(
      dir,
      screenshotFileName(
        mediaPath,
        now ?? DateTime.now(),
        pattern: pattern,
        position: position,
        extension: extension,
      ),
      extension,
    );
  }


  /// Deux fichiers dans la même seconde : on suffixe plutôt que d'écraser.
  static Future<String> _freePath(Directory dir, String fileName, String extension) async {
    var path = p.join(dir.path, fileName);
    var attempt = 1;
    while (await File(path).exists()) {
      attempt++;
      final base = p.basenameWithoutExtension(fileName).replaceFirst(RegExp(r' \(\d+\)$'), '');
      path = p.join(dir.path, '$base ($attempt).$extension');
    }
    return path;
  }
}

/// Dossier par défaut : `Téléchargements/OMNIA` quand le système sait le
/// donner, sinon le dossier de données de l'application. On évite le dossier
/// « Images » : path_provider ne le connaît pas sur desktop.
Future<Directory> defaultScreenshotFolder() async {
  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return Directory(p.join(downloads.path, 'OMNIA'));
  } on Object {
    // Pas de dossier Téléchargements connu sur ce système.
  }
  return Directory(p.join((await localStorageDirectory()).path, 'captures'));
}
