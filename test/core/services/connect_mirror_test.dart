import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/models/media_file.dart';
import 'package:omnia_mobile/core/models/media_type.dart';
import 'package:omnia_mobile/core/models/playback_state.dart';
import 'package:omnia_mobile/core/models/playback_status.dart';
import 'package:omnia_mobile/core/services/omnia_connect_service.dart';

void main() {
  const lecture = PlaybackState(
    file: MediaFile(path: '/films/a.mp4', type: MediaType.video),
    status: PlaybackStatus.playing,
    position: Duration(seconds: 10),
    duration: Duration(minutes: 20),
    volume: 80,
  );
  final pause = lecture.copyWith(status: PlaybackStatus.paused);
  const document = PlaybackState(
    file: MediaFile(path: '/docs/a.pdf', type: MediaType.pdf),
    status: PlaybackStatus.playing,
    currentPage: 4,
    totalPages: 30,
    scrollFraction: 0.2,
  );

  bool part(PlaybackState envoye, PlaybackState suivant) =>
      OmniaConnectService.mirrorWorthSending(envoye, suivant);

  group('Miroir : ce qui mérite un envoi', () {
    test('le premier état part toujours', () {
      expect(OmniaConnectService.mirrorWorthSending(null, lecture), isTrue);
    });

    test('la pause part, alors que la position ne bouge pas', () {
      // Le défaut corrigé ici : l'envoi était cadencé sur la seule position
      // de lecture, qui ne bouge plus en pause. Mettre en pause sur le
      // téléphone ne mettait donc jamais l'autre appareil en pause.
      expect(part(lecture, pause), isTrue);
      expect(part(pause, lecture), isTrue, reason: 'et la reprise aussi');
    });

    test("le volume réglé à l'arrêt part", () {
      // Même cause : à l'arrêt, plus rien ne partait. Le volume ne suivait
      // que pendant la lecture, d'où « parfois oui, parfois non ».
      expect(part(pause, pause.copyWith(volume: 60)), isTrue);
    });

    test("un petit déplacement à l'arrêt part", () {
      expect(
        part(
          pause,
          pause.copyWith(position: const Duration(seconds: 10, milliseconds: 200)),
        ),
        isTrue,
      );
    });

    test("un défilement lent d'un document part", () {
      // La position de lecture d'un document est immobile par nature : rien
      // ne partait tant qu'on ne changeait pas de page. Faire défiler
      // doucement ne suivait donc pas, un grand saut si.
      expect(part(document, document.copyWith(scrollFraction: 0.201)), isTrue);
      expect(part(document, document.copyWith(currentPage: 5)), isTrue);
    });

    test('en lecture, la position seule ne part que toutes les demi-secondes', () {
      // Elle change à chaque image : sans cette retenue, le miroir enverrait
      // soixante états par seconde pour dire que le temps passe.
      expect(
        part(
          lecture,
          lecture.copyWith(
            position: const Duration(seconds: 10, milliseconds: 100),
          ),
        ),
        isFalse,
      );
      expect(
        part(
          lecture,
          lecture.copyWith(
            position: const Duration(seconds: 10, milliseconds: 600),
          ),
        ),
        isTrue,
      );
    });

    test("rien n'a changé : rien ne part", () {
      expect(part(lecture, lecture), isFalse);
      expect(part(pause, pause), isFalse);
      expect(part(document, document), isFalse);
    });
  });
}
