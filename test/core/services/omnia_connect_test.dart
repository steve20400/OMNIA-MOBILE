import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/commands/player_command.dart';
import 'package:omnia_mobile/core/models/media_file.dart';
import 'package:omnia_mobile/core/models/media_type.dart';
import 'package:omnia_mobile/core/models/playback_state.dart';
import 'package:omnia_mobile/core/models/playback_status.dart';
import 'package:omnia_mobile/core/services/omnia_connect_service.dart';

/// Interconnexion OMNIA Connect, exercée pour de vrai : un serveur lié à la
/// boucle locale, un client qui s'y connecte par WebSocket, et les deux sens
/// du protocole — commandes du client vers l'hôte, état de lecture de l'hôte
/// vers le client.
///
/// Ce test ne remplace pas un essai entre deux appareils (découverte, Wi-Fi,
/// point d'accès, PAN Bluetooth restent propres au matériel), mais il vérifie
/// tout ce qui est du ressort du code : le contenu du payload d'appairage, la
/// poignée de main, le jeton, et la traduction des messages des deux côtés.
/// Sans lui, une divergence de protocole entre l'hôte et le client ne se
/// verrait qu'à la main, deux appareils en main.
void main() {
  /// Laisse au serveur le temps d'enregistrer la socket : `connect` rend la
  /// main dès la poignée de main WebSocket, l'hôte l'apprend juste après.
  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 60));

  group('OMNIA Connect de bout en bout', () {
    late OmniaConnectService host;
    late int port;

    setUp(() async {
      host = OmniaConnectService();
      port = await host.start(address: InternetAddress.loopbackIPv4);
    });

    tearDown(() async {
      await host.stop();
    });

    test('le serveur écoute et publie son état', () async {
      expect(host.isRunning, isTrue);
      expect(port, greaterThan(0));
      expect(host.sessionToken, isNotEmpty);

      final client = HttpClient();
      addTearDown(client.close);
      final request =
          await client.getUrl(Uri.parse('http://127.0.0.1:$port/api/status'));
      final response = await request.close();
      final body =
          jsonDecode(await response.transform(utf8.decoder).join()) as Map;

      expect(response.statusCode, HttpStatus.ok);
      expect(body['status'], 'online');
      expect(body['service'], 'OMNIA Connect');
    });

    test("le payload d'appairage porte l'adresse, le port et le jeton",
        () async {
      final payload = await host.getPairingPayload('Téléphone de test');
      final map = jsonDecode(payload) as Map<String, Object?>;

      expect(map['protocol'], 'omnia-connect');
      expect(map['version'], '1.0');
      expect(map['name'], 'Téléphone de test');
      expect(map['port'], port);
      // Le jeton doit être celui de la session en cours, sans quoi l'hôte
      // refuse la connexion au premier appairage venu.
      expect(map['token'], host.sessionToken);
    });

    test('un client appairé reçoit les commandes de lecture', () async {
      final payload = jsonDecode(await host.getPairingPayload('Hôte'))
          as Map<String, Object?>;

      final client = OmniaConnectClient();
      final connected = await client.connect(
        host: '127.0.0.1',
        port: port,
        token: payload['token'] as String,
        name: 'Télécommande',
      );
      expect(connected, isTrue, reason: 'le client doit se connecter');
      await pump();
      expect(host.hasConnectedClients, isTrue);

      // Le client envoie, l'hôte traduit en commandes du bus.
      final received = <PlayerCommand>[];
      final subscription = host.remoteCommands.listen(received.add);

      client.sendCommand(const TogglePlay());
      await pump();
      expect(received.last, isA<TogglePlay>());

      client.sendCommand(const SeekRelative(10));
      await pump();
      expect(
        received.last,
        isA<SeekRelative>().having((c) => c.seconds, 'seconds', 10),
      );

      client.sendCommand(const VolumeRelative(-5));
      await pump();
      expect(
        received.last,
        isA<VolumeRelative>().having((c) => c.delta, 'delta', -5),
      );

      client.sendCommand(const NextFile());
      await pump();
      expect(received.last, isA<NextFile>());

      await subscription.cancel();
      await client.disconnect();
    });

    test("l'hôte diffuse son état de lecture au client", () async {
      final payload = jsonDecode(await host.getPairingPayload('Hôte'))
          as Map<String, Object?>;

      final client = OmniaConnectClient();
      await client.connect(
        host: '127.0.0.1',
        port: port,
        token: payload['token'] as String,
      );
      await pump();

      final future =
          client.remoteState.first.timeout(const Duration(seconds: 5));

      host.broadcastState(
        PlaybackState(
          status: PlaybackStatus.playing,
          file: const MediaFile(path: 'film.mkv', type: MediaType.video),
          position: const Duration(seconds: 5),
          duration: const Duration(seconds: 100),
          volume: 80,
        ),
      );

      final state = await future;
      expect(state.status, PlaybackStatus.playing);
      expect(state.position, const Duration(seconds: 5));
      expect(state.duration, const Duration(seconds: 100));
      expect(state.volume, 80);
      expect(state.file?.path, 'film.mkv');

      await client.disconnect();
    });

    test('un jeton erroné est refusé', () async {
      final client = OmniaConnectClient();
      final connected = await client.connect(
        host: '127.0.0.1',
        port: port,
        token: 'jeton-qui-ne-va-pas',
      );

      expect(connected, isFalse, reason: "l'hôte doit refuser un mauvais jeton");
      await pump();
      expect(host.hasConnectedClients, isFalse);

      await client.disconnect();
    });

    test('un appairage manuel depuis la machine même reste accepté', () async {
      // Cas du PC et du téléphone sur le même poste : le jeton peut manquer,
      // l'hôte accepte alors la connexion locale. Verrouillé ici car c'est le
      // repli qui sauve un appairage dont le QR code a mal été lu.
      final client = OmniaConnectClient();
      final connected = await client.connect(
        host: '127.0.0.1',
        port: port,
        token: '',
      );

      expect(connected, isTrue);
      await client.disconnect();
    });

    test("l'arrêt de l'hôte libère le port et déconnecte les clients",
        () async {
      final payload = jsonDecode(await host.getPairingPayload('Hôte'))
          as Map<String, Object?>;

      final client = OmniaConnectClient();
      await client.connect(
        host: '127.0.0.1',
        port: port,
        token: payload['token'] as String,
      );
      await pump();

      await host.stop();
      expect(host.isRunning, isFalse);
      expect(host.hasConnectedClients, isFalse);
      expect(host.sessionToken, isNull,
          reason: 'le jeton éphémère ne doit pas survivre à la session');

      // Le port doit pouvoir être repris : sinon l'hôte ne redémarre jamais.
      final relance = OmniaConnectService();
      addTearDown(relance.stop);
      await expectLater(
        relance.start(address: InternetAddress.loopbackIPv4),
        completion(greaterThan(0)),
      );
    });
  });
}
