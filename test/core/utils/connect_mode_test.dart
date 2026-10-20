import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/utils/connect_mode.dart';

/// Les boutons Bluetooth / point d'accès / Wi-Fi n'enregistraient qu'une
/// préférence : aucun prérequis vérifié, aucun retour, et l'appairage échouait
/// plus tard sans que rien n'explique pourquoi. Ces tests vérifient le
/// diagnostic de chaque mode sur de fausses cartes réseau — une machine en a
/// plusieurs et toutes ne sont pas joignables depuis le téléphone.
void main() {
  group('Correspondance avec la préférence enregistrée', () {
    test('les trois modes font l\'aller-retour', () {
      for (final mode in ConnectMode.values) {
        expect(connectModeFromPreference(connectModePreference(mode)), mode);
      }
    });

    test('une préférence inconnue retombe sur le Wi-Fi local', () {
      expect(connectModeFromPreference('n\'importe quoi'), ConnectMode.wifi);
      expect(connectModeFromPreference(''), ConnectMode.wifi);
    });

    test('les intitulés sont en français', () {
      expect(ConnectMode.wifi.label, 'Wi-Fi local');
      expect(ConnectMode.hotspot.label, 'Point d\'accès');
      expect(ConnectMode.bluetooth.label, 'Bluetooth');
    });
  });

  group('Mode Wi-Fi local', () {
    test('une carte Wi-Fi du réseau local suffit', () {
      final report = ConnectModeInspector.inspect(
        mode: ConnectMode.wifi,
        interfaces: [_Carte('Wi-Fi', ['192.168.1.42'])],
      );
      expect(report.ready, isTrue);
      expect(report.address, '192.168.1.42');
      expect(report.problem, isNull);
    });

    test('les cartes virtuelles ne comptent pas pour une liaison', () {
      // Le piège du commit « annoncer une adresse que le téléphone peut
      // joindre » : la carte hôte de VirtualBox vient avant le Wi-Fi.
      final report = ConnectModeInspector.inspect(
        mode: ConnectMode.wifi,
        interfaces: [
          _Carte('VirtualBox Host-Only Network', ['192.168.56.1']),
          _Carte('docker0', ['172.17.0.1']),
          _Carte('Wi-Fi', ['192.168.1.42']),
        ],
      );
      expect(report.address, '192.168.1.42');
    });

    test('rien que des cartes virtuelles : on le dit et on guide', () {
      final report = ConnectModeInspector.inspect(
        mode: ConnectMode.wifi,
        interfaces: [
          _Carte('vEthernet (WSL)', ['172.24.16.1']),
          _Carte('tun0', ['10.8.0.6']),
        ],
      );
      expect(report.ready, isFalse);
      expect(report.problem, contains('virtuelles'));
      expect(report.guidance, contains('VPN'));
      // On annonce quand même quelque chose : mieux vaut une adresse
      // incertaine que la boucle locale, qui ne joint personne.
      expect(report.announcedAddress, isNotNull);
    });

    test('aucun réseau du tout : on dit d\'activer le Wi-Fi', () {
      final report = ConnectModeInspector.inspect(
        mode: ConnectMode.wifi,
        interfaces: [_Carte('lo', ['127.0.0.1'])],
      );
      expect(report.ready, isFalse);
      expect(report.problem, contains('aucun réseau'));
      expect(report.guidance, contains('Wi-Fi'));
      expect(report.announcedAddress, isNull);
    });

    test('un point d\'accès actif oriente vers le bon mode', () {
      final report = ConnectModeInspector.inspect(
        mode: ConnectMode.wifi,
        interfaces: [_Carte('ap0', ['192.168.43.1'])],
      );
      expect(report.ready, isFalse);
      expect(report.guidance, contains('Point d\'accès'));
    });

    test('une adresse publique n\'est pas un réseau local', () {
      final report = ConnectModeInspector.inspect(
        mode: ConnectMode.wifi,
        interfaces: [
          // 172.32.x est public : seul 172.16–172.31 est privé.
          _Carte('eth0', ['172.32.5.5']),
          _Carte('wlan0', ['192.168.1.9']),
        ],
      );
      expect(report.address, '192.168.1.9');
    });
  });

  group('Mode point d\'accès', () {
    test('l\'interface du point d\'accès est retenue', () {
      final report = ConnectModeInspector.inspect(
        mode: ConnectMode.hotspot,
        interfaces: [
          _Carte('wlan0', ['192.168.1.42']),
          _Carte('ap0', ['192.168.43.1']),
        ],
      );
      expect(report.ready, isTrue);
      expect(report.address, '192.168.43.1',
          reason: 'c\'est cette adresse que l\'autre appareil joint');
    });

    test('le sous-réseau de partage Android trahit un nom inconnu', () {
      // Le nom d'interface varie selon le fabricant, le sous-réseau non.
      final report = ConnectModeInspector.inspect(
        mode: ConnectMode.hotspot,
        interfaces: [_Carte('rmnet_data0', ['192.168.43.1'])],
      );
      expect(report.address, '192.168.43.1');
    });

    test('le point d\'accès mobile de Windows est reconnu', () {
      final report = ConnectModeInspector.inspect(
        mode: ConnectMode.hotspot,
        interfaces: [
          _Carte('Connexion réseau locale* 12', ['192.168.137.1']),
        ],
      );
      expect(report.ready, isTrue);
      expect(report.address, '192.168.137.1');
    });

    test('aucun partage actif : on dit lequel activer', () {
      final report = ConnectModeInspector.inspect(
        mode: ConnectMode.hotspot,
        interfaces: [_Carte('wlan0', ['192.168.1.42'])],
      );
      expect(report.ready, isFalse);
      expect(report.problem, contains('Aucun point d\'accès'));
      expect(report.guidance, contains('partage de connexion'));
    });

    test('rien du tout : on guide quand même', () {
      final report = ConnectModeInspector.inspect(
        mode: ConnectMode.hotspot,
        interfaces: const [],
      );
      expect(report.ready, isFalse);
      expect(report.guidance, isNotNull);
    });
  });

  group('Mode Bluetooth', () {
    test('un lien PAN actif est retenu', () {
      final report = ConnectModeInspector.inspect(
        mode: ConnectMode.bluetooth,
        interfaces: [
          _Carte('wlan0', ['192.168.1.42']),
          _Carte('bnep0', ['192.168.44.1']),
        ],
      );
      expect(report.ready, isTrue);
      expect(report.address, '192.168.44.1');
    });

    test('le nom Windows du lien Bluetooth est reconnu', () {
      final report = ConnectModeInspector.inspect(
        mode: ConnectMode.bluetooth,
        interfaces: [
          _Carte('Bluetooth Network Connection', ['192.168.137.5']),
        ],
      );
      expect(report.ready, isTrue);
      expect(report.address, '192.168.137.5');
    });

    test('sans lien PAN, aucune adresse n\'est annoncée', () {
      // Le piège à éviter absolument : publier l'adresse Wi-Fi pour un lien
      // Bluetooth qui n'existe pas. Le code d'appairage serait injoignable et
      // l'échec resterait inexpliqué.
      final report = ConnectModeInspector.inspect(
        mode: ConnectMode.bluetooth,
        interfaces: [_Carte('wlan0', ['192.168.1.42'])],
      );
      expect(report.ready, isFalse);
      expect(report.address, isNull);
      expect(report.announcedAddress, isNull);
      expect(report.problem, contains('PAN'));
      expect(report.guidance, contains('partage de connexion par Bluetooth'));
      expect(report.guidance, contains('proximité'),
          reason: 'la permission « appareils à proximité » doit être citée');
    });
  });

  group('Quand le système ne répond pas', () {
    test('la sonde est bornée dans le temps', () {
      // Sans borne, l'encart de l'interface resterait en « vérification »
      // indéfiniment : un panneau qui tourne sans fin vaut le bouton qui ne
      // fait rien, dont l'utilisateur se plaint déjà.
      expect(ConnectModeInspector.probeTimeout.inSeconds, greaterThan(0));
      expect(ConnectModeInspector.probeTimeout.inSeconds, lessThanOrEqualTo(5));
    });

    test('l\'échec est dit et la relance proposée, pour les trois modes', () {
      for (final mode in ConnectMode.values) {
        final report = ConnectModeInspector.unavailable(mode);
        expect(report.ready, isFalse);
        expect(report.announcedAddress, isNull);
        expect(report.problem, contains('cartes réseau'));
        expect(report.guidance, contains('relancez la vérification'));
        expect(report.message, contains(report.problem!));
      }
    });
  });

  group('Tout rapport parle à l\'utilisateur', () {
    final cases = <String, List<NetworkInterface>>{
      'aucune carte': const [],
      'boucle locale seule': [_Carte('lo', ['127.0.0.1'])],
      'carte virtuelle seule': [_Carte('docker0', ['172.17.0.1'])],
      'Wi-Fi seul': [_Carte('wlan0', ['192.168.1.5'])],
      'point d\'accès seul': [_Carte('ap0', ['192.168.43.1'])],
      'lien Bluetooth seul': [_Carte('bnep0', ['192.168.44.1'])],
    };

    cases.forEach((label, interfaces) {
      for (final mode in ConnectMode.values) {
        test('$label en mode ${mode.label} : jamais d\'échec muet', () {
          final report = ConnectModeInspector.inspect(
            mode: mode,
            interfaces: interfaces,
          );
          expect(report.message.trim(), isNotEmpty);
          if (!report.ready) {
            expect(report.problem, isNotNull,
                reason: 'il faut dire ce qui manque');
            expect(report.guidance, isNotNull,
                reason: 'il faut dire quoi faire');
          } else {
            expect(report.message, contains(report.address!));
          }
        });
      }
    });
  });
}

/// Fausse carte réseau, pour éprouver le diagnostic sans matériel.
class _Carte implements NetworkInterface {
  _Carte(this.name, List<String> ips)
      : addresses = [for (final ip in ips) InternetAddress(ip)];

  @override
  final String name;

  @override
  final List<InternetAddress> addresses;

  @override
  int get index => 0;
}
