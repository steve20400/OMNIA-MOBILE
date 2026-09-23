import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/playback_state.dart';
import '../../core/models/playback_status.dart';
import '../../core/providers.dart';
import '../../core/services/omnia_connect_service.dart';
import '../theme/omnia_theme.dart';
import 'omnia_button.dart';
import 'omnia_icon_button.dart';
import 'omnia_qr_code.dart';

enum _ConnectTab { share, remote }

/// Dialogue interactif d'appairage, de télécommande et de projection OMNIA Connect (Zero-Internet).
class OmniaConnectModal extends ConsumerStatefulWidget {
  const OmniaConnectModal({super.key, this.initialPairingData});

  final String? initialPairingData;

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const OmniaConnectModal(),
    );
  }

  @override
  ConsumerState<OmniaConnectModal> createState() => _OmniaConnectModalState();
}

class _OmniaConnectModalState extends ConsumerState<OmniaConnectModal> {
  _ConnectTab _activeTab = _ConnectTab.share;
  String? _pairingData;
  bool _isLoading = true;
  StreamSubscription<PlayerCommand>? _cmdSubscription;

  // Contrôleur de saisie pour la connexion manuelle / code
  final TextEditingController _ipController = TextEditingController();
  bool _isConnectingClient = false;
  String? _clientError;

  // Scanner de caméra pour QR Code
  bool _isScanning = false;
  MobileScannerController? _scannerController;

  @override
  void initState() {
    super.initState();
    if (widget.initialPairingData != null) {
      _pairingData = widget.initialPairingData;
      _isLoading = false;
    } else {
      _initConnect();
    }
  }

  @override
  void dispose() {
    _cmdSubscription?.cancel();
    _ipController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _initConnect() async {
    final service = ref.read(omniaConnectServiceProvider);
    await service.start();
    final payload = await service.getPairingPayload('OMNIA Mobile');

    // Écouter les commandes distantes pour les router vers le bus
    _cmdSubscription = service.remoteCommands.listen((cmd) {
      ref.dispatch(cmd);
    });

    if (mounted) {
      setState(() {
        _pairingData = payload;
        _isLoading = false;
      });
    }
  }

  Future<void> _connectWithRawString(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _isScanning = false;
      _isConnectingClient = true;
      _clientError = null;
    });

    final service = ref.read(omniaConnectServiceProvider);
    String host = trimmed;
    int port = 41530;
    String token = '';

    try {
      if (trimmed.startsWith('{')) {
        final map = jsonDecode(trimmed) as Map<String, Object?>;
        host = map['host'] as String? ?? '127.0.0.1';
        port = (map['port'] as num?)?.toInt() ?? 41530;
        token = map['token'] as String? ?? '';
      } else if (trimmed.contains(':')) {
        final parts = trimmed.split(':');
        host = parts[0];
        port = int.tryParse(parts[1]) ?? 41530;
      }
    } catch (_) {}

    final success = await service.client.connect(
      host: host,
      port: port,
      token: token,
      name: 'OMNIA Mobile',
    );

    if (mounted) {
      setState(() {
        _isConnectingClient = false;
        if (!success) {
          _clientError = 'Impossible de joindre le PC ($host:$port). Vérifiez le réseau WiFi.';
        }
      });
    }
  }

  Future<void> _connectToRemote() async {
    await _connectWithRawString(_ipController.text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final service = ref.watch(omniaConnectServiceProvider);

    return Container(
      decoration: BoxDecoration(
        color: colors.curtain,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: colors.seam),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Barre de préhension
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.dust.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Icon(Icons.wifi_tethering_rounded, color: colors.projector, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'OMNIA Connect (Zero-Internet)',
                    style: TextStyle(
                      fontFamily: OmniaFonts.ui,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colors.screen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Sélecteur d'onglets (Partager / Télécommande)
              Container(
                decoration: BoxDecoration(
                  color: colors.velvet,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.seam),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _activeTab = _ConnectTab.share),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _activeTab == _ConnectTab.share
                                ? colors.projector.withValues(alpha: 0.25)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'Partager (QR Code)',
                              style: TextStyle(
                                fontFamily: OmniaFonts.ui,
                                fontSize: 13,
                                fontWeight: _activeTab == _ConnectTab.share
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _activeTab == _ConnectTab.share
                                    ? colors.projector
                                    : colors.dust,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _activeTab = _ConnectTab.remote),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _activeTab == _ConnectTab.remote
                                ? colors.projector.withValues(alpha: 0.25)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'Télécommande / Projection',
                              style: TextStyle(
                                fontFamily: OmniaFonts.ui,
                                fontSize: 13,
                                fontWeight: _activeTab == _ConnectTab.remote
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _activeTab == _ConnectTab.remote
                                    ? colors.projector
                                    : colors.dust,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (_activeTab == _ConnectTab.share) ...[
                Text(
                  'Scannez ce QR code avec votre ordinateur ou une autre instance OMNIA '
                  'pour projeter votre écran ou télécommander la lecture en direct sur réseau local.',
                  style: TextStyle(
                    fontFamily: OmniaFonts.ui,
                    fontSize: 13,
                    color: colors.dust,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (_isLoading)
                  const CircularProgressIndicator()
                else if (_pairingData != null)
                  OmniaQrCode(
                    data: _pairingData!,
                    size: 200,
                    color: colors.velvet,
                    backgroundColor: colors.screen,
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      service.hasConnectedClients
                          ? Icons.check_circle_rounded
                          : Icons.hourglass_top_rounded,
                      size: 16,
                      color: service.hasConnectedClients ? Colors.green : colors.projector,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      service.hasConnectedClients
                          ? 'Périphérique connecté'
                          : 'En attente de connexion...',
                      style: TextStyle(
                        fontFamily: OmniaFonts.ui,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: service.hasConnectedClients ? Colors.green : colors.screen,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Mode Télécommande / Rejoindre
                _buildRemoteTab(colors, service),
              ],

              const SizedBox(height: 24),
              OmniaButton(
                label: 'Fermer',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRemoteTab(OmniaColors colors, OmniaConnectService service) {
    if (!service.client.connected) {
      if (_isScanning) {
        return Column(
          children: [
            Text(
              'Pointez votre caméra vers le QR Code affiché sur votre ordinateur.',
              style: TextStyle(
                fontFamily: OmniaFonts.ui,
                fontSize: 13,
                color: colors.screen,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 240,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    MobileScanner(
                      controller: _scannerController ??= MobileScannerController(
                        detectionSpeed: DetectionSpeed.normal,
                        facing: CameraFacing.back,
                      ),
                      onDetect: (capture) {
                        for (final barcode in capture.barcodes) {
                          final raw = barcode.rawValue;
                          if (raw != null && raw.isNotEmpty) {
                            _connectWithRawString(raw);
                            break;
                          }
                        }
                      },
                    ),
                    // Viseur visuel avec coins stylisés
                    Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.projector, width: 2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_clientError != null) ...[
              const SizedBox(height: 8),
              Text(_clientError!, style: TextStyle(color: colors.alert, fontSize: 12), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 16),
            OmniaButton(
              label: 'Annuler le scan / Saisie manuelle',
              icon: Icons.keyboard_rounded,
              onPressed: () => setState(() => _isScanning = false),
            ),
          ],
        );
      }

      return Column(
        children: [
          Text(
            'Scannez le QR Code de votre PC avec votre caméra ou saisissez son adresse IP '
            'pour piloter le grand écran à distance.',
            style: TextStyle(
              fontFamily: OmniaFonts.ui,
              fontSize: 13,
              color: colors.dust,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OmniaButton(
            label: 'Scanner le QR Code du PC (Caméra)',
            icon: Icons.qr_code_scanner_rounded,
            primary: true,
            onPressed: () => setState(() => _isScanning = true),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Divider(color: colors.seam)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('OU', style: TextStyle(color: colors.dust, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              Expanded(child: Divider(color: colors.seam)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ipController,
            style: TextStyle(color: colors.screen, fontFamily: OmniaFonts.mono, fontSize: 14),
            decoration: InputDecoration(
              hintText: '192.168.1.X:41530',
              hintStyle: TextStyle(color: colors.dust.withValues(alpha: 0.5)),
              filled: true,
              fillColor: colors.velvet,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.seam),
              ),
              suffixIcon: IconButton(
                icon: Icon(Icons.content_paste_rounded, color: colors.projector, size: 20),
                tooltip: 'Coller depuis le presse-papier',
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null && data!.text!.isNotEmpty) {
                    setState(() {
                      _ipController.text = data.text!;
                    });
                  }
                },
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          if (_clientError != null) ...[
            const SizedBox(height: 8),
            Text(_clientError!, style: TextStyle(color: colors.alert, fontSize: 12), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),
          OmniaButton(
            label: _isConnectingClient ? 'Connexion en cours...' : 'Se connecter au PC',
            icon: Icons.link_rounded,
            onPressed: _isConnectingClient ? null : _connectToRemote,
          ),
        ],
      );
    }

    // Connecté à l'hôte distant : Pad de télécommande tactile
    return StreamBuilder<PlaybackState>(
      stream: service.client.remoteState,
      builder: (context, snapshot) {
        final remote = snapshot.data;
        final title = remote?.file?.name ?? 'Lecture sur PC';
        final isPlaying = remote?.status == PlaybackStatus.playing;

        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Connecté au grand écran',
                  style: TextStyle(
                    fontFamily: OmniaFonts.ui,
                    fontWeight: FontWeight.bold,
                    color: colors.screen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: OmniaFonts.ui,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: colors.projector,
              ),
            ),
            const SizedBox(height: 16),
            // Boutons de commande à distance
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OmniaIconButton(
                  icon: Icons.replay_10_rounded,
                  tooltip: 'Recul 10s',
                  onPressed: () => service.client.sendCommand(const SeekRelative(-10)),
                ),
                OmniaIconButton(
                  icon: Icons.skip_previous_rounded,
                  tooltip: 'Précédent',
                  onPressed: () => service.client.sendCommand(const PreviousFile()),
                ),
                OmniaIconButton(
                  icon: isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                  size: 52,
                  iconSize: 42,
                  active: true,
                  onPressed: () => service.client.sendCommand(const TogglePlay()),
                ),
                OmniaIconButton(
                  icon: Icons.skip_next_rounded,
                  tooltip: 'Suivant',
                  onPressed: () => service.client.sendCommand(const NextFile()),
                ),
                OmniaIconButton(
                  icon: Icons.forward_10_rounded,
                  tooltip: 'Avance 10s',
                  onPressed: () => service.client.sendCommand(const SeekRelative(10)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OmniaIconButton(
                  icon: Icons.volume_down_rounded,
                  tooltip: 'Volume -',
                  onPressed: () => service.client.sendCommand(const VolumeRelative(-5)),
                ),
                const SizedBox(width: 24),
                OmniaIconButton(
                  icon: Icons.volume_up_rounded,
                  tooltip: 'Volume +',
                  onPressed: () => service.client.sendCommand(const VolumeRelative(5)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OmniaButton(
              label: 'Déconnecter la télécommande',
              onPressed: () async {
                await service.client.disconnect();
                setState(() {});
              },
            ),
          ],
        );
      },
    );
  }
}
