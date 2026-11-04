import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/services/omnia_connect_service.dart';

/// Ce que le serveur reçoit vraiment : du texte, qu'il relit.
ConnectMessage recu(String wire) =>
    ConnectMessage.fromJson(jsonDecode(wire) as Map<String, Object?>);

void main() {
  group("Contrôle d'ordre des messages", () {
    test('des numéros qui montent passent', () {
      final gate = ConnectMessageGate();
      const msg = ConnectMessage(type: 'togglePlay');
      expect(gate.accepts(recu(msg.envelope(1))), isTrue);
      expect(gate.accepts(recu(msg.envelope(2))), isTrue);
      expect(gate.accepts(recu(msg.envelope(3))), isTrue);
    });

    test('le même message renvoyé est refusé', () {
      // Le défaut corrigé ici : rien ne distinguait une commande nouvelle
      // d'une commande captée sur le réseau et réémise telle quelle. Elle
      // était exécutée une seconde fois, et autant de fois qu'on la renvoyait.
      final gate = ConnectMessageGate();
      const msg = ConnectMessage(type: 'togglePlay');
      final capte = msg.envelope(1);
      expect(gate.accepts(recu(capte)), isTrue);
      expect(gate.accepts(recu(capte)), isFalse);
      expect(gate.accepts(recu(capte)), isFalse);
    });

    test('un numéro revenu en arrière est refusé', () {
      final gate = ConnectMessageGate();
      const msg = ConnectMessage(type: 'next');
      expect(gate.accepts(recu(msg.envelope(7))), isTrue);
      expect(gate.accepts(recu(msg.envelope(6))), isFalse);
      // Et la suite reprend au-dessus du plus haut numéro vu.
      expect(gate.accepts(recu(msg.envelope(8))), isTrue);
    });

    test('une version de protocole étrangère est refusée', () {
      final gate = ConnectMessageGate();
      final etranger = jsonEncode({
        'protocolVersion': connectProtocolVersion + 1,
        'seq': 1,
        'type': 'togglePlay',
        'payload': const <String, Object?>{},
      });
      expect(gate.accepts(recu(etranger)), isFalse);
    });

    test('un message sans enveloppe est refusé', () {
      // Un émetteur d'avant l'enveloppe, ou quelqu'un qui l'omet exprès :
      // dans les deux cas on ne peut rien vérifier, et un message qu'on ne
      // peut pas vérifier ne commande pas le lecteur.
      final gate = ConnectMessageGate();
      final nu = jsonEncode({
        'type': 'togglePlay',
        'payload': const <String, Object?>{},
      });
      expect(gate.accepts(recu(nu)), isFalse);
    });

    test('chaque connexion a son propre compte', () {
      // Deux appareils appairés numérotent chacun de leur côté : le contrôle
      // de l'un ne doit pas rejeter les messages de l'autre.
      final premier = ConnectMessageGate();
      final second = ConnectMessageGate();
      const msg = ConnectMessage(type: 'previous');
      expect(premier.accepts(recu(msg.envelope(5))), isTrue);
      expect(second.accepts(recu(msg.envelope(1))), isTrue);
    });
  });

  group('Comparaison de jetons', () {
    test('seul le jeton exact est reconnu', () {
      expect(OmniaConnectService.sameToken('abc', 'abc'), isTrue);
      expect(OmniaConnectService.sameToken('abc', 'abd'), isFalse);
      expect(OmniaConnectService.sameToken('abc', 'ab'), isFalse);
      expect(OmniaConnectService.sameToken('', ''), isTrue);
      expect(OmniaConnectService.sameToken(null, 'abc'), isFalse);
      expect(OmniaConnectService.sameToken('abc', null), isFalse);
      expect(OmniaConnectService.sameToken(null, null), isFalse);
    });
  });
}
