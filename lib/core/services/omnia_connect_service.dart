import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../commands/player_command.dart';
import '../models/media_file.dart';
import '../models/media_type.dart';
import '../models/playback_state.dart';
import '../models/playback_status.dart';

/// Message échangé sur le canal WebSocket d'OMNIA Connect.
class ConnectMessage {
  const ConnectMessage({
    required this.type,
    this.payload = const {},
  });

  factory ConnectMessage.fromJson(Map<String, Object?> json) {
    return ConnectMessage(
      type: json['type'] as String? ?? 'unknown',
      payload: json['payload'] as Map<String, Object?>? ?? const {},
    );
  }

  final String type;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
        'type': type,
        'payload': payload,
      };

  String serialize() => jsonEncode(toJson());
}

/// Service de communication locale Zero-Internet OMNIA Connect.
///
/// Permet la projection d'écran, la télécommande tactile et le streaming
/// direct de médias volumineux sur réseau local (Wi-Fi ou Hotspot) sans Internet.
class OmniaConnectService {
  OmniaConnectService({this.port = 41530});

  final int port;

  HttpServer? _server;
  String? _sessionToken;
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
    _server?.idleTimeout = null;

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

  /// Récupère l'adresse IP locale à annoncer selon le [wirelessMode] choisi.
  ///
  /// Le mode de liaison change réellement l'interface publiée, sinon annoncer
  /// l'adresse Wi-Fi alors que le téléphone sert de point d'accès (ou l'inverse)
  /// rendrait le pairage injoignable :
  /// - `wifi` : l'interface station du réseau local (wlan0, eth, en…).
  /// - `hotspot` : l'interface du point d'accès servi par le téléphone
  ///   (ap0, swlan…, ou le sous-réseau de partage Android 192.168.43.x) —
  ///   c'est celle-ci que le PC joint quand le téléphone partage sa connexion.
  /// - `bluetooth` : l'interface PAN Bluetooth (bnep0, bt-pan…) ; `null` si
  ///   aucun lien PAN n'est actif, le partage Bluetooth devant être engagé.
  Future<String?> getLocalIpAddress({String wirelessMode = 'wifi'}) async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      String? station;
      String? accessPoint;
      String? bluetooth;
      String? private;
      String? any;

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        final isAp = name.startsWith('ap') ||
            name.contains('swlan') ||
            name.contains('wlan1');
        final isBt = name.contains('bnep') ||
            name.contains('bt-pan') ||
            name.startsWith('bt');
        final isSta = name.contains('wlan') ||
            name.contains('wi-fi') ||
            name.contains('eth') ||
            name.contains('en');
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (addr.isLoopback || ip.startsWith('127.')) continue;
          any ??= ip;
          final isPrivate =
              ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.');
          if (isPrivate) private ??= ip;
          // Le sous-réseau de partage Android trahit le point d'accès même si
          // le nom d'interface varie selon le fabricant.
          if (isAp || ip.startsWith('192.168.43.')) accessPoint ??= ip;
          if (isBt) bluetooth ??= ip;
          if (isSta && !isAp) station ??= ip;
        }
      }

      switch (wirelessMode) {
        case 'hotspot':
          return accessPoint ?? private ?? any ?? '127.0.0.1';
        case 'bluetooth':
          // Sans lien PAN Bluetooth actif il n'y a aucune adresse à annoncer :
          // on le signale plutôt que de publier une adresse injoignable.
          return bluetooth;
        default:
          return station ?? private ?? any ?? '127.0.0.1';
      }
    } catch (_) {}
    return wirelessMode == 'bluetooth' ? null : '127.0.0.1';
  }

  /// Génère le payload d'appairage QR Code.
  ///
  /// L'hôte publié suit le [wirelessMode] : c'est l'adresse que l'appareil
  /// distant devra joindre selon le type de liaison choisi.
  Future<String> getPairingPayload(String deviceName, {String wirelessMode = 'wifi'}) async {
    final ip = await getLocalIpAddress(wirelessMode: wirelessMode);
    final p = _server?.port ?? port;
    final map = {
      'protocol': 'omnia-connect',
      'version': '1.0',
      'name': deviceName,
      'host': ip ?? '',
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
  Future<String?> projectFile(
    String path, {
    String wirelessMode = 'wifi',
  }) async {
    if (path.isEmpty || !client.connected) return null;

    final serverPort = await start();
    final host = await getLocalIpAddress(wirelessMode: wirelessMode);
    if (!isProjectableHost(host)) return null;

    final url = buildStreamUrl(
      host: host!,
      port: serverPort,
      token: _sessionToken ?? '',
      path: path,
    );
    client.projectStream(url);
    return url;
  }

  /// Diffuse l'état actuel de lecture aux clients appairés.
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
    final serialized = msg.serialize();
    for (final client in _clients) {
      try {
        client.add(serialized);
      } catch (_) {}
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    // En-têtes CORS pour le réseau local
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Origin, Content-Type, Authorization');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
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

      final tokenMatches = token == _sessionToken;
      final allowedManual = isLocalClient && (token == null || token.isEmpty || token == 'omnia');

      if (!tokenMatches && !allowedManual) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }

      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        _handleClientSocket(socket);
        return;
      }
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

    socket.listen(
      (data) {
        try {
          final decoded = jsonDecode(data as String) as Map<String, Object?>;
          final msg = ConnectMessage.fromJson(decoded);
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

  void _processRemoteMessage(ConnectMessage msg) {
    if (_remoteCommands.isClosed) return;
    switch (msg.type) {
      case 'togglePlay':
        _remoteCommands.add(const TogglePlay());
        break;
      case 'seekRelative':
        final seconds = (msg.payload['seconds'] as num?)?.toDouble() ?? 0.0;
        _remoteCommands.add(SeekRelative(seconds));
        break;
      case 'seekAbsolute':
        final ms = (msg.payload['positionMs'] as num?)?.toInt() ?? 0;
        _remoteCommands.add(SeekAbsolute(Duration(milliseconds: ms)));
        break;
      case 'volumeRelative':
        final delta = (msg.payload['delta'] as num?)?.toDouble() ?? 0.0;
        _remoteCommands.add(VolumeRelative(delta));
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
          _remoteCommands.add(OpenFile(url));
        }
        break;
    }
  }

  /// Diffusion multimédia avec support RFC 7233 (HTTP Range Requests).
  Future<void> _handleStreaming(HttpRequest request) async {
    final filePath = request.uri.queryParameters['path'];
    final token = request.uri.queryParameters['token'];

    if (token != _sessionToken || filePath == null) {
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
      final rangeParts = rangeHeader.substring(6).split('-');
      final start = int.parse(rangeParts[0]);
      final end = rangeParts.length > 1 && rangeParts[1].isNotEmpty
          ? int.parse(rangeParts[1])
          : totalSize - 1;

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

  String _generateToken() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return base64Url.encode(bytes);
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

  /// Établit la connexion avec l'hôte distant via WebSocket.
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

    try {
      final tokenParam = token.isNotEmpty ? '?token=$token' : '';
      final uri = Uri.parse('ws://$host:$port/api/ws$tokenParam');
      _socket = await WebSocket.connect(uri.toString()).timeout(
        const Duration(seconds: 4),
      );
      if (!_connectionController.isClosed) {
        _connectionController.add(true);
      }

      _socket!.listen(
        (data) {
          try {
            final decoded = jsonDecode(data as String) as Map<String, Object?>;
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
        _socket!.add(msg.serialize());
      } catch (_) {}
    }
  }

  /// Ordonne à l'hôte distant de charger et projeter un flux HTTP.
  void projectStream(String streamUrl) {
    if (_socket == null) return;
    final msg = ConnectMessage(
      type: 'openRemoteStream',
      payload: {'url': streamUrl},
    );
    try {
      _socket!.add(msg.serialize());
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
