import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command_bus.dart';
import '../../core/models/playback_state.dart';
import '../../core/providers.dart';
import '../chrome_controller.dart';
import '../theme/omnia_motion.dart';
import 'osd_message.dart';

/// Message OSD courant, `null` quand rien n'est affiché.
final osdProvider = NotifierProvider<OsdController, OsdMessage?>(OsdController.new);

/// Écoute le bus, attend que la commande soit traitée, puis publie le message
/// à afficher. Un nouveau message remplace le précédent et relance le délai.
class OsdController extends Notifier<OsdMessage?> {
  Timer? _hide;
  StreamSubscription<DispatchedCommand>? _subscription;
  StreamSubscription<PlaybackState>? _states;

  @override
  OsdMessage? build() {
    final bus = ref.watch(commandBusProvider);
    final service = ref.watch(playbackServiceProvider);

    _subscription = bus.stream.listen((dispatched) async {
      // La règle dépend de la commande autant que de son origine : le volume,
      // la capture et l'extrait s'annoncent même barre visible (osd_message).
      if (!osdWantedFor(
        dispatched.command,
        dispatched.source,
        controlsHidden: !ref.read(chromeProvider),
      )) {
        return;
      }
      // La commande n'est pas encore traitée quand elle arrive ici : on
      // attend que la file du service l'ait exécutée pour lire l'état obtenu.
      await service.idle;
      final message = osdFor(dispatched.command, service.state);
      if (message == null) return;
      show(message);
    });

    // Extraits : la fin d'un enregistrement s'annonce toujours, qu'elle vienne
    // de l'utilisateur ou d'un changement de fichier, et un échec aussi. Hors
    // de l'OSD, un extrait n'a aucun retour : l'indicateur REC s'éteint, et
    // c'est tout — ni le fichier écrit ni l'échec ne se voient.
    var previous = service.state;
    _states = service.stream.listen((next) {
      final before = previous;
      previous = next;

      // Fin d'un extrait. Le message porte le chemin quand un fichier a bien
      // été écrit ; sans fichier, c'est un échec, drapeau levé ou non : l'un
      // et l'autre arrivent dans la même mise à jour d'état.
      if (before.recording && !next.recording) {
        final saved = next.recordingFailed ? null : next.lastRecording;
        if (saved == null) {
          show(const OsdRecordingFailed());
          return;
        }
        final started = before.recordingStartedAt;
        show(OsdRecordingSaved(
          saved,
          length: started == null ? null : DateTime.now().difference(started),
        ));
        return;
      }

      // Échec au démarrage : l'indicateur REC ne s'allume même pas, seul ce
      // message dit pourquoi. Le suivi d'état ne voit que le premier échec —
      // le suivant laisse l'état inchangé, même raison —, c'est pourquoi
      // `osdFor` annonce aussi l'échec à la commande : un appui, une réponse.
      if (!before.recordingFailed && next.recordingFailed) {
        show(const OsdRecordingFailed());
      }
    });

    ref.onDispose(() {
      _subscription?.cancel();
      _states?.cancel();
      _hide?.cancel();
    });
    return null;
  }

  void show(OsdMessage message) {
    state = message;
    _hide?.cancel();
    _hide = Timer(OmniaMotion.osdLinger, () => state = null);
  }
}
