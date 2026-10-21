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
    final sink = target.openWrite();
    try {
      await sink.addStream(response);
      await sink.flush();
    } finally {
      await sink.close();
    }
    return target.path;
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

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
