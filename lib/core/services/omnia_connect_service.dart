import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../commands/player_command.dart';
import '../models/media_file.dart';
import '../models/media_type.dart';
import '../models/playback_state.dart';
import '../models/playback_status.dart';
import '../utils/connect_mode.dart';
import '../utils/pairing_code.dart';

/// Version du protocole d'OMNIA Connect.
///
/// Deux appareils qui ne parlent pas la même version ne doivent pas faire
/// semblant de se comprendre : un champ ajouté, renommé ou dont le sens
/// change passerait inaperçu jusqu'à ce qu'une commande parte de travers.
const int connectProtocolVersion = 1;

/// Taille maximale d'un message reçu, en octets.
///
/// Une commande de télécommande tient en quelques dizaines d'octets, un état
/// de lecture en quelques milliers. Au-delà, ce n'est plus une commande :
/// c'est une tentative de faire grossir la mémoire du lecteur.
const int connectMaxMessageBytes = 64 * 1024;

/// Message échangé sur le canal WebSocket d'OMNIA Connect.
class ConnectMessage {
  const ConnectMessage({
    required this.type,
    this.payload = const {},
    this.version = connectProtocolVersion,
    this.sequence = 0,
  });

  factory ConnectMessage.fromJson(Map<String, Object?> json) {
    final payload = json['payload'];
    return ConnectMessage(
      type: json['type'] as String? ?? 'unknown',
      payload: payload is Map<String, Object?> ? payload : const {},
      // Zéro quand le champ manque : l'émetteur est antérieur à l'enveloppe,
      // et on ne lui accorde pas le bénéfice du doute.
      version: (json['protocolVersion'] as num?)?.toInt() ?? 0,
      sequence: (json['seq'] as num?)?.toInt() ?? 0,
    );
  }

  final String type;
  final Map<String, Object?> payload;

  /// Version du protocole annoncée par l'émetteur.
  final int version;

  /// Numéro d'ordre, strictement croissant au sein d'une connexion.
  ///
  /// Il ferme la porte au rejeu : une commande captée sur le réseau et
  /// renvoyée telle quelle porte un numéro déjà vu, et part à la corbeille.
  final int sequence;

  Map<String, Object?> toJson() => {
        'protocolVersion': version,
        'seq': sequence,
        'type': type,
        'payload': payload,
      };

  /// Le message prêt à partir, dans son enveloppe numérotée.
  String envelope(int sequence) => jsonEncode({
        'protocolVersion': connectProtocolVersion,
        'seq': sequence,
        'type': type,
        'payload': payload,
      });

  String serialize() => jsonEncode(toJson());
}

/// Garde l'ordre des messages reçus sur une connexion.
///
/// Séparé du service pour être vérifiable seul : c'est la pièce qui décide
/// d'accepter ou de rejeter, et elle doit pouvoir être mise à l'épreuve sans
/// ouvrir de socket.
class ConnectMessageGate {
  int _lastSequence = 0;

  /// Vrai si [msg] doit être traité.
  ///
  /// Refuse une version de protocole étrangère, et tout numéro d'ordre déjà
  /// vu — rejeu, ou réémission d'un message capté.
  bool accepts(ConnectMessage msg) {
    if (msg.version != connectProtocolVersion) return false;
    if (msg.sequence <= _lastSequence) return false;
    _lastSequence = msg.sequence;
    return true;
  }
}

/// Service de communication locale Zero-Internet OMNIA Connect.
///
/// Permet la projection d'écran, la télécommande tactile et le streaming
/// direct de médias volumineux sur réseau local (Wi-Fi ou Hotspot) sans Internet.
class OmniaConnectService {
  OmniaConnectService({this.port = 41530});

  /// Connexions de commande acceptées en même temps.
  ///
  /// Un appairage relie deux appareils, rarement plus d'une poignée. Sans
  /// plafond, ouvrir des connexions en rafale faisait grossir la liste sans
  /// fin, et chacune gardait sa place en mémoire.
  static const int maxClients = 8;

  /// Spectateurs simultanés du partage d'écran.
  static const int maxScreenViewers = 4;

  /// Commandes acceptées par seconde et par connexion.
  static const int maxCommandsPerSecond = 40;

  /// Délai au bout duquel une connexion sans trafic est refermée.
  static const Duration idleTimeout = Duration(minutes: 5);

  final int port;

  HttpServer? _server;
  String? _sessionToken;

  /// Numéro d'ordre des messages que ce serveur émet.
  int _outgoing = 0;

  /// Dernier état de lecture local, tenu à jour par [followStates].
  PlaybackState _localState = const PlaybackState();
  StreamSubscription<PlaybackState>? _localStates;

  /// Vrai quand cet appareil reçoit une lecture en miroir et doit s'y caler.
  bool _mirroring = false;

  /// Vrai quand cet appareil projette en miroir et doit annoncer son état.
  bool _mirrorSending = false;
  int _lastMirrorTick = -1;
  final Set<WebSocket> _clients = {};

  final StreamController<PlayerCommand> _remoteCommands =
      StreamController<PlayerCommand>.broadcast();

  final StreamController<bool> _connectionState =
      StreamController<bool>.broadcast();

  Stream<PlayerCommand> get remoteCommands => _remoteCommands.stream;
  Stream<bool> get isConnectedStream => _connectionState.stream;

  bool get isRunning => _server != null;
  bool get hasConnectedClients => _clients.isNotEmpty;
  String? get sessionToken => _sessionToken;

  /// Démarre le serveur local et génère le jeton d'appairage éphémère.
  Future<int> start({InternetAddress? address}) async {
    if (_server != null) return _server!.port;

    _sessionToken = _generateToken();
    final bindAddr = address ?? InternetAddress.anyIPv4;
    try {
      _server = await HttpServer.bind(bindAddr, port);
    } catch (_) {
      // Si le port 41530 est occupé, on alloue un port dynamique
      _server = await HttpServer.bind(bindAddr, 0);
    }
    _server?.idleTimeout = idleTimeout;

    _server!.listen(_handleRequest);
    return _server!.port;
  }

  /// Arrête le serveur et clôture toutes les connexions actives.
  Future<void> stop() async {
    final activeClients = _clients.toList();
    _clients.clear();
    for (final client in activeClients) {
      try {
        await client.close();
      } catch (_) {}
    }
    await _server?.close(force: true);
    _server = null;
    _sessionToken = null;
    if (!_connectionState.isClosed) {
      _connectionState.add(false);
    }
  }

  /// Vérifie les prérequis réels du mode de liaison choisi.
  ///
  /// Les boutons de mode n'enregistraient qu'une préférence : rien ne
  /// contrôlait que le Wi-Fi était actif, qu'un point d'accès tournait ou
  /// qu'un lien PAN Bluetooth existait, et l'appairage échouait plus tard sans
  /// rien dire. Le rapport rendu ici porte soit l'adresse à annoncer, soit ce
  /// qui manque et la marche à suivre.
  Future<ConnectModeReport> inspectMode(ConnectMode mode) async {
    try {
      // Borné dans le temps : sur Android, lire les cartes réseau demande
      // l'accès à l'état du réseau et peut rester sans réponse. Sans borne,
      // l'interface resterait en « vérification » indéfiniment — un panneau
      // qui tourne sans fin vaut le bouton qui ne fait rien.
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      ).timeout(ConnectModeInspector.probeTimeout);
      return ConnectModeInspector.inspect(mode: mode, interfaces: interfaces);
    } catch (_) {
      return ConnectModeInspector.unavailable(mode);
    }
  }

  /// Adresse à annoncer pour [mode], ou `null` quand il n'y en a aucune.
  ///
  /// L'interface publiée suit réellement le mode : annoncer l'adresse Wi-Fi
  /// alors que le téléphone sert de point d'accès (ou l'inverse) rend le code
  /// d'appairage injoignable. En Bluetooth sans lien PAN, il n'y a rien à
  /// annoncer du tout.
  /// Toutes les adresses de cet appareil qu'un autre peut tenter, la plus
  /// probable en premier.
  ///
  /// Annoncer une seule adresse revient à parier sur la façon dont les deux
  /// appareils sont reliés — et le pari se perd dès qu'une box sépare ses
  /// bandes, ou qu'Android cache à l'application l'interface de son propre
  /// point d'accès. Les annoncer toutes laisse l'autre appareil trouver.
  Future<List<String>> candidateAddresses(ConnectMode mode) async {
    final liste = <String>[];
    final prefere = (await inspectMode(mode)).announcedAddress;
    if (prefere != null) liste.add(prefere);

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final carte in interfaces) {
        for (final adresse in carte.addresses) {
          final ip = adresse.address;
          if (!liste.contains(ip) && _isPrivateAddress(ip)) liste.add(ip);
        }
      }
    } on Object {
      // Liste d'interfaces refusée : il reste l'adresse préférée, et le
      // repli ci-dessous.
    }

    // Android ne montre pas toujours l'interface de son propre point d'accès
    // à une application ordinaire. Sa passerelle, elle, ne change pas.
    if (mode == ConnectMode.hotspot && !liste.contains('192.168.43.1')) {
      liste.add('192.168.43.1');
    }
    return liste;
  }

  /// Vrai pour une adresse de réseau local, seule joignable par l'autre
  /// appareil : une adresse publique ne mène nulle part depuis chez soi.
  static bool _isPrivateAddress(String ip) {
    if (ip.startsWith('10.') || ip.startsWith('192.168.')) return true;
    if (!ip.startsWith('172.')) return false;
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final second = int.tryParse(parts[1]);
    return second != null && second >= 16 && second <= 31;
  }

  Future<String?> addressForMode(ConnectMode mode) async {
    final announced = (await inspectMode(mode)).announcedAddress;
    if (announced != null) return announced;
    return mode == ConnectMode.wifi ? '127.0.0.1' : null;
  }

  /// Génère le payload d'appairage QR Code.
  ///
  /// L'hôte publié suit le [mode] : c'est l'adresse que l'appareil distant
  /// devra joindre selon le type de liaison choisi.
  Future<String> getPairingPayload(
    String deviceName, {
    ConnectMode mode = ConnectMode.wifi,
  }) async {
    final adresses = await candidateAddresses(mode);
    final ip = adresses.isNotEmpty ? adresses.first : await addressForMode(mode);
    final p = _server?.port ?? port;
    final map = {
      'protocol': 'omnia-connect',
      'version': '1.0',
      'name': deviceName,
      'host': ip ?? '',
      // Toutes les adresses, pour que l'autre appareil les essaie : celle qui
      // le joint dépend de la façon dont les deux sont reliés.
      'hosts': adresses,
      'port': p,
      'token': _sessionToken ?? '',
    };
    return jsonEncode(map);
  }

  /// URL du flux HTTP par lequel cet appareil sert [path] au réseau local.
  ///
  /// Le jeton transmis est celui du serveur local : c'est lui qui autorise la
  /// lecture du fichier, l'appareil distant n'ayant aucun accès au stockage.
  static String buildStreamUrl({
    required String host,
    required int port,
    required String token,
    required String path,
  }) {
    return Uri.http(
      '$host:$port',
      '/api/stream',
      <String, String>{'path': path, 'token': token},
    ).toString();
  }

  /// Vrai si [host] est une adresse que l'appareil distant peut joindre.
  ///
  /// La boucle locale et l'adresse indéterminée ne joignent que l'appareil qui
  /// les annonce : les publier ferait échouer la projection sans rien dire.
  static bool isProjectableHost(String? host) {
    if (host == null || host.isEmpty) return false;
    return host != '127.0.0.1' && host != '0.0.0.0';
  }

  /// Demande à l'hôte appairé de lire [path], servi par cet appareil.
  ///
  /// Renvoie l'URL projetée, ou `null` quand la projection est impossible —
  /// pas d'appairage actif, chemin vide ou adresse injoignable — pour que
  /// l'interface puisse l'expliquer au lieu d'échouer en silence.
  /// [mirror] demande la lecture en miroir : l'autre appareil ne se contente
  /// alors pas d'ouvrir le fichier, il suit aussi ce qu'on y fait.
  Future<String?> projectFile(
    String path, {
    ConnectMode mode = ConnectMode.wifi,
    bool mirror = false,
  }) async {
    if (path.isEmpty || !client.connected) return null;

    final serverPort = await start();
    final host = await addressForMode(mode);
    if (!isProjectableHost(host)) return null;

    final url = buildStreamUrl(
      host: host!,
      port: serverPort,
      token: _sessionToken ?? '',
      path: path,
    );
    _mirrorSending = mirror;
    _lastMirrorTick = -1;
    client.projectStream(url, mirror: mirror);
    return url;
  }

  /// Les spectateurs de l'écran partagé, et les paramètres de décodage.
  final List<HttpResponse> _screenViewers = [];
  List<int>? _screenHeader;

  /// Sert l'écran partagé : un flux H.264 qui ne se termine jamais.
  ///
  /// Les paramètres de décodage partent en tête pour chaque spectateur, même
  /// arrivé en cours de route : sans eux, un lecteur ne décode rien et reste
  /// sur un écran noir sans dire pourquoi.
  Future<void> _handleScreenStream(HttpRequest request) async {
    if (!sameToken(request.uri.queryParameters['token'], _sessionToken)) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    if (_screenViewers.length >= maxScreenViewers) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }
    final response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType('video', 'h264');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    final header = _screenHeader;
    if (header != null) response.add(header);
    _screenViewers.add(response);
    try {
      await response.done;
    } on Object {
      // Le spectateur est parti : c'est la fin normale de ce flux.
    }
    _screenViewers.remove(response);
  }

  /// Pousse un morceau d'écran encodé vers les spectateurs.
  void feedScreenChunk(List<int> bytes, {required bool header}) {
    if (header) _screenHeader = List<int>.unmodifiable(bytes);
    for (final viewer in List<HttpResponse>.of(_screenViewers)) {
      try {
        viewer.add(bytes);
      } on Object {
        _screenViewers.remove(viewer);
      }
    }
  }

  /// Demande à l'hôte appairé d'afficher l'écran de cet appareil.
  ///
  /// Contrairement aux deux autres modes, rien n'est lu : c'est l'image de
  /// l'écran, encodée au vol, qui part sur le réseau.
  Future<String?> projectScreen({ConnectMode mode = ConnectMode.wifi}) async {
    if (!client.connected) return null;
    final serverPort = await start();
    final host = await addressForMode(mode);
    if (!isProjectableHost(host)) return null;
    final url = Uri.http(
      '$host:$serverPort',
      '/api/screen',
      <String, String>{'token': _sessionToken ?? ''},
    ).toString();
    _mirrorSending = false;
    client.projectStream(url);
    return url;
  }

  /// Diffuse l'état actuel de lecture aux clients appairés.
  /// Suit l'état de lecture local, hors de toute fenêtre.
  ///
  /// Sert des deux côtés de la liaison. L'appareil qui projette en miroir
  /// envoie cet état à l'autre ; celui qui reçoit s'en sert pour mesurer son
  /// écart avec ce qu'on lui annonce. Auparavant l'état ne partait que depuis
  /// la fenêtre OMNIA Connect, et s'arrêtait donc dès qu'on la fermait — ce
  /// qu'on fait précisément pour regarder.
  void followStates(Stream<PlaybackState> states) {
    unawaited(_localStates?.cancel());
    _localStates = states.listen(_onLocalState);
  }

  void _onLocalState(PlaybackState state) {
    _localState = state;
    if (hasConnectedClients) broadcastState(state);
    if (!_mirrorSending || !client.connected) return;
    // Une fois par demi-seconde : la position change à chaque image, et
    // inonder la liaison ne rendrait pas le miroir plus fidèle.
    final now = state.position.inMilliseconds ~/ 500;
    if (now == _lastMirrorTick) return;
    _lastMirrorTick = now;
    client.sendMirrorState(state);
  }

  /// Cale la lecture locale sur celle de l'appareil qui projette.
  ///
  /// On converge vers l'état reçu plutôt que de rejouer les gestes : un geste
  /// perdu ou reçu deux fois décalerait les deux lectures pour de bon, alors
  /// qu'un état en retard se rattrape de lui-même au message suivant.
  void _applyMirrorState(Map<String, Object?> payload) {
    if (!_mirroring || _remoteCommands.isClosed) return;

    final positionMs = (payload['positionMs'] as num?)?.toInt();
    if (positionMs != null) {
      final cible = Duration(milliseconds: positionMs);
      final ecart = (cible - _localState.position).abs();
      // Seul un écart visible mérite un saut : se recaler à chaque message
      // hacherait la lecture au lieu de la suivre.
      if (ecart > const Duration(milliseconds: 1500)) {
        _remoteCommands.add(SeekAbsolute(cible));
      }
    }

    final volume = (payload['volume'] as num?)?.toDouble();
    if (volume != null && (volume - _localState.volume).abs() > 0.5) {
      _remoteCommands.add(SetVolume(volume));
    }

    final page = (payload['page'] as num?)?.toInt();
    if (page != null && page > 0 && page != _localState.currentPage) {
      _remoteCommands.add(GoToPage(page));
    }

    final scroll = (payload['scrollFraction'] as num?)?.toDouble();
    if (scroll != null && (scroll - _localState.scrollFraction).abs() > 0.004) {
      _remoteCommands.add(ScrollTo(scroll));
    }

    final playing = payload['status'] == PlaybackStatus.playing.name;
    if (playing != (_localState.status == PlaybackStatus.playing)) {
      _remoteCommands.add(const TogglePlay());
    }
  }

  void broadcastState(PlaybackState state) {
    if (_clients.isEmpty) return;

    final msg = ConnectMessage(
      type: 'state',
      payload: {
        'status': state.status.name,
        'title': state.file?.name ?? '',
        'positionMs': state.position.inMilliseconds,
        'durationMs': state.duration.inMilliseconds,
        'volume': state.volume,
        'page': state.currentPage,
        'pageCount': state.totalPages,
        'isDocument': state.isDocument,
      },
    );
    final serialized = msg.envelope(++_outgoing);
    for (final client in _clients) {
      try {
        client.add(serialized);
      } catch (_) {}
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    // En-têtes CORS pour le réseau local
    // Aucun en-tête CORS, et c'est voulu : OMNIA Connect ne parle qu'à
    // l'application OMNIA d'en face, jamais à une page web. Avec
    // « Access-Control-Allow-Origin: * », n'importe quel site visité sur
    // cet appareil pouvait interroger ce serveur depuis le navigateur, en
    // profitant de ce qu'il est sur le réseau local de la victime.

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    if (path == '/api/status') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'status': 'online',
        'service': 'OMNIA Connect',
        'version': '1.0',
      }));
      await request.response.close();
      return;
    }

    if (path == '/api/ws') {
      final token = request.uri.queryParameters['token'];
      final isLocalClient = request.connectionInfo?.remoteAddress.isLoopback == true ||
          (request.connectionInfo?.remoteAddress.address.startsWith('192.168.') ?? false) ||
          (request.connectionInfo?.remoteAddress.address.startsWith('10.') ?? false) ||
          (request.connectionInfo?.remoteAddress.address.startsWith('172.') ?? false);

      final tokenMatches = sameToken(token, _sessionToken);
      final allowedManual = isLocalClient && (token == null || token.isEmpty || token == 'omnia');

      if (!tokenMatches && !allowedManual) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }

      if (WebSocketTransformer.isUpgradeRequest(request)) {
        // Un appairage relie deux appareils : au-delà d'une poignée, ce
        // n'est plus un usage, c'est une façon d'épuiser le serveur.
        if (_clients.length >= maxClients) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        _handleClientSocket(socket);
        return;
      }
    }

    if (path == '/api/screen') {
      await _handleScreenStream(request);
      return;
    }

    if (path == '/api/stream') {
      await _handleStreaming(request);
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  void _handleClientSocket(WebSocket socket) {
    _clients.add(socket);
    if (!_connectionState.isClosed) {
      _connectionState.add(true);
    }

    // L'ordre et la cadence se tiennent par connexion : deux appareils
    // appairés ne se gênent pas l'un l'autre, et celui qui s'emballe ne
    // pénalise que lui-même.
    final gate = ConnectMessageGate();
    var fenetre = DateTime.now();
    var recues = 0;

    socket.listen(
      (data) {
        try {
          if (data is! String || data.length > connectMaxMessageBytes) return;

          // Cadence : une télécommande tenue par une main produit quelques
          // commandes par seconde. Un millier n'en vient jamais.
          final maintenant = DateTime.now();
          if (maintenant.difference(fenetre) >= const Duration(seconds: 1)) {
            fenetre = maintenant;
            recues = 0;
          }
          if (++recues > maxCommandsPerSecond) return;

          final decoded = jsonDecode(data) as Map<String, Object?>;
          final msg = ConnectMessage.fromJson(decoded);
          if (!gate.accepts(msg)) return;
          _processRemoteMessage(msg);
        } catch (_) {}
      },
      onDone: () {
        _clients.remove(socket);
        if (!_connectionState.isClosed) {
          _connectionState.add(_clients.isNotEmpty);
        }
      },
      onError: (_) {
        _clients.remove(socket);
        if (!_connectionState.isClosed) {
          _connectionState.add(_clients.isNotEmpty);
        }
      },
    );
  }

  /// Un déplacement relatif au-delà d'une journée n'est plus un geste.
  static const double _maxSeekSeconds = 24 * 60 * 60;

  /// Et aucun média ne dure plus de cent jours.
  static const double _maxPositionMs = 100 * 24 * 60 * 60 * 1000;

  /// Le nombre porté par [value], ou `null` s'il n'y en a pas d'utilisable.
  ///
  /// Un `clamp` ne rattrape pas tout : appliqué à « pas un nombre », il rend
  /// « pas un nombre », et la valeur entrerait quand même dans le lecteur.
  static double? _finite(Object? value) {
    if (value is! num) return null;
    final number = value.toDouble();
    return number.isFinite ? number : null;
  }

  void _processRemoteMessage(ConnectMessage msg) {
    if (_remoteCommands.isClosed) return;
    switch (msg.type) {
      case 'togglePlay':
        _remoteCommands.add(const TogglePlay());
        break;
      // Les valeurs venues du réseau sont bornées avant d'entrer dans le
      // lecteur. Rien ne les vérifiait : une position de mille ans ou un
      // volume de l'ordre du milliard partaient telles quelles vers le
      // moteur, qui n'a pas à se défendre tout seul.
      case 'seekRelative':
        final seconds = _finite(msg.payload['seconds']);
        if (seconds == null) break;
        _remoteCommands
            .add(SeekRelative(seconds.clamp(-_maxSeekSeconds, _maxSeekSeconds)));
        break;
      case 'seekAbsolute':
        final ms = _finite(msg.payload['positionMs']);
        if (ms == null) break;
        _remoteCommands.add(
          SeekAbsolute(
            Duration(milliseconds: ms.clamp(0, _maxPositionMs).toInt()),
          ),
        );
        break;
      case 'volumeRelative':
        final delta = _finite(msg.payload['delta']);
        if (delta == null) break;
        _remoteCommands.add(VolumeRelative(delta.clamp(-100.0, 100.0)));
        break;
      case 'next':
        _remoteCommands.add(const NextFile());
        break;
      case 'previous':
        _remoteCommands.add(const PreviousFile());
        break;
      case 'nextPage':
        _remoteCommands.add(const NextPage());
        break;
      case 'previousPage':
        _remoteCommands.add(const PreviousPage());
        break;
      case 'openRemoteStream':
        final url = msg.payload['url'] as String?;
        if (url != null) {
          // Le mode se déclare à l'ouverture : l'appareil qui projette en
          // décide, celui qui reçoit s'y conforme.
          _mirroring = msg.payload['mirror'] == true;
          _remoteCommands.add(OpenFile(url));
        }
        break;
      case 'mirrorState':
        _applyMirrorState(msg.payload);
        break;
    }
  }

  /// Diffusion multimédia avec support RFC 7233 (HTTP Range Requests).
  Future<void> _handleStreaming(HttpRequest request) async {
    final filePath = request.uri.queryParameters['path'];
    final token = request.uri.queryParameters['token'];

    if (!sameToken(token, _sessionToken) || filePath == null) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }

    final file = File(filePath);
    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final totalSize = await file.length();
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      // L'en-tête vient du client : il peut être absurde autant que
      // malveillant. « bytes=abc- » levait une exception qui remontait au
      // serveur, et une plage renversée ou hors du fichier faisait échouer
      // la lecture elle-même. On répond désormais ce que prévoit la norme.
      final rangeParts = rangeHeader.substring(6).split('-');
      final start = int.tryParse(rangeParts[0]);
      final asked = rangeParts.length > 1 && rangeParts[1].isNotEmpty
          ? int.tryParse(rangeParts[1])
          : totalSize - 1;
      if (start == null || asked == null || start < 0 || start >= totalSize) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers
            .add(HttpHeaders.contentRangeHeader, 'bytes */$totalSize');
        await request.response.close();
        return;
      }
      // Une fin au-delà du fichier se ramène à sa dernière position, comme
      // le veut la RFC 7233 ; une fin avant le début, elle, n'a pas de sens.
      final end = asked >= totalSize ? totalSize - 1 : asked;
      if (end < start) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers
            .add(HttpHeaders.contentRangeHeader, 'bytes */$totalSize');
        await request.response.close();
        return;
      }

      final chunkLength = end - start + 1;
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.add(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.add(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$totalSize');
      request.response.headers.contentLength = chunkLength;

      final stream = file.openRead(start, end + 1);
      await request.response.addStream(stream);
      await request.response.close();
    } else {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.add(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.contentLength = totalSize;
      await request.response.addStream(file.openRead());
      await request.response.close();
    }
  }

  OmniaConnectClient? _client;

  /// Client permettant de se connecter à une autre instance OMNIA distante.
  OmniaConnectClient get client => _client ??= OmniaConnectClient();

  /// Jeton de session : 256 bits tirés du générateur cryptographique.
  ///
  /// Seize octets suffisaient à un appairage de salon, mais ce jeton est la
  /// seule chose qui sépare un appareil invité d'un inconnu : autant qu'il
  /// reste hors de portée d'une recherche exhaustive, aujourd'hui comme dans
  /// dix ans.
  String _generateToken() {
    final rand = Random.secure();
    final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Comparaison de jetons à temps constant.
  ///
  /// Une comparaison ordinaire s'arrête au premier caractère qui diffère :
  /// le temps de réponse trahit alors le nombre de caractères justes, et le
  /// jeton se devine de proche en proche au lieu d'être cherché en entier.
  static bool sameToken(String? given, String? expected) {
    if (given == null || expected == null) return false;
    if (given.length != expected.length) return false;
    var difference = 0;
    for (var i = 0; i < given.length; i++) {
      difference |= given.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return difference == 0;
  }

  void dispose() {
    stop();
    _client?.dispose();
    if (!_remoteCommands.isClosed) _remoteCommands.close();
    if (!_connectionState.isClosed) _connectionState.close();
  }
}

/// Client OMNIA Connect pour se connecter à une instance distante (Desktop ou Mobile)
/// et faire office de télécommande interactive ou de passerelle de projection.
class OmniaConnectClient {
  WebSocket? _socket;
  final StreamController<PlaybackState> _remoteStateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<PlaybackState> get remoteState => _remoteStateController.stream;
  Stream<bool> get isConnected => _connectionController.stream;
  bool get connected => _socket != null;

  String? host;
  int? port;
  String? token;
  String? deviceName;

  /// Numéro d'ordre des messages que ce client émet : il repart de zéro à
  /// chaque connexion, comme le contrôle qui l'attend en face.
  int _outgoing = 0;

  /// Établit la connexion avec l'hôte distant via WebSocket.
  /// Essaie chaque adresse annoncée, la plus probable d'abord.
  ///
  /// Laquelle joint l'autre appareil dépend de la façon dont les deux sont
  /// reliés — Wi-Fi par une box, point d'accès, lien Bluetooth — et celui qui
  /// annonce ne peut pas le deviner. Au lieu de parier sur une, on les essaie.
  Future<bool> connectAny(PairingTarget target, {String? name}) async {
    for (final host in <String>[target.host, ...target.alternates]) {
      if (host.isEmpty) continue;
      final ok = await connect(
        host: host,
        port: target.port,
        token: target.token,
        name: name,
      );
      if (ok) return true;
    }
    return false;
  }

  Future<bool> connect({
    required String host,
    required int port,
    required String token,
    String? name,
  }) async {
    await disconnect();
    this.host = host;
    this.port = port;
    this.token = token;
    deviceName = name;
    // Le contrôle d'ordre d'en face repart de zéro à chaque connexion : le
    // compteur doit le suivre, sans quoi la première commande d'une nouvelle
    // session serait prise pour un rejeu de la précédente.
    _outgoing = 0;

    try {
      final tokenParam = token.isNotEmpty ? '?token=$token' : '';
      final uri = Uri.parse('ws://$host:$port/api/ws$tokenParam');
      _socket = await WebSocket.connect(uri.toString()).timeout(
        const Duration(seconds: 4),
      );
      if (!_connectionController.isClosed) {
        _connectionController.add(true);
      }

      // Mêmes règles qu'à l'arrivée côté serveur : taille bornée, version du
      // protocole exigée, et ordre strictement croissant. Un état de lecture
      // rejoué ramènerait l'affichage en arrière.
      final gate = ConnectMessageGate();

      _socket!.listen(
        (data) {
          try {
            if (data is! String || data.length > connectMaxMessageBytes) return;
            final decoded = jsonDecode(data) as Map<String, Object?>;
            if (!gate.accepts(ConnectMessage.fromJson(decoded))) return;
            if (decoded['type'] == 'state') {
              final payload = decoded['payload'] as Map<String, Object?>? ?? {};
              final state = PlaybackState(
                status: PlaybackStatus.values.byName(payload['status'] as String? ?? 'idle'),
                position: Duration(milliseconds: (payload['positionMs'] as num?)?.toInt() ?? 0),
                duration: Duration(milliseconds: (payload['durationMs'] as num?)?.toInt() ?? 0),
                volume: (payload['volume'] as num?)?.toDouble() ?? 100.0,
                currentPage: (payload['page'] as num?)?.toInt() ?? 0,
                totalPages: (payload['pageCount'] as num?)?.toInt() ?? 0,
                file: payload['title'] != null && (payload['title'] as String).isNotEmpty
                    ? MediaFile(
                        path: payload['title'] as String,
                        type: (payload['isDocument'] as bool? ?? false)
                            ? MediaType.doc
                            : MediaType.video,
                      )
                    : null,
              );
              if (!_remoteStateController.isClosed) {
                _remoteStateController.add(state);
              }
            }
          } catch (_) {}
        },
        onDone: () {
          _socket = null;
          if (!_connectionController.isClosed) {
            _connectionController.add(false);
          }
        },
        onError: (_) {
          _socket = null;
          if (!_connectionController.isClosed) {
            _connectionController.add(false);
          }
        },
      );
      return true;
    } catch (_) {
      _socket = null;
      if (!_connectionController.isClosed) {
        _connectionController.add(false);
      }
      return false;
    }
  }

  /// Envoie une commande de télécommande à l'hôte distant.
  void sendCommand(PlayerCommand command) {
    if (_socket == null) return;
    ConnectMessage? msg;
    if (command is TogglePlay) {
      msg = const ConnectMessage(type: 'togglePlay');
    } else if (command is SeekRelative) {
      msg = ConnectMessage(type: 'seekRelative', payload: {'seconds': command.seconds});
    } else if (command is SeekAbsolute) {
      msg = ConnectMessage(
          type: 'seekAbsolute', payload: {'positionMs': command.position.inMilliseconds});
    } else if (command is VolumeRelative) {
      msg = ConnectMessage(type: 'volumeRelative', payload: {'delta': command.delta});
    } else if (command is NextFile) {
      msg = const ConnectMessage(type: 'next');
    } else if (command is PreviousFile) {
      msg = const ConnectMessage(type: 'previous');
    } else if (command is NextPage) {
      msg = const ConnectMessage(type: 'nextPage');
    } else if (command is PreviousPage) {
      msg = const ConnectMessage(type: 'previousPage');
    }
    if (msg != null) {
      try {
        _socket!.add(msg.envelope(++_outgoing));
      } catch (_) {}
    }
  }

  /// Ordonne à l'hôte distant de charger et projeter un flux HTTP.
  void projectStream(String streamUrl, {bool mirror = false}) {
    if (_socket == null) return;
    final msg = ConnectMessage(
      type: 'openRemoteStream',
      payload: {'url': streamUrl, 'mirror': mirror},
    );
    try {
      _socket!.add(msg.envelope(++_outgoing));
    } catch (_) {}
  }

  /// Annonce l'état de lecture à l'appareil qui nous suit en miroir.
  void sendMirrorState(PlaybackState state) {
    if (_socket == null) return;
    final msg = ConnectMessage(
      type: 'mirrorState',
      payload: {
        'status': state.status.name,
        'positionMs': state.position.inMilliseconds,
        'volume': state.volume,
        'page': state.currentPage,
        'scrollFraction': state.scrollFraction,
      },
    );
    try {
      _socket!.add(msg.envelope(++_outgoing));
    } catch (_) {}
  }

  /// Déconnecte le client du serveur distant.
  Future<void> disconnect() async {
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    if (!_connectionController.isClosed) {
      _connectionController.add(false);
    }
  }

  void dispose() {
    disconnect();
    if (!_remoteStateController.isClosed) _remoteStateController.close();
    if (!_connectionController.isClosed) _connectionController.close();
  }
}
