import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/controllers/media_router.dart';
import 'package:omnia_mobile/core/models/media_file.dart';
import 'package:omnia_mobile/core/models/media_type.dart';
import 'package:omnia_mobile/core/utils/remote_media.dart';

/// Une adresse telle qu'OMNIA Connect en produit : le vrai chemin du fichier
/// voyage dans le paramètre `path`.
String projete(String chemin) => Uri.http('192.168.1.24:41530', '/api/stream', {
      'path': chemin,
      'token': 'jeton',
    }).toString();

void main() {
  group('Média projeté : nom et type viennent du fichier transporté', () {
    test("le titre affiche le nom du fichier, pas l'adresse", () {
      // Le symptôme rapporté : la barre de titre montrait « stream?path=… ».
      final f = MediaFile(
        path: projete('/data/user/0/dev.omnia.mobile/cache/Le_Voyage.mkv'),
        type: MediaType.video,
      );
      expect(f.name, 'Le_Voyage.mkv');
      expect(f.baseName, 'Le_Voyage');
      expect(f.extension, 'mkv');
    });

    test('un chemin local reste inchangé', () {
      final f = MediaFile(path: '/films/ep1.mkv', type: MediaType.video);
      expect(f.name, 'ep1.mkv');
      expect(f.extension, 'mkv');
    });

    test('chaque type est reconnu dans une adresse projetée', () {
      // Tout était tenu pour une vidéo : un PDF ou une image finissaient donc
      // chez le moteur vidéo, qui les déclarait illisibles.
      expect(MediaRouter.typeForPath(projete('/x/manuel.pdf')), MediaType.pdf);
      expect(MediaRouter.typeForPath(projete('/x/photo.jpg')), MediaType.image);
      expect(MediaRouter.typeForPath(projete('/x/notes.txt')), MediaType.text);
      expect(MediaRouter.typeForPath(projete('/x/chanson.mp3')), MediaType.audio);
      expect(MediaRouter.typeForPath(projete('/x/film.mkv')), MediaType.video);
    });

    test('un flux ordinaire sans extension reste une vidéo', () {
      expect(MediaRouter.typeForPath('http://exemple.test/direct'), MediaType.video);
    });
  });

  group('Rapatriement du média distant', () {
    HttpServer? serveur;
    late Directory dossier;

    setUp(() {
      dossier = Directory.systemTemp.createTempSync('omnia_recu_test_');
    });

    tearDown(() async {
      await serveur?.close(force: true);
      try {
        dossier.deleteSync(recursive: true);
      } on FileSystemException {
        // Le dossier temporaire partira avec le système.
      }
    });

    Future<String> servir(List<int> octets, {int code = HttpStatus.ok}) async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serveur = s;
      s.listen((r) async {
        r.response.statusCode = code;
        if (code == HttpStatus.ok) r.response.add(octets);
        await r.response.close();
      });
      return 'http://${s.address.address}:${s.port}/api/stream?path=%2Fx%2Fmanuel.pdf';
    }

    test('le fichier est écrit en local sous son vrai nom', () async {
      final url = await servir([1, 2, 3, 4]);
      final local = await downloadRemoteMedia(url, name: 'manuel.pdf', into: dossier);
      expect(local, isNotNull);
      expect(File(local!).readAsBytesSync(), [1, 2, 3, 4]);
      expect(local.endsWith('manuel.pdf'), isTrue);
    });

    test('une réponse en erreur ne laisse aucun fichier', () async {
      final url = await servir(const [], code: HttpStatus.unauthorized);
      final local = await downloadRemoteMedia(url, name: 'manuel.pdf', into: dossier);
      expect(local, isNull);
      expect(dossier.listSync(), isEmpty);
    });

    test('une adresse injoignable rend null au lieu de lever', () async {
      // Le port 1 n'écoute jamais : l'échec doit être dit, pas propagé.
      final local = await downloadRemoteMedia(
        'http://127.0.0.1:1/api/stream?path=%2Fx%2Fmanuel.pdf',
        name: 'manuel.pdf',
        into: dossier,
        timeout: const Duration(seconds: 2),
      );
      expect(local, isNull);
    });

    test("un nom venu du réseau ne peut pas désigner un autre dossier", () {
      // Ce nom est fourni par l'autre appareil : il ne doit jamais sortir du
      // dossier de réception.
      expect(safeFileName('../../etc/passwd'), 'passwd');
      expect(safeFileName(r'C:\Windows\system32\cmd.exe'), 'cmd.exe');
      expect(safeFileName(''), 'media');
      expect(safeFileName('..'), 'media');
    });
  });
}
