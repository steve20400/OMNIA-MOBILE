import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Rapatrie un média distant dans un fichier local, et rend son chemin.
///
/// Le moteur vidéo sait lire un flux à distance ; ni le lecteur de PDF ni
/// celui d'images, qui attendent un fichier posé sur le disque. Un document
/// projeté par OMNIA Connect doit donc d'abord atterrir ici — sans quoi il
/// était confié au moteur vidéo, qui le déclarait illisible.
///
/// Rend `null` quand le média n'a pas pu être récupéré : l'appelant doit le
/// dire à l'utilisateur plutôt que d'ouvrir un fichier vide.
Future<String?> downloadRemoteMedia(
  String url, {
  required String name,
  Directory? into,
  Duration timeout = const Duration(seconds: 30),
  int maxBytes = maxRemoteMediaBytes,
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) return null;

    final dir = into ?? await Directory.systemTemp.createTemp('omnia_recu_');
    await dir.create(recursive: true);
    // Le nom d'origine est conservé : c'est lui qui porte l'extension, donc le
    // type du média, et c'est lui que l'utilisateur lira dans le titre.
    final target = File(p.join(dir.path, safeFileName(name)));
    // Un document annoncé plus gros que la borne n'est pas même commencé.
    if (response.contentLength > maxBytes) {
      unawaited(response.drain<void>().catchError((Object _) {}));
      return null;
    }
    final sink = target.openWrite();
    var received = 0;
    var tooBig = false;
    try {
      await for (final chunk in response.timeout(timeout)) {
        received += chunk.length;
        // Un appareil relié qui enverrait sans fin remplirait le disque.
        if (received > maxBytes) {
          tooBig = true;
          break;
        }
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (tooBig) {
      try {
        await target.delete();
      } on FileSystemException {
        // Le dossier temporaire sera purgé au prochain lancement.
      }
      return null;
    }
    return target.path;
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Taille maximale d'un document ou d'une image rapatriés : 2 Gio. Les
/// vidéos et les sons, eux, sont lus en flux, sans copie.
const int maxRemoteMediaBytes = 2 << 30;

/// Un nom de fichier sans séparateur ni caractère interdit.
///
/// Ce nom vient de l'autre appareil : il ne doit pas pouvoir désigner un
/// dossier voisin, ni un emplacement choisi par celui qui l'envoie.
String safeFileName(String name) {
  final base = p.basename(name.replaceAll('\\', '/'));
  final cleaned = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return 'media';
  return cleaned;
}

/// Vrai si [path] désigne un média servi par un autre appareil.
bool isRemoteMedia(String path) =>
    path.startsWith('http://') || path.startsWith('https://');

/// Les dossiers temporaires qu'OMNIA crée, et qu'il efface lui-même : les
/// copies de médias projetés, et les téléchargements de mise à jour.
const List<String> omniaTemporaryPrefixes = ['omnia_recu_', 'omnia-update-'];

/// Efface les dossiers temporaires d'OMNIA laissés par les sessions
/// précédentes, et eux seuls — jamais les fichiers d'une autre application.
///
/// Un document ou une image projetés sont rapatriés dans un dossier temporaire
/// avant d'être ouverts ; une mise à jour s'y télécharge. Rien ne les effaçait :
/// sur une machine dont le disque est déjà plein, ils s'accumulaient sans que
/// personne ne sache d'où ils venaient.
///
/// Seuls les dossiers de plus de [olderThan] partent : une autre fenêtre
/// d'OMNIA, ouverte en ce moment, peut être en train d'afficher sa copie.
Future<void> purgeReceivedMedia({
  Directory? root,
  Duration olderThan = const Duration(hours: 12),
  DateTime? now,
}) async {
  try {
    final racine = root ?? Directory.systemTemp;
    if (!racine.existsSync()) return;
    final limite = (now ?? DateTime.now()).subtract(olderThan);
    for (final entree in racine.listSync()) {
      if (entree is! Directory) continue;
      final nom = p.basename(entree.path);
      if (!omniaTemporaryPrefixes.any(nom.startsWith)) continue;
      try {
        if (!entree.statSync().modified.isBefore(limite)) continue;
        entree.deleteSync(recursive: true);
      } on Object {
        // Dossier encore ouvert ailleurs : on le laisse plutôt que d'insister.
      }
    }
  } on Object {
    // Le dossier temporaire est illisible : rien à nettoyer, rien à signaler.
  }
}
