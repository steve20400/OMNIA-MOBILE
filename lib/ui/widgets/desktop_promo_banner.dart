import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/providers.dart';
import '../theme/omnia_theme.dart';
import 'omnia_button.dart';
import 'omnia_qr_code.dart';

/// URL officielle du dépôt OMNIA Desktop.
const String omniaDesktopUrl = 'https://github.com/steve20400/OMNIA-Descktop';

/// Bannière incitative élégante invitant l'utilisateur mobile à découvrir la version PC.
class DesktopPromoBanner extends ConsumerWidget {
  const DesktopPromoBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider);
    final colors = context.colors;

    // Conditions de masquage
    if (prefs.desktopPromoDismissed) return const SizedBox.shrink();
    if (prefs.desktopPromoSnoozeUntil != null &&
        DateTime.now().isBefore(prefs.desktopPromoSnoozeUntil!)) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.curtain,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.projector.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.projector.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.devices_rounded, color: colors.projector, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Découvrez OMNIA pour PC',
                      style: TextStyle(
                        fontFamily: OmniaFonts.ui,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colors.screen,
                      ),
                    ),
                    Text(
                      'Synchronisation locale sans Internet, projection & télécommande.',
                      style: TextStyle(
                        fontFamily: OmniaFonts.ui,
                        fontSize: 12,
                        color: colors.dust,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Wrap et non Row : sur un écran étroit les trois boutons passeraient
          // les uns sur les autres (débordement RenderFlex) et « Plus tard »
          // disparaîtrait. Le Wrap les fait redescendre sur une ligne suivante.
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: () {
                  final bus = ref.read(commandBusProvider);
                  bus.dispatch(
                    UpdatePreferences.between(
                      prefs,
                      prefs.copyWith(
                        desktopPromoSnoozeUntil: DateTime.now().add(const Duration(days: 7)),
                      ),
                    ),
                  );
                },
                child: Text(
                  'Plus tard',
                  style: TextStyle(
                    fontFamily: OmniaFonts.ui,
                    fontSize: 12,
                    color: colors.dust,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  final bus = ref.read(commandBusProvider);
                  bus.dispatch(
                    UpdatePreferences.between(
                      prefs,
                      prefs.copyWith(desktopPromoDismissed: true),
                    ),
                  );
                },
                child: Text(
                  'Ne plus afficher',
                  style: TextStyle(
                    fontFamily: OmniaFonts.ui,
                    fontSize: 12,
                    color: colors.dust.withValues(alpha: 0.7),
                  ),
                ),
              ),
              OmniaButton(
                label: 'Découvrir',
                icon: Icons.qr_code_rounded,
                onPressed: () => _showPromoDialog(context, colors),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showPromoDialog(BuildContext context, OmniaColors colors) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: colors.curtain,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.laptop_chromebook_rounded, color: colors.projector, size: 24),
              const SizedBox(width: 10),
              Text(
                'OMNIA pour Bureau',
                style: TextStyle(
                  fontFamily: OmniaFonts.ui,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colors.screen,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Scannez ce QR code ou ouvrez le lien pour installer OMNIA sur votre PC Linux ou Windows :',
                style: TextStyle(
                  fontFamily: OmniaFonts.ui,
                  fontSize: 13,
                  color: colors.dust,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              OmniaQrCode(
                data: omniaDesktopUrl,
                size: 190,
                color: colors.velvet,
                backgroundColor: colors.screen,
              ),
              const SizedBox(height: 14),
              SelectableText(
                omniaDesktopUrl,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: OmniaFonts.mono,
                  fontSize: 11,
                  color: colors.projector,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
          actions: [
            OmniaButton(
              label: 'Fermer',
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        );
      },
    );
  }
}
