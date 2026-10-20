import 'dart:io';

/// Technologie choisie pour relier les deux appareils.
enum ConnectMode {
  /// Les deux appareils sur le même réseau local, Wi-Fi ou Ethernet.
  wifi,

  /// L'un des deux appareils sert de point d'accès à l'autre.
  hotspot,

  /// Lien réseau porté par Bluetooth (profil PAN).
  bluetooth,
}

/// Correspondance avec la préférence enregistrée, qui reste une chaîne pour ne
/// pas casser les réglages déjà écrits sur le disque.
ConnectMode connectModeFromPreference(String raw) => switch (raw) {
      'hotspot' => ConnectMode.hotspot,
      'bluetooth' => ConnectMode.bluetooth,
      _ => ConnectMode.wifi,
    };

String connectModePreference(ConnectMode mode) => switch (mode) {
      ConnectMode.hotspot => 'hotspot',
      ConnectMode.bluetooth => 'bluetooth',
      ConnectMode.wifi => 'wifi',
    };

extension ConnectModeLabel on ConnectMode {
  /// Nom du mode tel qu'il est écrit dans l'interface.
  String get label => switch (this) {
        ConnectMode.hotspot => 'Point d\'accès',
        ConnectMode.bluetooth => 'Bluetooth',
        ConnectMode.wifi => 'Wi-Fi local',
      };
}

/// Ce qu'on a trouvé en vérifiant les prérequis d'un mode de liaison.
///
/// Les boutons de mode se contentaient d'enregistrer la préférence : aucun
/// contrôle, aucun retour, et l'appairage échouait plus tard sans que rien
/// n'explique pourquoi. Un rapport porte donc soit l'adresse à annoncer, soit
/// ce qui manque **et** la marche à suivre, en français.
class ConnectModeReport {
  const ConnectModeReport({
    required this.mode,
    this.address,
    this.fallback,
    this.problem,
    this.guidance,
  });

  final ConnectMode mode;

  /// Adresse que l'autre appareil peut effectivement joindre, ou `null`.
  final String? address;

  /// Adresse à annoncer faute de mieux : mieux vaut une adresse incertaine
  /// que la boucle locale, qui ne joint que l'appareil qui l'annonce. Reste
  /// nulle en Bluetooth : publier une adresse Wi-Fi pour un lien PAN absent
  /// est exactement le piège à éviter.
  final String? fallback;

  /// Adresse à publier dans le code d'appairage.
  String? get announcedAddress => address ?? fallback;

  /// Ce qui manque, dit simplement. `null` quand tout est en place.
  final String? problem;

  /// Ce que l'utilisateur doit faire pour que ça marche.
  final String? guidance;

  /// Vrai quand le mode est utilisable en l'état.
  bool get ready => address != null && problem == null;

  /// Message prêt à afficher : le constat puis la marche à suivre.
  String get message {
    if (ready) {
      return 'Mode ${mode.label} prêt — annoncez l\'adresse $address à '
          'l\'autre appareil.';
    }
    return [problem, guidance].whereType<String>().join(' ');
  }
}

/// Contrôle des prérequis d'un mode de liaison, à partir des cartes réseau.
///
/// Séparé de l'appel système pour être vérifiable avec de fausses cartes : un
/// poste a plusieurs interfaces et toutes ne sont pas joignables depuis le
/// téléphone.
class ConnectModeInspector {
  const ConnectModeInspector._();

  /// Délai au bout duquel on renonce à interroger le système.
  ///
  /// Lire les cartes réseau peut rester sans réponse — pilote en faute,
  /// permission refusée sur Android. Sans borne, l'encart de l'interface
  /// resterait en « vérification » indéfiniment : l'utilisateur verrait un
  /// panneau qui tourne sans fin au lieu d'une raison et d'une marche à
  /// suivre.
  static const Duration probeTimeout = Duration(seconds: 3);

  /// Rapport rendu quand le système n'a pas répondu à temps, ou pas du tout.
  static ConnectModeReport unavailable(ConnectMode mode) => ConnectModeReport(
        mode: mode,
        problem: 'Impossible de lire les cartes réseau de cet appareil.',
        guidance: 'Vérifiez que le système autorise OMNIA à voir le réseau et '
            'les appareils à proximité, puis relancez la vérification.',
      );

  /// Examine [interfaces] pour le [mode] demandé.
  static ConnectModeReport inspect({
    required ConnectMode mode,
    required List<NetworkInterface> interfaces,
  }) {
    String? station;
    String? accessPoint;
    String? bluetooth;
    String? virtualOnly;
    var sawLoopbackOnly = true;

    for (final iface in interfaces) {
      final name = iface.name.toLowerCase();
      for (final addr in iface.addresses) {
        final ip = addr.address;
        if (addr.isLoopback || ip.startsWith('127.')) continue;
        sawLoopbackOnly = false;

        if (_isBluetoothInterface(name)) {
          bluetooth ??= ip;
          continue;
        }
        if (_isAccessPointInterface(name) || _isAccessPointSubnet(ip)) {
          accessPoint ??= ip;
          continue;
        }
        if (_isVirtualInterface(name)) {
          virtualOnly ??= ip;
          continue;
        }
        if (_isPrivateAddress(ip)) {
          station ??= ip;
        } else {
          virtualOnly ??= ip;
        }
      }
    }

    return switch (mode) {
      ConnectMode.wifi => _wifiReport(
          station: station,
          accessPoint: accessPoint,
          virtualOnly: virtualOnly,
          nothingButLoopback: sawLoopbackOnly,
        ),
      ConnectMode.hotspot => _hotspotReport(
          accessPoint: accessPoint,
          station: station,
          virtualOnly: virtualOnly,
        ),
      ConnectMode.bluetooth => _bluetoothReport(bluetooth: bluetooth),
    };
  }

  static ConnectModeReport _wifiReport({
    required String? station,
    required String? accessPoint,
    required String? virtualOnly,
    required bool nothingButLoopback,
  }) {
    if (station != null) {
      return ConnectModeReport(mode: ConnectMode.wifi, address: station);
    }
    if (accessPoint != null) {
      // Un point d'accès est actif mais le mode demandé est le Wi-Fi local :
      // l'adresse existe, autant le dire plutôt que de prétendre qu'il n'y a
      // rien.
      return ConnectModeReport(
        mode: ConnectMode.wifi,
        fallback: accessPoint,
        problem: 'Aucun réseau Wi-Fi ou Ethernet rejoint, mais un point '
            'd\'accès est actif sur cet appareil.',
        guidance: 'Choisissez le mode « Point d\'accès », ou connectez les '
            'deux appareils au même réseau Wi-Fi.',
      );
    }
    if (virtualOnly != null) {
      return ConnectModeReport(
        mode: ConnectMode.wifi,
        fallback: virtualOnly,
        problem: 'Les seules cartes réseau trouvées sont virtuelles (VPN, '
            'machine virtuelle, conteneur) : l\'autre appareil ne peut pas '
            'les joindre.',
        guidance: 'Coupez le VPN ou connectez cet appareil au Wi-Fi du lieu, '
            'puis rouvrez OMNIA Connect.',
      );
    }
    if (nothingButLoopback) {
      return const ConnectModeReport(
        mode: ConnectMode.wifi,
        problem: 'Cet appareil n\'est sur aucun réseau : seule la boucle '
            'locale répond.',
        guidance: 'Activez le Wi-Fi et rejoignez le même réseau que l\'autre '
            'appareil, puis rouvrez OMNIA Connect.',
      );
    }
    return const ConnectModeReport(
      mode: ConnectMode.wifi,
      problem: 'Aucune adresse de réseau local n\'a été trouvée.',
      guidance: 'Vérifiez que le Wi-Fi est activé et que les deux appareils '
          'sont sur le même réseau.',
    );
  }

  static ConnectModeReport _hotspotReport({
    required String? accessPoint,
    required String? station,
    required String? virtualOnly,
  }) {
    if (accessPoint != null) {
      return ConnectModeReport(
        mode: ConnectMode.hotspot,
        address: accessPoint,
      );
    }
    if (station != null) {
      return ConnectModeReport(
        mode: ConnectMode.hotspot,
        fallback: station,
        problem: 'Aucun point d\'accès actif sur cet appareil, mais il est '
            'connecté à un réseau Wi-Fi.',
        guidance: 'Activez le partage de connexion, ou choisissez le mode '
            '« Wi-Fi local » si les deux appareils sont déjà sur le même '
            'réseau.',
      );
    }
    return ConnectModeReport(
      mode: ConnectMode.hotspot,
      fallback: virtualOnly,
      problem: 'Aucun point d\'accès actif.',
      guidance: 'Activez le partage de connexion sur cet appareil, connectez-y '
          'l\'autre appareil, puis rouvrez OMNIA Connect.',
    );
  }

  static ConnectModeReport _bluetoothReport({required String? bluetooth}) {
    if (bluetooth != null) {
      return ConnectModeReport(
        mode: ConnectMode.bluetooth,
        address: bluetooth,
      );
    }
    // Le Bluetooth seul ne transporte pas de réseau : OMNIA Connect parle
    // HTTP, il lui faut le profil PAN. Sans lui il n'y a aucune adresse à
    // annoncer, et publier une adresse injoignable est le pire des cas.
    return const ConnectModeReport(
      mode: ConnectMode.bluetooth,
      problem: 'Aucun lien réseau Bluetooth (PAN) actif.',
      guidance: 'Activez le Bluetooth sur les deux appareils, appairez-les, '
          'autorisez l\'accès aux appareils à proximité, puis activez le '
          'partage de connexion par Bluetooth. Le Bluetooth seul ne suffit '
          'pas : OMNIA Connect a besoin du réseau qu\'il transporte.',
    );
  }

  /// Interface d'un point d'accès servi par cet appareil.
  static bool _isAccessPointInterface(String name) =>
      name.startsWith('ap') ||
      name.contains('swlan') ||
      name.contains('wlan1') ||
      name.contains('hotspot') ||
      name.contains('wi-fi direct') ||
      name.contains('wifi direct');

  /// Sous-réseaux de partage de connexion : Android annonce 192.168.43.x,
  /// le point d'accès mobile de Windows 192.168.137.x. Le nom de l'interface
  /// varie selon le fabricant, le sous-réseau non.
  static bool _isAccessPointSubnet(String ip) =>
      ip.startsWith('192.168.43.') || ip.startsWith('192.168.137.');

  static bool _isBluetoothInterface(String name) =>
      name.contains('bnep') ||
      name.contains('bt-pan') ||
      name.contains('bluetooth') ||
      name.startsWith('bt');

  /// Cartes qui ne joignent pas le réseau de l'utilisateur : hôte des machines
  /// virtuelles, ponts de conteneurs, liens VPN.
  static bool _isVirtualInterface(String name) {
    const marks = [
      'vboxnet', 'virtualbox', 'vmware', 'vmnet', 'docker', 'br-', 'virbr',
      'veth', 'lxc', 'lxd', 'tun', 'tap', 'wsl', 'vethernet', 'hyper-v',
      'hamachi', 'zerotier', 'tailscale', 'wg', 'cni', 'flannel', 'kube',
      'podman', 'rndis', 'nordlynx', 'proton', 'ppp', 'utun',
    ];
    for (final mark in marks) {
      if (name.contains(mark)) return true;
    }
    return false;
  }

  /// Adresse d'un réseau local au sens RFC 1918 : c'est de là que l'autre
  /// appareil joindra celui-ci.
  static bool _isPrivateAddress(String ip) {
    if (ip.startsWith('192.168.') || ip.startsWith('10.')) return true;
    // 172.16.0.0 – 172.31.255.255 seulement : le reste de 172.x est public,
    // et une adresse publique n'est pas joignable depuis l'autre appareil.
    final parts = ip.split('.');
    if (parts.length == 4 && parts[0] == '172') {
      final second = int.tryParse(parts[1]);
      return second != null && second >= 16 && second <= 31;
    }
    return false;
  }
}
