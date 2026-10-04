import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/commands/player_command.dart';
import 'package:omnia_mobile/core/models/playback_state.dart';
import 'package:omnia_mobile/core/models/playback_status.dart';
import 'package:omnia_mobile/core/services/omnia_connect_service.dart';

void main() {
  group('OmniaConnectService (Zero-Internet Protocol)', () {
    late OmniaConnectService service;

    setUp(() {
      service = OmniaConnectService(port: 0); // Port dynamique
    });

    tearDown(() async {
      await service.stop();
      service.dispose();
    });

    test('start initializes local server and generates session token', () async {
      final port = await service.start();
      expect(port, greaterThan(0));
      expect(service.isRunning, isTrue);
      expect(service.sessionToken, isNotNull);
      expect(service.sessionToken!.length, greaterThan(10));
    });

    test('pairing payload generates valid JSON structure', () async {
      await service.start();
      final payload = await service.getPairingPayload('Test Phone');
      final decoded = jsonDecode(payload) as Map<String, Object?>;

      expect(decoded['protocol'], 'omnia-connect');
      expect(decoded['version'], '1.0');
      expect(decoded['name'], 'Test Phone');
      expect(decoded['token'], service.sessionToken);
      expect(decoded['port'], isNotNull);
    });

    test('stop closes server and revokes session', () async {
      await service.start();
      expect(service.isRunning, isTrue);

      await service.stop();
      expect(service.isRunning, isFalse);
      expect(service.sessionToken, isNull);
    });

    test('OmniaConnectClient connects, sends commands and receives state', () async {
      final port = await service.start(address: InternetAddress.loopbackIPv4);
      final client = OmniaConnectClient();

      final ok = await client.connect(
        host: '127.0.0.1',
        port: port,
        token: service.sessionToken!,
        name: 'Client Test',
      );
      expect(ok, isTrue);
      expect(client.connected, isTrue);

      final cmdFuture = service.remoteCommands.first;
      client.sendCommand(const NextFile());
      final cmd = await cmdFuture;
      expect(cmd, isA<NextFile>());

      final stateFuture = client.remoteState.first;
      service.broadcastState(
        const PlaybackState(
          status: PlaybackStatus.paused,
          position: Duration(seconds: 15),
          duration: Duration(minutes: 3),
        ),
      );
      final remoteState = await stateFuture;
      expect(remoteState.status, PlaybackStatus.paused);
      expect(remoteState.position, const Duration(seconds: 15));

      await client.disconnect();
      client.dispose();
    });
  });

  group('Projection du téléphone vers le PC', () {
    test('buildStreamUrl encode le chemin et le jeton', () {
      final url = OmniaConnectService.buildStreamUrl(
        host: '192.168.43.1',
        port: 41530,
        token: 'ab/c+=',
        path: '/storage/emulated/0/Movies/ete 2024.mp4',
      );

      expect(url, startsWith('http://192.168.43.1:41530/api/stream?'));
      expect(url, contains('token=ab%2Fc%2B%3D'));
      // Un chemin non encode casserait la requete des le premier espace.
      expect(url, contains('path=%2Fstorage'));
      expect(url, isNot(contains(' ')));
    });

    test('isProjectableHost ecarte les adresses injoignables', () {
      expect(OmniaConnectService.isProjectableHost('192.168.43.1'), isTrue);
      expect(OmniaConnectService.isProjectableHost('10.0.0.5'), isTrue);
      expect(OmniaConnectService.isProjectableHost('127.0.0.1'), isFalse);
      expect(OmniaConnectService.isProjectableHost('0.0.0.0'), isFalse);
      expect(OmniaConnectService.isProjectableHost(''), isFalse);
      expect(OmniaConnectService.isProjectableHost(null), isFalse);
    });

    test('projectFile fait ouvrir le flux par l appareil appaire', () async {
      final pc = OmniaConnectService(port: 0);
      final phone = OmniaConnectService(port: 0);
      addTearDown(() async {
        await phone.stop();
        phone.dispose();
        await pc.stop();
        pc.dispose();
      });

      final pcPort = await pc.start(address: InternetAddress.loopbackIPv4);
      final ok = await phone.client.connect(
        host: '127.0.0.1',
        port: pcPort,
        token: pc.sessionToken!,
        name: 'OMNIA Mobile',
      );
      expect(ok, isTrue);
      await phone.start(address: InternetAddress.loopbackIPv4);

      final ouverture = pc.remoteCommands.first;
      final url = await phone.projectFile('/storage/emulated/0/Movies/film.mkv');
      final commande = await ouverture.timeout(const Duration(seconds: 5));

      expect(url, isNotNull);
      expect(url, contains('/api/stream'));
      expect(url, contains(phone.sessionToken!));
      expect(commande, isA<OpenFile>());
      expect((commande as OpenFile).path, url);
    });

    test('le flux projete est servi avec le bon jeton, refuse sinon', () async {
      final phone = OmniaConnectService(port: 0);
      final client = HttpClient();
      addTearDown(() async {
        client.close();
        await phone.stop();
        phone.dispose();
      });

      final port = await phone.start(address: InternetAddress.loopbackIPv4);
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}omnia_projection_test.mkv',
      );
      await file.writeAsBytes(<int>[1, 2, 3, 4, 5]);
      addTearDown(() => file.deleteSync());

      final url = OmniaConnectService.buildStreamUrl(
        host: '127.0.0.1',
        port: port,
        token: phone.sessionToken!,
        path: file.path,
      );

      final ok = await client.getUrl(Uri.parse(url));
      final response = await ok.close();
      expect(response.statusCode, 200);
      final bytes = await response.expand((chunk) => chunk).toList();
      expect(bytes.length, 5);

      // Sans le jeton du serveur, le fichier reste prive : le PC recevrait
      // une erreur 401 au lieu de la video.
      final mauvais = await client.getUrl(
        Uri.parse(OmniaConnectService.buildStreamUrl(
          host: '127.0.0.1',
          port: port,
          token: 'mauvais-jeton',
          path: file.path,
        )),
      );
      final refus = await mauvais.close();
      expect(refus.statusCode, 401);
    });

    test('projectFile reste sans effet sans appairage actif', () async {
      final phone = OmniaConnectService(port: 0);
      addTearDown(() async {
        await phone.stop();
        phone.dispose();
      });

      expect(await phone.projectFile('/storage/film.mkv'), isNull);
      expect(await phone.projectFile(''), isNull);
    });
  });
}
