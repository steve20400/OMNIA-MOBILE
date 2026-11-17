import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/services/mobile_window_service.dart';
import '../core/utils/connect_mode.dart';

/// Vrai quand un média est ouvert et que le téléphone est relié à un PC :
/// il y a alors quelque chose à projeter, et quelqu'un pour le recevoir.
bool canProjectCurrentMedia(WidgetRef ref) {
  // La lecture d'abord : sans fichier ouvert, inutile de réveiller le
  // service OMNIA Connect.
  if (ref.read(playbackStateProvider).file == null) return false;
  return ref.read(omniaConnectServiceProvider).client.connected;
}

/// Envoie au PC relié le média ouvert [path] — ou cet écran, selon le mode
/// de projection choisi dans les réglages — et retourne la phrase à montrer.
///
/// Partagé par le bouton « Projeter » d'OMNIA Connect et par « Actualiser la
/// projection » du menu à trois points : après avoir changé de fichier, un
/// toucher suffit, sans rescanner le code ni rouvrir OMNIA Connect.
Future<String> projectCurrentMedia(WidgetRef ref, String path) async {
  // Tout est lu avant la première attente : le menu qui a lancé la
  // projection s'est refermé entre-temps, et son `ref` avec lui.
  final service = ref.read(omniaConnectServiceProvider);
  final prefs = ref.read(preferencesProvider);
  final window = ref.read(windowServiceProvider);
  // La liaison retenue dans les réglages décide de l'adresse que le PC
  // contactera pour lire le flux.
  final link = connectModeFromPreference(prefs.wirelessMode);
  // Le mode appartient à l'appareil qui projette : c'est lui qui décide si
  // l'autre lit à son rythme, suit ce qu'on fait ici, ou voit cet écran.
  final mode = prefs.projectionMode;

  if (mode == 'screen') {
    final granted =
        window is MobileWindowService && await window.startScreenCapture();
    if (!granted) {
      // Le refus de la boîte du système est un choix de l'utilisateur, pas
      // une panne : il faut le dire comme tel.
      return "Partage d'écran refusé : le système demande votre accord à "
          'chaque session, et rien ne part sans lui.';
    }
    final url = await service.projectScreen(mode: link);
    return url == null
        ? "Partage d'écran impossible : vérifiez le mode de liaison dans "
            'les réglages et que le PC est bien connecté au téléphone.'
        : "Partage d'écran lancé — le PC voit cet écran.";
  }

  final url = await service.projectFile(
    path,
    mode: link,
    mirror: mode == 'mirror',
  );
  return url == null
      ? 'Projection impossible : vérifiez le mode de liaison dans les '
          'réglages et que le PC est bien connecté au téléphone.'
      : 'Projection lancée — le PC lit le flux depuis le téléphone.';
}
