import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../commands/player_command.dart';
import '../models/playback_state.dart';

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
  Future<int> start() async {
    if (_server != null) return _server!.port;

    _sessionToken = _generateToken();
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    } catch (_) {
      // Si le port 41530 est occupé, on alloue un port dynamique
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }

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

  /// Récupère l'adresse IP locale du périphérique (Wi-Fi / Ethernet).
  Future<String> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  /// Génère le payload d'appairage QR Code.
  Future<String> getPairingPayload(String deviceName) async {
    final ip = await getLocalIpAddress();
    final p = _server?.port ?? port;
    final map = {
      'protocol': 'omnia-connect',
      'version': '1.0',
      'name': deviceName,
      'host': ip,
      'port': p,
      'token': _sessionToken ?? '',
    };
    return jsonEncode(map);
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
      if (token != _sessionToken) {
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
    _connectionState.add(true);

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
        _connectionState.add(_clients.isNotEmpty);
      },
      onError: (_) {
        _clients.remove(socket);
        _connectionState.add(_clients.isNotEmpty);
      },
    );
  }

  void _processRemoteMessage(ConnectMessage msg) {
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

  String _generateToken() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return base64Url.encode(bytes);
  }

  void dispose() {
    stop();
    if (!_remoteCommands.isClosed) _remoteCommands.close();
    if (!_connectionState.isClosed) _connectionState.close();
  }
}
