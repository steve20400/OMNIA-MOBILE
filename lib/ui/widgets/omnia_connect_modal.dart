import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/playback_state.dart';
import '../../core/models/playback_status.dart';
import '../../core/providers.dart';
import '../../core/services/omnia_connect_service.dart';
import '../theme/omnia_theme.dart';
import 'omnia_button.dart';
import 'omnia_icon_button.dart';
import 'omnia_qr_code.dart';

enum _ConnectTab { scanDesktop, mobileQr }

/// Dialogue interactif d'appairage OMNIA Connect (Zero-Internet).
///
/// Permet à la fois de :
/// 1. Scanner le QR code du PC Desktop ou coller son code d'appairage pour le contrôler.
/// 2. Afficher le QR code de ce mobile pour qu'un Desktop ou un autre appareil puisse le scanner.
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

class _OmniaConnectModalState extends ConsumerState<OmniaConnectModal>
    with SingleTickerProviderStateMixin {
  late _ConnectTab _activeTab;
  String? _pairingData;
  bool _isLoading = true;
  StreamSubscription<PlayerCommand>? _cmdSubscription;

  // Contrôleur de saisie pour la connexion manuelle / code
  final TextEditingController _ipController = TextEditingController();
  bool _isConnectingClient = false;
  String? _clientError;
  String? _pasteSuccessMessage;

  // Animation pour le viseur du scanner de QR code
  late final AnimationController _scannerAnimController;

  @override
  void initState() {
    super.initState();
    if (widget.initialPairingData != null) {
      _activeTab = _ConnectTab.mobileQr;
      _pairingData = widget.initialPairingData;
      _isLoading = false;
    } else {
      _activeTab = _ConnectTab.scanDesktop;
      _scannerAnimController.repeat(reverse: true);
      _initConnect();
    }
  }

  @override
  void dispose() {
    _cmdSubscription?.cancel();
    _ipController.dispose();
    _scannerAnimController.dispose();
    super.dispose();
  }

  Future<void> _initConnect() async {
    final service = ref.read(omniaConnectServiceProvider);
    await service.start();
    final payload = await service.getPairingPayload('OMNIA Mobile');

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

  Future<void> _connectWithData(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _isConnectingClient = true;
      _clientError = null;
      _pasteSuccessMessage = null;
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
          _clientError = 'Connexion impossible. Assurez-vous que le PC et le mobile sont sur le même réseau WiFi.';
        } else {
          _pasteSuccessMessage = 'Connecté avec succès au PC Desktop !';
        }
      });
    }
  }

  Future<void> _pasteAndConnect() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      _ipController.text = text;
      await _connectWithData(text);
    } else {
      setState(() {
        _clientError = 'Presse-papier vide. Copiez le code affiché sur votre PC Desktop.';
      });
    }
  }

  void _switchTab(_ConnectTab tab) {
    if (_activeTab == tab) return;
    setState(() => _activeTab = tab);
    if (tab == _ConnectTab.scanDesktop) {
      _scannerAnimController.repeat(reverse: true);
    } else {
      _scannerAnimController.stop();
    }
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
              // Poignée de préhension
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

              // Sélecteur d'onglets : Scanner le PC vs Mon code QR Mobile
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
                        onTap: () => _switchTab(_ConnectTab.scanDesktop),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _activeTab == _ConnectTab.scanDesktop
                                ? colors.projector.withValues(alpha: 0.25)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.qr_code_scanner_rounded,
                                size: 16,
                                color: _activeTab == _ConnectTab.scanDesktop
                                    ? colors.projector
                                    : colors.dust,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Scanner le PC',
                                style: TextStyle(
                                  fontFamily: OmniaFonts.ui,
                                  fontSize: 12,
                                  fontWeight: _activeTab == _ConnectTab.scanDesktop
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _activeTab == _ConnectTab.scanDesktop
                                      ? colors.projector
                                      : colors.dust,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => _switchTab(_ConnectTab.mobileQr),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _activeTab == _ConnectTab.mobileQr
                                ? colors.projector.withValues(alpha: 0.25)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.qr_code_2_rounded,
                                size: 16,
                                color: _activeTab == _ConnectTab.mobileQr
                                    ? colors.projector
                                    : colors.dust,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Mon code QR',
                                style: TextStyle(
                                  fontFamily: OmniaFonts.ui,
                                  fontSize: 12,
                                  fontWeight: _activeTab == _ConnectTab.mobileQr
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _activeTab == _ConnectTab.mobileQr
                                      ? colors.projector
                                      : colors.dust,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (_activeTab == _ConnectTab.scanDesktop) ...[
                _buildScanDesktopTab(colors, service),
              ] else ...[
                _buildMobileQrTab(colors, service),
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

  /// Onglet 1 : Scanner le QR code du PC Desktop ou coller le code d'appairage
  Widget _buildScanDesktopTab(OmniaColors colors, OmniaConnectService service) {
    if (service.client.connected) {
      return _buildConnectedRemotePad(colors, service);
    }

    return Column(
      children: [
        Text(
          'Scannez le QR code affiché sur votre PC OMNIA Desktop, '
          'ou collez ci-dessous son code d’appairage local.',
          style: TextStyle(
            fontFamily: OmniaFonts.ui,
            fontSize: 13,
            color: colors.dust,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),

        // Cadre de visée de scan QR animé avec coins ambrés
        Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            color: colors.velvet,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.seam),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Coins décoratifs du viseur
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: colors.projector, width: 3),
                      left: BorderSide(color: colors.projector, width: 3),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: colors.projector, width: 3),
                      right: BorderSide(color: colors.projector, width: 3),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: colors.projector, width: 3),
                      left: BorderSide(color: colors.projector, width: 3),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: colors.projector, width: 3),
                      right: BorderSide(color: colors.projector, width: 3),
                    ),
                  ),
                ),
              ),
              // Ligne de balayage animée
              AnimatedBuilder(
                animation: _scannerAnimController,
                builder: (context, child) {
                  return Positioned(
                    top: 16 + (_scannerAnimController.value * 144),
                    left: 16,
                    right: 16,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            colors.projector,
                            Colors.transparent,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colors.projector.withValues(alpha: 0.6),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              // Icône centrale
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_scanner_rounded, color: colors.projector.withValues(alpha: 0.8), size: 48),
                  const SizedBox(height: 8),
                  Text(
                    'Viseur Caméra / QR',
                    style: TextStyle(
                      fontFamily: OmniaFonts.ui,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.dust,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Bouton proéminent pour coller le code d'appairage du PC
        OmniaButton(
          label: _isConnectingClient ? 'Connexion en cours...' : 'Coller le code du Desktop',
          icon: _isConnectingClient ? Icons.hourglass_top_rounded : Icons.content_paste_go_rounded,
          primary: true,
          onPressed: _isConnectingClient ? null : _pasteAndConnect,
        ),
        const SizedBox(height: 12),

        // Saisie manuelle de l'adresse IP / Port
        TextField(
          controller: _ipController,
          style: TextStyle(color: colors.screen, fontFamily: OmniaFonts.mono, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'ex: 192.168.1.45:41530 ou code JSON',
            hintStyle: TextStyle(color: colors.dust.withValues(alpha: 0.5)),
            filled: true,
            fillColor: colors.velvet,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.seam),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            suffixIcon: _isConnectingClient
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: colors.projector),
                    ),
                  )
                : IconButton(
                    icon: Icon(Icons.send_rounded, color: colors.projector, size: 20),
                    tooltip: 'Se connecter',
                    onPressed: () => _connectWithData(_ipController.text),
                  ),
          ),
        ),

        if (_pasteSuccessMessage != null) ...[
          const SizedBox(height: 8),
          Text(_pasteSuccessMessage!, style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
        if (_clientError != null) ...[
          const SizedBox(height: 8),
          Text(_clientError!, style: TextStyle(color: colors.alert, fontSize: 12), textAlign: TextAlign.center),
        ],
      ],
    );
  }

  /// Onglet 2 : Afficher le QR code de ce mobile
  Widget _buildMobileQrTab(OmniaColors colors, OmniaConnectService service) {
    return Column(
      children: [
        Text(
          'Scannez ce QR code depuis OMNIA Desktop ou un autre appareil '
          'pour diffuser l’écran ou télécommander ce mobile.',
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
                  ? 'PC Desktop connecté'
                  : 'En attente de connexion du PC...',
              style: TextStyle(
                fontFamily: OmniaFonts.ui,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: service.hasConnectedClients ? Colors.green : colors.screen,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_pairingData != null)
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _pairingData!));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code d’appairage copié dans le presse-papier !')),
                );
              }
            },
            icon: Icon(Icons.copy_rounded, color: colors.projector, size: 16),
            label: Text(
              'Copier mon code d’appairage',
              style: TextStyle(
                fontFamily: OmniaFonts.ui,
                fontSize: 12,
                color: colors.projector,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  /// Panneau de télécommande tactile lorsque connecté à l'hôte distant
  Widget _buildConnectedRemotePad(OmniaColors colors, OmniaConnectService service) {
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
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Connecté au PC Desktop',
                  style: TextStyle(
                    fontFamily: OmniaFonts.ui,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
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
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: colors.projector,
              ),
            ),
            const SizedBox(height: 16),
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
