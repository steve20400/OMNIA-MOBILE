import '../controllers/media_router.dart';
import '../models/media_file.dart';
import 'content_uri.dart';

/// Les voisins d'un média partagé par une autre application.
///
/// Sous Android, « Ouvrir avec » ne transmet pas un chemin mais un URI de
/// fournisseur : il n'a pas de dossier parent à scanner. La plateforme
/// interroge alors MediaStore, qui connaît le dossier de chaque média indexé,
/// et rend la liste brute de ses fichiers. Ce module la traduit en entrées du
/// panneau latéral, pour que « Ouvrir avec » montre le dossier comme le fait
/// une ouverture depuis l'application.
///
/// Toute l'interprétation est ici, rien dans la couche Android : ce qui décide
/// de la liste affichée se vérifie donc sans téléphone.
class SharedSiblings {
  const SharedSiblings({required this.folder, required this.files});

  /// Dossier à afficher, ou `null` quand le fournisseur n'en expose aucun
  /// (envoi par messagerie, fichier en nuage, permission refusée).
  final String? folder;

  /// Le fichier ouvert et ses voisins lisibles. Jamais vide : le fichier ouvert
  /// y figure toujours.
  final List<MediaFile> files;
}

/// Traduit la réponse de « listSiblings » en fichiers du panneau.
///
/// [openedPath] est le chemin — ou l'URI — par lequel le lecteur a ouvert le
/// média : c'est sous celui-là qu'il le connaît, et sous celui-là que la
/// reprise et le surlignage du fichier courant le retrouvent. L'entrée que la
/// plateforme désigne par « self » reprend donc ce chemin, et non l'URI
/// MediaStore du même fichier.
///
/// [openedName] donne son type et son rang dans le tri au fichier ouvert. Le
/// nom réel de chaque voisin désigné par un URI est retenu au passage : sans
/// lui, la liste afficherait des numéros et le tri naturel n'aurait rien à
/// comparer.
///
/// Une réponse absente ou incompréhensible n'est pas une erreur : MediaStore
/// refuse ses requêtes quand la permission manque, et n'indexe pas les fichiers
/// d'un fournisseur distant. Il reste alors le fichier ouvert, seul — ce qui
/// vaut toujours mieux qu'un panneau vide, et surtout qu'un refus de lire.
SharedSiblings parseSharedSiblings(
  Object? reply, {
  required String openedPath,
  required String openedName,
}) {
  rememberContentUriName(openedPath, openedName);

  final files = <MediaFile>[];
  final seen = <String>{};
  String? folder;

  if (reply is Map) {
    folder = reply['folder'] as String?;
    final self = reply['self'] as String?;
    final raw = reply['files'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final name = item['name'] as String?;
        if (name == null || name.isEmpty) continue;
        final listed = item['path'] as String?;
        if (listed == null || listed.isEmpty) continue;

        // Le dossier contient aussi ce qu'OMNIA ne lit pas : c'est ici, et
        // nulle part côté plateforme, que la liste des types se décide.
        final type = MediaRouter.typeForPath(name);
        if (!type.isSupported) continue;

        final path = (self != null && listed == self) ? openedPath : listed;
        // Un même fichier peut remonter deux fois : indexé dans deux
        // collections, ou déjà rencontré sous le chemin d'ouverture. Deux
        // entrées identiques feraient deux lignes et deux crans de navigation.
        if (!seen.add(path)) continue;

        rememberContentUriName(path, name);
        files.add(
          MediaFile(
            path: path,
            type: type,
            size: _asInt(item['size']),
            modifiedAt: _asDate(item['modified']),
          ),
        );
      }
    }
  }

  // Le fichier en cours de lecture doit figurer dans la liste, même si
  // MediaStore ne l'indexe pas : c'est lui que le panneau surligne, et c'est de
  // lui que part la navigation « suivant / précédent ».
  if (!seen.contains(openedPath)) {
    files.add(
      MediaFile(path: openedPath, type: MediaRouter.typeForPath(openedName)),
    );
  }

  return SharedSiblings(folder: folder, files: files);
}

int? _asInt(Object? value) =>
    value is int ? value : (value is num ? value.toInt() : null);

DateTime? _asDate(Object? value) {
  final millis = _asInt(value);
  if (millis == null || millis <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(millis);
}
