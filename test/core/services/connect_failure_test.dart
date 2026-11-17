// Même fichier dans les dépôts bureau et mobile, aux imports près.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/services/omnia_connect_service.dart';
import 'package:omnia_mobile/core/utils/pairing_code.dart';

/// Un port où personne n'écoute : ouvert puis aussitôt refermé.
Future<int> _closedPort() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  await server.close(force: true);
  return port;
}

void main() {
  test('chaque cause d’échec a sa phrase', () {
    expect(
      describeConnectFailure(TimeoutException('délai')).reason,
      startsWith('pas de réponse'),
    );
    expect(
      describeConnectFailure(const SocketException('x', osError: OSError('refused', 111))).reason,
      startsWith('connexion refusée'),
    );
    expect(
      describeConnectFailure(const SocketException('x', osError: OSError('refused', 10061))).reason,
      startsWith('connexion refusée'),
    );
    expect(
      describeConnectFailure(const SocketException('x', osError: OSError('no route', 113))).reason,
      'adresse injoignable depuis ce réseau',
    );
    expect(
      describeConnectFailure(const SocketException('x', osError: OSError('disque', 5))).reason,
      contains('disque'),
    );
    expect(describeConnectFailure(StateError('?')).reason, 'échec inattendu');

    // Seul un refus de l'autre appareil est définitif.
    expect(describeConnectFailure(const WebSocketException('not upgraded')).definitive, isTrue);
    expect(describeConnectFailure(TimeoutException('délai')).definitive, isFalse);
  });

  test('un port fermé est nommé comme tel', () async {
    final port = await _closedPort();
    final client = OmniaConnectClient();
    addTearDown(client.dispose);

    final ok = await client.connectAny(PairingTarget(host: '127.0.0.1', port: port));

    expect(ok, isFalse);
    expect(client.lastFailures.keys, ['127.0.0.1']);
    expect(client.lastFailures['127.0.0.1']!.reason, startsWith('connexion refusée'));
  });

  group('avec un appareil qui écoute', () {
    late OmniaConnectService host;
    late int port;

    setUp(() async {
      host = OmniaConnectService(port: 0);
      port = await host.start(address: InternetAddress.loopbackIPv4);
    });

    tearDown(() async {
      await host.stop();
      host.dispose();
    });

    test('un code refusé est définitif', () async {
      final client = OmniaConnectClient();
      addTearDown(client.dispose);

      final ok = await client.connectAny(
        PairingTarget(host: '127.0.0.1', port: port, token: 'mauvais-jeton'),
      );

      expect(ok, isFalse);
      expect(client.lastFailures['127.0.0.1']!.definitive, isTrue);
    });

    test('une adresse morte n’empêche pas la suivante, et rien ne reste', () async {
      final client = OmniaConnectClient();
      addTearDown(client.dispose);

      // 127.0.0.2 est une boucle locale où le serveur n'écoute pas : refus
      // immédiat, puis la bonne adresse.
      final ok = await client.connectAny(
        PairingTarget(
          host: '127.0.0.2',
          port: port,
          token: host.sessionToken!,
          alternates: const ['127.0.0.1'],
        ),
      );

      expect(ok, isTrue);
      expect(client.connected, isTrue);
      expect(client.lastFailures, isEmpty);
      await client.disconnect();
    });
  });
}
