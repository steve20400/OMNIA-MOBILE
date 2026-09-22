import 'dart:io';

import 'package:path/path.dart' as p;

import '../commands/player_command.dart';
import '../controllers/media_router.dart';
import 'subtitle_sidecars.dart';

/// Chemin local désigné par un argument de la ligne de commande, `null` pour
/// une option (`--quelque-chose`) ou un argument vide.
///
/// Les lanceurs Linux (`%U`) et certains docks transmettent des URI
/// `file:///home/…/Vid%C3%A9os/film.mkv` plutôt que des chemins : on les
/// décode. Un URI qui ne désigne pas un fichier local est ignoré.
String? pathFromArgument(String arg) {
  if (arg.trim().isEmpty || arg.startsWith('-')) return null;
  if (!arg.toLowerCase().startsWith('file:')) return arg;
  try {
    return Uri.parse(arg).toFilePath();
  } on UnsupportedError {
    return null;
  } on FormatException {
    return null;
  }
}

/// Chemins locaux contenus dans [args], dans l'ordre.
List<String> pathsFromArguments(List<String> args) => [
      for (final arg in args) ?pathFromArgument(arg),
    ];

/// Vrai pour un fichier de sous-titres (`.srt`, `.ass`, `.vtt`…).
bool isSubtitlePath(String path) {
  final ext = p.extension(path).toLowerCase();
  return ext.length > 1 && subtitleExtensions.contains(ext.substring(1));
}

/// Commande à exécuter pour des chemins reçus du système : fichiers déposés
/// sur la fenêtre ou sur l'icône, « Ouvrir avec », seconde instance.
///
/// Le premier élément utilisable gagne, dans l'ordre reçu : un dossier est
/// scanné, un fichier lisible est ouvert. Un sous-titre déposé pendant une
/// vidéo ([videoPlaying]) se charge sur cette vidéo au lieu de la remplacer.
/// Sans rien d'utilisable, on tente quand même le premier chemin : mieux vaut
/// un message d'erreur clair qu'une application qui ne réagit pas.
PlayerCommand? commandForPaths(List<String> paths, {bool videoPlaying = false}) {
  for (final path in paths) {
    if (FileSystemEntity.isDirectorySync(path)) return OpenFolder(path);
    if (videoPlaying && isSubtitlePath(path)) return LoadSubtitleFile(path);
    if (MediaRouter.isSupported(path) && !isSubtitlePath(path)) return OpenFile(path);
  }
  for (final path in paths) {
    if (MediaRouter.isSupported(path)) return OpenFile(path);
  }
  final first = paths.firstOrNull;
  return first == null ? null : OpenFile(first);
}

/// Traduit les arguments de la ligne de commande en commande d'ouverture.
///
/// `omnia /chemin/fichier.mkv` (« Ouvrir avec », fichier déposé sur l'icône)
/// ouvre le fichier ; un dossier déclenche le scan et la lecture de son
/// premier élément. Retourne `null` s'il n'y a rien à ouvrir.
///
/// Utilisé au démarrage et quand une seconde instance transmet ses arguments.
PlayerCommand? commandForLaunchArguments(List<String> args, {bool videoPlaying = false}) =>
    commandForPaths(pathsFromArguments(args), videoPlaying: videoPlaying);
