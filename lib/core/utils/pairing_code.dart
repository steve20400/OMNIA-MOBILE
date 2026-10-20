import 'dart:convert';

/// Appareil visé par un appairage : ce qu'il faut pour ouvrir la liaison.
class PairingTarget {
  const PairingTarget({
    required this.host,
    required this.port,
    this.token = '',
  });

  final String host;
  final int port;

  /// Jeton de session. Vide pour une saisie manuelle : l'hôte accepte un
  /// client du réseau local sans jeton, c'est ce qui rend le repli possible.
  final String token;

  @override
  bool operator ==(Object other) =>
      other is PairingTarget &&
      other.host == host &&
      other.port == port &&
      other.token == token;

  @override
  int get hashCode => Object.hash(host, port, token);

  @override
  String toString() => 'PairingTarget($host:$port'
      '${token.isEmpty ? '' : ', jeton de ${token.length} caractères'})';
}

/// Lecture et écriture du code d'appairage saisi à la main.
///
/// C'est le repli indispensable quand le scan échoue, et il doit marcher du
/// premier coup : l'utilisateur recopie à l'œil ce que l'autre écran affiche,
/// avec les approximations que cela suppose. Cette classe accepte donc tout ce
/// qu'une personne peut raisonnablement taper — espaces en trop, deux-points
/// manquant, guillemets collés par un copier-coller, adresse lue avec un « O »
/// pour un zéro — au lieu de n'accepter qu'une forme canonique et d'échouer en
/// silence sur tout le reste.
class PairingCode {
  const PairingCode._();

  /// Port d'écoute d'OMNIA Connect, repris quand la saisie n'en donne pas.
  static const int defaultPort = 41530;

  /// Code à afficher en face de l'utilisateur, à recopier sur l'autre
  /// appareil. Rien que des chiffres et deux séparateurs : aucune lettre, donc
  /// aucune confusion possible entre O et 0 ou entre l et 1.
  static String format({required String host, required int port}) =>
      '$host:$port';

  /// Interprète [raw] : saisie manuelle, payload JSON du QR code, ou URL.
  ///
  /// Renvoie `null` quand il n'y a décidément pas d'adresse à y lire, pour que
  /// l'interface puisse le dire à l'utilisateur plutôt que de tenter une
  /// connexion vers n'importe quoi.
  static PairingTarget? parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final fromJson = _parseJson(trimmed);
    if (fromJson != null) return fromJson;

    final fromUri = _parseUri(trimmed);
    if (fromUri != null) return fromUri;

    return _parsePlain(trimmed);
  }

  /// Payload du QR code, ou collé depuis le presse-papier de l'autre appareil.
  static PairingTarget? _parseJson(String text) {
    if (!text.startsWith('{')) return null;
    try {
      final map = jsonDecode(text) as Map<String, Object?>;
      final host = (map['host'] as String? ?? '').trim();
      if (host.isEmpty) return null;
      final port = (map['port'] as num?)?.toInt() ?? defaultPort;
      return PairingTarget(
        host: host,
        port: _validPort(port) ? port : defaultPort,
        token: (map['token'] as String? ?? '').trim(),
      );
    } catch (_) {
      // JSON tronqué par un copier-coller partiel : on laisse la lecture en
      // clair tenter d'y retrouver une adresse.
      return null;
    }
  }

  /// `ws://192.168.1.24:41530/api/ws?token=…` et consorts : c'est ce qu'on
  /// obtient en copiant une URL de flux depuis les journaux ou un message.
  static PairingTarget? _parseUri(String text) {
    if (!text.contains('://')) return null;
    final uri = Uri.tryParse(_stripWrappers(text));
    if (uri == null || uri.host.isEmpty) return null;
    final port = uri.hasPort ? uri.port : defaultPort;
    return PairingTarget(
      host: uri.host,
      port: port,
      token: uri.queryParameters['token']?.trim() ?? '',
    );
  }

  /// Saisie en clair : adresse, éventuellement un port, éventuellement un
  /// jeton, séparés par ce que l'utilisateur a sous la main.
  static PairingTarget? _parsePlain(String text) {
    final cleaned = _stripWrappers(text);

    // Une adresse IPv4, en tolérant les espaces autour des points et les
    // glyphes qu'on confond en recopiant : O pour 0, I ou l pour 1.
    final quad = RegExp(
      r'([0-9OoIl]{1,3})\s*\.\s*([0-9OoIl]{1,3})\s*\.\s*'
      r'([0-9OoIl]{1,3})\s*\.\s*([0-9OoIl]{1,3})',
    ).firstMatch(cleaned);

    if (quad != null) {
      final octets = <int>[];
      for (var group = 1; group <= 4; group++) {
        final value = int.tryParse(_disambiguate(quad.group(group)!));
        if (value == null || value > 255) return null;
        octets.add(value);
      }
      final rest = cleaned.substring(quad.end);
      return PairingTarget(
        host: octets.join('.'),
        port: _portIn(rest) ?? defaultPort,
        token: _tokenIn(rest),
      );
    }

    // Pas d'adresse IPv4 : un nom d'hôte, qu'on ne touche pas — ses lettres
    // sont des lettres, pas des chiffres mal recopiés.
    final named = RegExp(r'^([A-Za-z0-9][A-Za-z0-9.\-_]*)\s*[:;\s]\s*(.*)$')
        .firstMatch(cleaned);
    if (named != null) {
      final rest = named.group(2)!;
      return PairingTarget(
        host: named.group(1)!,
        port: _portIn(rest) ?? defaultPort,
        token: _tokenIn(rest),
      );
    }
    // Un nom d'hôte seul, sans port. Un nombre nu n'en est pas un : taper
    // « 41530 » n'est pas donner une adresse, et mieux vaut le dire que
    // d'essayer de joindre un hôte nommé « 41530 ».
    if (RegExp(r'^[A-Za-z0-9][A-Za-z0-9.\-_]*$').hasMatch(cleaned) &&
        !RegExp(r'^[0-9]+$').hasMatch(cleaned)) {
      return PairingTarget(host: cleaned, port: defaultPort);
    }
    return null;
  }

  /// Premier nombre lisible de [text], espaces internes compris : le port tapé
  /// « 41 530 » est le même que « 41530 ».
  static int? _portIn(String text) {
    final match = RegExp(r'([0-9OoIl][0-9OoIl\s]{0,8})').firstMatch(text);
    if (match == null) return null;
    final digits = _disambiguate(match.group(1)!.replaceAll(RegExp(r'\s'), ''));
    final port = int.tryParse(digits);
    return port != null && _validPort(port) ? port : null;
  }

  /// Jeton éventuel : ce qui reste après le port et ressemble à du base64url.
  /// La casse et les glyphes y sont laissés tels quels — un jeton est opaque,
  /// le « corriger » le casserait.
  static String _tokenIn(String text) {
    final matches =
        RegExp(r'[A-Za-z0-9_=+/\-]{8,}').allMatches(text).toList();
    for (final match in matches) {
      final candidate = match.group(0)!;
      // Une suite de chiffres seule est un port, pas un jeton.
      if (RegExp(r'^[0-9]+$').hasMatch(candidate)) continue;
      return candidate;
    }
    return '';
  }

  /// Remplace les glyphes qu'on confond à l'œil par le chiffre attendu. Ne
  /// s'applique qu'à des groupes déjà reconnus comme numériques : ailleurs, un
  /// O est un O.
  static String _disambiguate(String group) => group
      .replaceAll(RegExp('[Oo]'), '0')
      .replaceAll(RegExp('[IilL]'), '1');

  /// Retire ce qu'un copier-coller colle autour du code : guillemets droits ou
  /// français, parenthèses, puces, ponctuation de fin de phrase.
  static String _stripWrappers(String text) {
    var out = text.trim();
    const pairs = {'«': '»', '(': ')', '[': ']', '<': '>', '"': '"', "'": "'"};
    var changed = true;
    while (changed && out.isNotEmpty) {
      changed = false;
      final first = out[0];
      final closing = pairs[first];
      if (closing != null && out.length > 1 && out.endsWith(closing)) {
        out = out.substring(1, out.length - 1).trim();
        changed = true;
      }
    }
    out = out.replaceAll(RegExp(r'^[\s"«»<>\[\]()‘’“”]+'), '');
    out = out.replaceAll(
        RegExp(r'[\s"«»<>\[\]().,;/‘’“”]+$'), '');
    return out.trim();
  }

  static bool _validPort(int port) => port > 0 && port <= 65535;
}
