import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
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
  });
}
