import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/commands/player_command.dart';
import 'package:omnia_mobile/core/commands/player_command_bus.dart';
import 'package:omnia_mobile/core/models/end_of_playback_mode.dart';
import 'package:omnia_mobile/core/models/media_file.dart';
import 'package:omnia_mobile/core/models/media_type.dart';
import 'package:omnia_mobile/core/models/playback_state.dart';
import 'package:omnia_mobile/core/models/playback_status.dart';
import 'package:omnia_mobile/ui/osd/osd_message.dart';

void main() {
  const playing = PlaybackState(
    file: MediaFile(path: '/serie/ep2.mkv', type: MediaType.video),
    status: PlaybackStatus.playing,
    position: Duration(minutes: 1, seconds: 5),
    duration: Duration(minutes: 40),
    volume: 65,
    speed: 1.25,
  );
  const idle = PlaybackState();

  group('osdWantedFor', () {
    // Action ordinaire : son résultat se lit déjà dans le contrôle manipulé.
    const ordinary = SpeedRelative(0.25);

    test('clavier, ligne de commande, système, télécommande : toujours', () {
      for (final source in [
        CommandSource.keyboard,
        CommandSource.cli,
        CommandSource.system,
        CommandSource.remote,
      ]) {
        expect(
          osdWantedFor(ordinary, source, controlsHidden: false),
          isTrue,
          reason: source.name,
        );
        expect(
          osdWantedFor(ordinary, source, controlsHidden: true),
          isTrue,
          reason: source.name,
        );
      }
    });

    test('souris : une action déjà visible attend que la barre soit masquée', () {
      expect(osdWantedFor(ordinary, CommandSource.ui, controlsHidden: false), isFalse);
      expect(osdWantedFor(ordinary, CommandSource.ui, controlsHidden: true), isTrue);
    });

    test('le volume s’annonce toujours, barre visible comprise', () {
      const volumeCommands = [SetVolume(40), VolumeRelative(5), ToggleMute()];
      for (final command in volumeCommands) {
        expect(
          osdWantedFor(command, CommandSource.ui, controlsHidden: false),
          isTrue,
          reason: command.type,
        );
        expect(
          osdWantedFor(command, CommandSource.keyboard, controlsHidden: false),
          isTrue,
          reason: command.type,
        );
      }
    });

    test('capture et extrait s’annoncent toujours : aucun autre retour', () {
      for (final command in const [TakeScreenshot(), ToggleRecording()]) {
        expect(
          osdWantedFor(command, CommandSource.ui, controlsHidden: false),
          isTrue,
          reason: command.type,
        );
      }
    });

    test('glissement sur le faisceau : rien tant que la barre est visible', () {
      // Un glissement envoie une commande par pixel, et retient la barre
      // affichée : la lampe suit déjà le doigt, l'OSD se tait.
      const drag = SeekAbsolute(Duration(minutes: 10));
      expect(osdWantedFor(drag, CommandSource.ui, controlsHidden: false), isFalse);
      // Barre masquée (ou touche du clavier), l'OSD reprend son rôle.
      expect(osdWantedFor(drag, CommandSource.ui, controlsHidden: true), isTrue);
      expect(osdWantedFor(drag, CommandSource.keyboard, controlsHidden: false), isTrue);
    });
  });

  group('osdFor', () {
    test('avance / recul', () {
      final m = osdFor(const SeekRelative(5), playing);
      expect(m, isA<OsdSeek>());
      final seek = m! as OsdSeek;
      expect(seek.deltaSeconds, 5);
      expect(seek.position, const Duration(minutes: 1, seconds: 5));
      expect(seek.duration, const Duration(minutes: 40));
    });

    test('seek absolu : pas de delta', () {
      final m = osdFor(const SeekAbsolute(Duration(minutes: 10)), playing)! as OsdSeek;
      expect(m.deltaSeconds, 0);
    });

    test('volume et sourdine', () {
      final v = osdFor(const VolumeRelative(5), playing)! as OsdVolume;
      expect(v.volume, 65);
      expect(v.muted, isFalse);

      final muted = osdFor(const ToggleMute(), playing.copyWith(muted: true))! as OsdVolume;
      expect(muted.muted, isTrue);
    });

    test('le volume s’affiche même sans fichier', () {
      expect(osdFor(const SetVolume(30), idle.copyWith(volume: 30)), isA<OsdVolume>());
    });

    test('vitesse', () {
      final s = osdFor(const SpeedRelative(0.25), playing)! as OsdSpeed;
      expect(s.speed, 1.25);
    });

    test('lecture / pause', () {
      final p = osdFor(const TogglePlay(), playing)! as OsdPlayState;
      expect(p.playing, isTrue);
      final paused = osdFor(const TogglePlay(), playing.copyWith(status: PlaybackStatus.paused))!
          as OsdPlayState;
      expect(paused.playing, isFalse);
    });

    test('changement de fichier', () {
      final n = osdFor(const NextFile(), playing)! as OsdFileChanged;
      expect(n.name, 'ep2.mkv');
      expect(n.forward, isTrue);
      final p = osdFor(const PreviousFile(), playing)! as OsdFileChanged;
      expect(p.forward, isFalse);
    });

    test('mode de fin, premier plan, plein écran', () {
      expect(
        (osdFor(const CycleLoopMode(), playing.copyWith(endMode: EndOfPlaybackMode.shuffle))!
                as OsdEndMode)
            .mode,
        EndOfPlaybackMode.shuffle,
      );
      expect(
        (osdFor(const ToggleAlwaysOnTop(), playing.copyWith(alwaysOnTop: true))!
                as OsdAlwaysOnTop)
            .enabled,
        isTrue,
      );
      expect(
        (osdFor(const ToggleFullscreen(), playing.copyWith(fullscreen: true))! as OsdFullscreen)
            .enabled,
        isTrue,
      );
    });

    test('sans fichier, les actions de lecture ne produisent rien', () {
      expect(osdFor(const SeekRelative(5), idle), isNull);
      expect(osdFor(const TogglePlay(), idle), isNull);
      expect(osdFor(const SpeedRelative(0.25), idle), isNull);
      expect(osdFor(const NextFile(), idle), isNull);
    });

    test('capture : chemin enregistré, ou échec signalé', () {
      expect(
        osdFor(const TakeScreenshot(), playing.copyWith(lastScreenshot: '/c/a.png')),
        isA<OsdScreenshot>(),
      );
      expect(
        osdFor(const TakeScreenshot(), playing.copyWith(screenshotFailed: true)),
        isA<OsdScreenshotFailed>(),
      );
      // Rien d'enregistré (fichier audio) : pas de message.
      expect(osdFor(const TakeScreenshot(), playing), isNull);
    });

    test('capture sans image obtenue : l’échec s’affiche quand même', () {
      // Devant une image, ni chemin ni drapeau veut dire que rien n'a été
      // capturé : sans message, le bouton passerait pour inerte.
      expect(
        osdFor(const TakeScreenshot(), playing.copyWith(hasVideo: true)),
        isA<OsdScreenshotFailed>(),
      );
    });

    test('extrait : le début s’annonce à la commande ; la fin, par l’état', () {
      expect(
        osdFor(const ToggleRecording(), playing.copyWith(recordingPath: '/c/a.mkv')),
        isA<OsdRecordingStarted>(),
      );
      // L'arrêt réussi est annoncé par OsdController, qui suit l'état : un
      // extrait s'arrête aussi en changeant de fichier, sans commande.
      expect(osdFor(const ToggleRecording(), playing.copyWith(lastRecording: '/c/a.mkv')), isNull);
    });

    test('extrait impossible : l’échec répond à chaque appui', () {
      // Deux tentatives impossibles de suite (lecture en pause, document)
      // laissent le même état : le suivi d'état ne voit aucun front, et seule
      // la commande peut encore répondre au second appui.
      expect(
        osdFor(const ToggleRecording(), playing.copyWith(recordingFailed: true)),
        isA<OsdRecordingFailed>(),
      );
      // Sans fichier ouvert, il n'y a rien à enregistrer ni à annoncer.
      expect(osdFor(const ToggleRecording(), idle.copyWith(recordingFailed: true)), isNull);
    });

    test('les commandes sans retour visuel ne produisent rien', () {
      expect(osdFor(const OpenFile('/x.mkv'), playing), isNull);
      expect(osdFor(const SetPlaylistQuery('a'), playing), isNull);
      expect(osdFor(const ToggleSidePanel(), playing), isNull);
      expect(osdFor(const Stop(), playing), isNull);
    });
  });
}
