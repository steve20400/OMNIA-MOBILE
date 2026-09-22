import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/commands/player_command.dart';
import 'package:omnia_mobile/core/controllers/media_controller.dart';
import 'package:omnia_mobile/core/controllers/media_router.dart';
import 'package:omnia_mobile/core/models/media_file.dart';
import 'package:omnia_mobile/core/models/media_type.dart';

class _StubController implements MediaController {
  _StubController(this.supportedTypes);

  @override
  final Set<MediaType> supportedTypes;

  @override
  Future<void> open(MediaFile file, PlaybackStateSink sink) async {}

  @override
  Future<bool> handle(PlayerCommand command) async => false;

  @override
  Future<void> close() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  group('MediaRouter.typeForPath', () {
    test('vidéo', () {
      for (final ext in ['mp4', 'mkv', 'avi', 'webm', 'mov', 'flv', 'wmv', 'ts', 'm4v', '3gp', 'mpg']) {
        expect(MediaRouter.typeForPath('/films/a.$ext'), MediaType.video, reason: ext);
      }
    });

    test('audio', () {
      for (final ext in ['mp3', 'flac', 'wav', 'ogg', 'aac', 'm4a', 'opus', 'wma']) {
        expect(MediaRouter.typeForPath('/musique/a.$ext'), MediaType.audio, reason: ext);
      }
    });

    test('formats haute résolution, Blu-ray, diffusion et sans perte', () {
      for (final ext in ['m2ts', 'mts', 'hevc', 'h265', 'mxf', 'mk3d', 'wtv', 'ogm', 'y4m']) {
        expect(MediaRouter.typeForPath('/films/a.$ext'), MediaType.video, reason: ext);
      }
      for (final ext in ['dsf', 'dff', 'truehd', 'eac3', 'dtshd', 'm4b', 'weba', 'tak', 'caf']) {
        expect(MediaRouter.typeForPath('/musique/a.$ext'), MediaType.audio, reason: ext);
      }
    });

    test('documents', () {
      expect(MediaRouter.typeForPath('/docs/a.pdf'), MediaType.pdf);
      expect(MediaRouter.typeForPath('/docs/a.txt'), MediaType.text);
      expect(MediaRouter.typeForPath('/docs/a.md'), MediaType.text);
      expect(MediaRouter.typeForPath('/docs/a.log'), MediaType.text);
      expect(MediaRouter.typeForPath('/docs/a.docx'), MediaType.doc);
      expect(MediaRouter.typeForPath('/docs/a.doc'), MediaType.doc);
      expect(MediaRouter.typeForPath('/docs/a.odt'), MediaType.doc);
      expect(MediaRouter.typeForPath('/docs/a.rtf'), MediaType.doc);
      expect(MediaRouter.typeForPath('/docs/a.pptx'), MediaType.doc);
      expect(MediaRouter.typeForPath('/docs/a.ppt'), MediaType.doc);
      expect(MediaRouter.typeForPath('/docs/a.odp'), MediaType.doc);
      expect(MediaRouter.typeForPath('/docs/a.fodt'), MediaType.doc);
      expect(MediaRouter.typeForPath('/docs/a.fodp'), MediaType.doc);
      expect(MediaRouter.typeForPath('/docs/a.aux'), MediaType.text);
      expect(MediaRouter.typeForPath('/docs/a.tex'), MediaType.text);
      expect(MediaRouter.typeForPath('/docs/a.bib'), MediaType.text);
      expect(MediaRouter.typeForPath('/docs/a.cls'), MediaType.text);
      expect(MediaRouter.typeForPath('/docs/a.sty'), MediaType.text);
      expect(MediaRouter.typeForPath('/docs/a.diff'), MediaType.text);
      expect(MediaRouter.typeForPath('/docs/a.patch'), MediaType.text);
      expect(MediaRouter.typeForPath('/docs/a.env'), MediaType.text);
    });

    test('images', () {
      for (final ext in ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'svg']) {
        expect(MediaRouter.typeForPath('/images/a.$ext'), MediaType.image, reason: ext);
      }
    });


    test('insensible à la casse', () {
      expect(MediaRouter.typeForPath('C:\\Films\\A.MKV'), MediaType.video);
      expect(MediaRouter.typeForPath('/m/A.Mp3'), MediaType.audio);
    });

    test('inconnu ou sans extension', () {
      expect(MediaRouter.typeForPath('/x/a.exe'), MediaType.unknown);
      expect(MediaRouter.typeForPath('/x/README'), MediaType.unknown);
      expect(MediaRouter.typeForPath('/x/.hidden'), MediaType.unknown);
      expect(MediaRouter.isSupported('/x/a.exe'), isFalse);
      expect(MediaRouter.isSupported('/x/a.mkv'), isTrue);
    });

    test('les points dans le nom ne perturbent pas l’extension', () {
      expect(MediaRouter.typeForPath('/s/Show.S01E02.1080p.mkv'), MediaType.video);
    });
  });

  group('MediaRouter.controllerFor', () {
    final av = _StubController({MediaType.video, MediaType.audio});
    final pdf = _StubController({MediaType.pdf});
    final router = MediaRouter([av, pdf]);

    test('route vers le contrôleur qui déclare le type', () {
      expect(router.controllerFor(MediaType.video), same(av));
      expect(router.controllerFor(MediaType.audio), same(av));
      expect(router.controllerFor(MediaType.pdf), same(pdf));
    });

    test('null pour un type sans contrôleur', () {
      expect(router.controllerFor(MediaType.text), isNull);
      expect(router.controllerFor(MediaType.unknown), isNull);
    });

    test('controllerForPath combine les deux', () {
      expect(router.controllerForPath('/a/b.flac'), same(av));
      expect(router.controllerForPath('/a/b.pdf'), same(pdf));
      expect(router.controllerForPath('/a/b.bin'), isNull);
    });
  });

  test('chaque extension est en minuscules, lettres et chiffres seulement', () {
    // Le dialogue d'ouverture, l'installateur Windows (généré par
    // tool/make_installer_assoc.py) et son test relisent ces listes avec ce
    // motif : une extension avec tiret ou majuscule y serait perdue.
    for (final ext in MediaRouter.allExtensions) {
      expect(ext, matches(RegExp(r'^[a-z0-9]+$')), reason: ext);
    }
  });

  test('allExtensions couvre toutes les familles sans doublon', () {
    final all = MediaRouter.allExtensions;
    expect(all, containsAll(['mkv', 'mp3', 'pdf', 'md', 'docx', 'png']));
    expect(
      all.length,
      MediaRouter.videoExtensions.length +
          MediaRouter.audioExtensions.length +
          MediaRouter.pdfExtensions.length +
          MediaRouter.docExtensions.length +
          MediaRouter.textExtensions.length +
          MediaRouter.imageExtensions.length,
    );
  });

}
