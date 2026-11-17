// Transfert de fichiers d'OMNIA Connect. Fichier identique dans les dépôts
// bureau et mobile : toute modification se reporte dans l'autre.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// Chemin du serveur local par lequel un appareil sert le fichier proposé.
const String transferPath = '/api/transfer';

/// Délai pendant lequel une proposition reste servie.
///
/// Assez pour que la personne en face lise, choisisse son dossier et reçoive
/// un gros fichier sur une liaison lente ; pas assez pour qu'une proposition
/// oubliée reste ouverte toute la soirée.
const Duration transferLifetime = Duration(minutes: 30);

/// Un fichier proposé par un appareil à l'autre, tel qu'il voyage sur la
/// liaison.
///
/// La proposition ne porte ni chemin ni adresse : seulement de quoi décider
/// (nom, taille, expéditeur) et de quoi venir chercher le fichier (port et
/// jeton propres à cette proposition). L'adresse est celle d'où vient la
/// liaison, constatée par celui qui reçoit : il ne va jamais là où le
/// message lui dirait d'aller.
class TransferOffer {
  const TransferOffer({
    required this.id,
    required this.name,
    required this.size,
    required this.port,
    required this.token,
    this.from = '',
  });

  final String id;

  /// Nom du fichier chez l'expéditeur, sans son dossier.
  final String name;

  /// Taille annoncée, en octets. Le récepteur s'y tient : ni plus, ni moins.
  final int size;

  /// Port du serveur de l'expéditeur.
  final int port;

  /// Jeton propre à cette proposition : il n'ouvre que ce fichier-là.
  final String token;

  /// Nom de l'appareil qui propose, pour l'afficher.
  final String from;

  /// Taille maximale acceptée : 1 Tio. Au-delà, ce n'est plus un fichier.
  static const int maxSize = 1 << 40;

  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{8,64}$');
  static final RegExp _tokenPattern = RegExp(r'^[A-Za-z0-9_=-]{16,128}$');

  Map<String, Object?> toPayload() => {
        'id': id,
        'name': name,
        'size': size,
        'port': port,
        'token': token,
        'from': from,
      };

  /// La proposition portée par [payload], ou `null` si quoi que ce soit y
  /// est absent, mal formé ou hors bornes.
  ///
  /// Ces valeurs viennent du réseau : elles ne sont crues qu'une fois
  /// vérifiées une à une.
  static TransferOffer? fromPayload(Map<String, Object?> payload) {
    final id = payload['id'];
    final name = payload['name'];
    final size = payload['size'];
    final port = payload['port'];
    final token = payload['token'];
    final from = payload['from'];
    if (id is! String || !_idPattern.hasMatch(id)) return null;
    if (name is! String || name.trim().isEmpty || name.length > 1024) return null;
    if (size is! int || size < 0 || size > maxSize) return null;
    if (port is! int || port < 1 || port > 65535) return null;
    if (token is! String || !_tokenPattern.hasMatch(token)) return null;
    return TransferOffer(
      id: id,
      name: name,
      size: size,
      port: port,
      token: token,
      from: from is String && from.length <= 80 ? from : '',
    );
  }
}

/// Une proposition reçue, et l'adresse d'où elle est venue.
class IncomingTransfer {
  const IncomingTransfer({required this.offer, required this.host});

  final TransferOffer offer;

  /// Adresse de l'appareil qui propose, telle que la liaison l'a constatée.
  final String host;

  /// Où venir chercher le fichier.
  Uri get url => Uri.http(
        '$host:${offer.port}',
        transferPath,
        <String, String>{'id': offer.id, 'token': offer.token},
      );
}

/// Où en est une proposition, vu de celui qui la reçoit.
enum TransferReplyKind {
  /// Accepté : le fichier est en cours de réception.
  accepted,

  /// Refusé, ou fenêtre fermée sans répondre.
  declined,

  /// Reçu en entier, et rangé.
  completed,

  /// Commencé, mais pas abouti.
  failed,
}

/// La réponse de celui qui reçoit, renvoyée à celui qui propose.
class TransferReply {
  const TransferReply({required this.id, required this.kind, this.message = ''});

  final String id;
  final TransferReplyKind kind;

  /// Cause d'un échec, à afficher chez l'expéditeur.
  final String message;

  /// Vrai quand la proposition n'a plus de suite : refus, réussite ou échec.
  bool get isFinal => kind != TransferReplyKind.accepted;

  Map<String, Object?> toPayload() => {
        'id': id,
        'kind': kind.name,
        if (message.isNotEmpty) 'message': message,
      };

  static TransferReply? fromPayload(Map<String, Object?> payload) {
    final id = payload['id'];
    final kind = payload['kind'];
    final message = payload['message'];
    if (id is! String || id.isEmpty || id.length > 64) return null;
    if (kind is! String) return null;
    final known = TransferReplyKind.values.where((k) => k.name == kind);
    if (known.isEmpty) return null;
    return TransferReply(
      id: id,
      kind: known.single,
      message: message is String && message.length <= 500 ? message : '',
    );
  }
}

class _Outgoing {
  _Outgoing(this.path, this.offer, this.expires);

  final String path;
  final TransferOffer offer;
  final DateTime expires;
}

/// Les fichiers que cet appareil propose, et que lui seul sert.
///
/// Rien d'autre n'est servi : ni un chemin choisi par l'appareil d'en face,
/// ni un fichier dont la proposition a expiré ou a reçu sa réponse finale.
class OutgoingTransfers {
  OutgoingTransfers({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, _Outgoing> _offers = {};
  final Random _random = Random.secure();

  /// Propose [path] : rend la proposition à envoyer, ou `null` si le fichier
  /// n'existe pas.
  TransferOffer? offer(String path, {required int port, String from = ''}) {
    final file = File(path);
    if (!file.existsSync()) return null;
    _purge();
    final offer = TransferOffer(
      id: _randomText(12),
      name: p.basename(path),
      size: file.lengthSync(),
      port: port,
      token: _randomText(32),
      from: from,
    );
    _offers[offer.id] = _Outgoing(path, offer, _clock().add(transferLifetime));
    return offer;
  }

  /// Vrai tant que la proposition [id] est servie.
  bool isOpen(String id) {
    _purge();
    return _offers.containsKey(id);
  }

  /// Retire la proposition [id] : son fichier n'est plus servi.
  void close(String id) => _offers.remove(id);

  void _purge() {
    final now = _clock();
    _offers.removeWhere((_, o) => !o.expires.isAfter(now));
  }

  String _randomText(int bytes) => base64Url
      .encode(List<int>.generate(bytes, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  /// Sert `/api/transfer?id=…&token=…`.
  ///
  /// Une proposition inconnue et un jeton faux reçoivent la même réponse :
  /// rien ne doit permettre de deviner l'une en essayant l'autre.
  Future<void> serve(HttpRequest request) async {
    final response = request.response;
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }
    _purge();
    final query = request.uri.queryParameters;
    final entry = _offers[query['id']];
    if (entry == null || !_sameText(query['token'], entry.offer.token)) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final file = File(entry.path);
    if (!file.existsSync()) {
      // Supprimé ou déplacé depuis la proposition.
      response.statusCode = HttpStatus.gone;
      await response.close();
      return;
    }
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.binary;
    response.headers.contentLength = await file.length();
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    try {
      await response.addStream(file.openRead());
      await response.close();
    } on Object {
      // Le récepteur a interrompu : c'est lui qui annonce l'échec.
    }
  }

  /// Comparaison à temps constant, comme pour le jeton de session.
  static bool _sameText(String? given, String expected) {
    if (given == null || given.length != expected.length) return false;
    var difference = 0;
    for (var i = 0; i < given.length; i++) {
      difference |= given.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return difference == 0;
  }
}

/// Un transfert qui n'a pas abouti, et pourquoi, dit pour l'utilisateur.
class TransferException implements Exception {
  const TransferException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Noms que Windows réserve à des périphériques, quelle que soit l'extension.
const Set<String> _reservedNames = {
  'CON', 'PRN', 'AUX', 'NUL',
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
};

/// Nom de fichier sûr, tiré de celui qu'annonce l'expéditeur.
///
/// Seul le dernier segment est gardé, quel que soit le séparateur : un nom
/// comme « ../../.bashrc » ou « C:\Windows\system.ini » ne fait pas sortir
/// le fichier du dossier choisi. Les caractères interdits par Windows sont
/// remplacés, les noms réservés contournés, la longueur bornée.
String safeFileName(String announced) {
  var name = announced.split(RegExp(r'[\\/]')).last;
  name = name.replaceAll(RegExp(r'[\x00-\x1f<>:"|?*]'), '_').trim();
  // Points et espaces finaux : Windows les retire en silence, et deux noms
  // différents finiraient sur le même fichier.
  name = name.replaceAll(RegExp(r'[. ]+$'), '');
  // Un nom réduit à des points désignerait le dossier, ou son parent.
  if (name.isEmpty || RegExp(r'^\.+$').hasMatch(name)) name = 'fichier';
  final stem = name.split('.').first.toUpperCase();
  if (_reservedNames.contains(stem)) name = '_$name';
  if (name.length > 180) {
    final extension = p.extension(name);
    final keep = extension.length <= 16 ? extension : '';
    name = name.substring(0, 180 - keep.length) + keep;
  }
  return name;
}

/// Premier chemin libre pour [name] dans [folder] : « nom.ext », puis
/// « nom (2).ext », « nom (3).ext »… Un fichier déjà là n'est jamais écrasé.
String freeDestination(String folder, String name) {
  final first = p.join(folder, name);
  if (!_taken(first)) return first;
  final extension = p.extension(name);
  final stem = p.basenameWithoutExtension(name);
  for (var n = 2;; n++) {
    final candidate = p.join(folder, '$stem ($n)$extension');
    if (!_taken(candidate)) return candidate;
  }
}

bool _taken(String path) =>
    FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound ||
    FileSystemEntity.typeSync('$path.part') != FileSystemEntityType.notFound;

/// Reçoit [incoming] dans [folder] et rend le fichier écrit.
///
/// Le fichier s'écrit d'abord sous « .part », et ne prend son nom qu'une fois
/// complet : un transfert interrompu ne laisse jamais un fichier tronqué qui
/// aurait l'air entier. Exactement la taille annoncée est attendue ; plus ou
/// moins, et rien ne reste sur le disque.
///
/// [onProgress] reçoit les octets reçus et le total ; [cancelled] est
/// consulté à chaque morceau.
Future<File> receiveTransfer(
  IncomingTransfer incoming,
  String folder, {
  void Function(int received, int total)? onProgress,
  bool Function()? cancelled,
  Duration stallTimeout = const Duration(seconds: 30),
}) async {
  final total = incoming.offer.size;
  final name = safeFileName(incoming.offer.name);
  try {
    await Directory(folder).create(recursive: true);
  } on FileSystemException {
    throw TransferException('Impossible de créer le dossier $folder.');
  }
  final target = freeDestination(folder, name);
  final part = File('$target.part');

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  IOSink? sink;
  try {
    final HttpClientResponse response;
    try {
      final request = await client.getUrl(incoming.url);
      // Le fichier vient de l'adresse constatée, et d'elle seule : une
      // redirection mènerait ailleurs que là où la liaison a été établie.
      request.followRedirects = false;
      response = await request.close();
    } on Object {
      throw const TransferException(
        "L'appareil qui envoie ne répond pas. Vérifiez qu'il est toujours "
        'relié, et que son pare-feu le laisse joindre.',
      );
    }
    if (response.statusCode != HttpStatus.ok) {
      unawaited(response.drain<void>().catchError((Object _) {}));
      throw TransferException(switch (response.statusCode) {
        HttpStatus.gone => "Le fichier n'existe plus chez l'expéditeur.",
        HttpStatus.notFound => 'La proposition a expiré. Demandez un nouvel envoi.',
        _ => "L'appareil qui envoie a refusé (code ${response.statusCode}).",
      });
    }

    try {
      sink = part.openWrite();
    } on FileSystemException {
      throw TransferException("Impossible d'écrire dans $folder.");
    }
    var received = 0;
    onProgress?.call(0, total);
    await for (final chunk in response.timeout(stallTimeout)) {
      received += chunk.length;
      if (received > total) {
        throw const TransferException(
          "Plus de données qu'annoncé : transfert interrompu par prudence.",
        );
      }
      sink.add(chunk);
      onProgress?.call(received, total);
      if (cancelled?.call() ?? false) {
        throw const TransferException('Réception annulée.');
      }
    }
    await sink.flush();
    await sink.close();
    sink = null;
    if (received != total) {
      throw TransferException(
        'Transfert incomplet : $received octets reçus sur $total.',
      );
    }
    // Un fichier du même nom a pu apparaître pendant la réception.
    final destination =
        FileSystemEntity.typeSync(target) == FileSystemEntityType.notFound
            ? target
            : freeDestination(folder, p.basename(target));
    return await part.rename(destination);
  } on TransferException {
    await _discard(sink, part);
    rethrow;
  } on TimeoutException {
    await _discard(sink, part);
    throw const TransferException(
      "Plus rien ne vient de l'appareil qui envoie : la liaison est coupée.",
    );
  } on FileSystemException catch (e) {
    await _discard(sink, part);
    throw TransferException('Écriture impossible : ${e.osError?.message ?? e.message}.');
  } on Object {
    await _discard(sink, part);
    throw const TransferException('La liaison a été coupée pendant la réception.');
  } finally {
    client.close(force: true);
  }
}

Future<void> _discard(IOSink? sink, File part) async {
  try {
    await sink?.close();
  } on Object {
    // Déjà fermé, ou disque plein : on efface quand même.
  }
  try {
    if (part.existsSync()) await part.delete();
  } on Object {
    // Rien d'autre à faire : le « .part » dit de lui-même qu'il est partiel.
  }
}

/// Taille lisible : « 840 o », « 12,4 Ko », « 3,1 Go ».
String transferSizeLabel(int bytes) {
  const units = ['o', 'Ko', 'Mo', 'Go', 'To'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = unit == 0 || value >= 100
      ? value.round().toString()
      : value.toStringAsFixed(1).replaceAll('.', ',');
  return '$text ${units[unit]}';
}
