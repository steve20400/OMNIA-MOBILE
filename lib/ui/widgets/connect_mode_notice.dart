import 'package:flutter/material.dart';

import '../../core/utils/connect_mode.dart';
import '../theme/omnia_theme.dart';

/// Encart qui dit où en est le mode de liaison choisi.
///
/// Les boutons Bluetooth / point d'accès / Wi-Fi ne faisaient qu'enregistrer
/// la préférence : au clic, rien ne se passait à l'écran et l'appairage
/// échouait plus tard sans explication. Cet encart est la réponse visible du
/// clic — soit l'adresse à annoncer, soit ce qui manque et la marche à suivre.
class ConnectModeNotice extends StatelessWidget {
  const ConnectModeNotice({
    super.key,
    required this.report,
    this.checking = false,
  });

  /// Rapport du contrôle des prérequis, `null` tant qu'il n'a pas été fait.
  final ConnectModeReport? report;

  /// Contrôle en cours : on le montre plutôt que de laisser l'encart vide.
  final bool checking;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final current = report;

    // Rien à dire tant qu'aucun contrôle n'a été lancé : un encart vide vaut
    // mieux qu'un indicateur d'attente qui ne finirait jamais.
    if (current == null && !checking) return const SizedBox.shrink();

    if (checking || current == null) {
      // Pas d'indicateur de progression animé ici : la sonde réseau est
      // bornée dans le temps, et une animation indéfinie laisserait un
      // panneau qui tourne sans fin si le système ne répondait jamais.
      return _Frame(
        background: colors.seam.withValues(alpha: 0.25),
        border: colors.seam,
        child: Row(
          children: [
            Icon(Icons.sensors_rounded, size: 16, color: colors.dust),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Vérification des prérequis…',
                style: type.secondary.copyWith(color: colors.dust),
              ),
            ),
          ],
        ),
      );
    }

    final ready = current.ready;
    final accent = ready ? Colors.green : colors.projector;
    return _Frame(
      background: accent.withValues(alpha: 0.12),
      border: accent.withValues(alpha: 0.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ready ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 16,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mode ${current.mode.label}',
                  style: type.bodyStrong.copyWith(color: accent),
                ),
                const SizedBox(height: 2),
                // Le constat puis la marche à suivre : l'utilisateur doit
                // savoir quoi faire, pas seulement que ça ne marche pas.
                Text(
                  current.message,
                  style: type.secondary.copyWith(
                    color: colors.screen,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.child,
    required this.background,
    required this.border,
  });

  final Widget child;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: child,
    );
  }
}
