import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/providers.dart';
import '../../core/services/omnia_connect_service.dart';
import '../theme/omnia_theme.dart';
import 'omnia_button.dart';
import 'omnia_qr_code.dart';

final omniaConnectServiceProvider = Provider<OmniaConnectService>((ref) {
  final service = OmniaConnectService();
  ref.onDispose(service.dispose);
  return service;
});

/// Dialogue interactif d'appairage et de projection OMNIA Connect (Zero-Internet).
class OmniaConnectModal extends ConsumerStatefulWidget {
  const OmniaConnectModal({super.key});

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
  String? _pairingData;
  bool _isLoading = true;
  StreamSubscription<PlayerCommand>? _cmdSubscription;

  @override
  void initState() {
    super.initState();
    _initConnect();
  }

  @override
  void dispose() {
    _cmdSubscription?.cancel();
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
            const SizedBox(height: 20),

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
            const SizedBox(height: 12),
            Text(
              'Scannez ce QR code avec votre ordinateur ou une autre instance OMNIA '
              'pour projeter votre écran ou télécommander la lecture en direct sur réseau local.',
              style: TextStyle(
                fontFamily: OmniaFonts.ui,
                fontSize: 13,
                color: colors.dust,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),

            if (_isLoading)
              const CircularProgressIndicator()
            else if (_pairingData != null)
              OmniaQrCode(
                data: _pairingData!,
                size: 210,
                color: colors.velvet,
                backgroundColor: colors.screen,
              ),

            const SizedBox(height: 20),
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
            const SizedBox(height: 24),
            OmniaButton(
              label: 'Fermer',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
