import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/controllers/media_router.dart';
import 'package:omnia_mobile/core/models/media_file.dart';
import 'package:omnia_mobile/core/models/media_type.dart';
import 'package:omnia_mobile/core/utils/content_uri.dart';

const String _videoUri =
    'content://com.android.providers.media.documents/document/video%3A42';
const String _docUri =
    'content://com.google.android.apps.docs.storage/document/acc%3D1%3Bdoc%3D9';

void main() {
  setUp(forgetContentUriNames);
  tearDown(forgetContentUriNames);

  group('Reconnaissance des URI de contenu', () {
    test('un URI Android est reconnu', () {
      expect(isContentUri(_videoUri), isTrue);
    });

    test('un chemin de fichier ordinaire ne l est pas', () {
      expect(isContentUri('/storage/emulated/0/Films/episode.avi'), isFalse);
      expect(isContentUri('https://exemple.test/flux.mp4'), isFalse);
    });
  });

  group('Registre des noms relevés', () {
    test('le nom relevé est rendu tel quel', () {
      rememberContentUriName(_videoUri, 'Le Voyage.avi');
      expect(contentUriDisplayName(_videoUri), 'Le Voyage.avi');
    });

    test('un URI inconnu ne rend aucun nom', () {
      expect(contentUriDisplayName(_videoUri), isNull);
    });

    test('un nom vide ou un chemin ordinaire ne sont pas retenus', () {
      rememberContentUriName(_videoUri, '');
      rememberContentUriName('/storage/emulated/0/a.mp4', 'a.mp4');
      expect(contentUriDisplayName(_videoUri), isNull);
      expect(contentUriDisplayName('/storage/emulated/0/a.mp4'), isNull);
    });

    test('les plus anciens noms sont oubliés au-delà de la capacité', () {
      final last = maxRememberedNames + 9;
      for (var i = 0; i <= last; i++) {
        rememberContentUriName('content://test/$i', 'fichier$i.mp4');
      }
      // Le premier est parti, le dernier est là : le registre ne gonfle pas
      // indéfiniment pendant une longue session.
      expect(contentUriDisplayName('content://test/0'), isNull);
      expect(contentUriDisplayName('content://test/$last'), 'fichier$last.mp4');
    });

    test('la capacité tient un dossier entier de voisins partagés', () {
      // Le panneau retient le nom de chaque voisin que MediaStore a listé : une
      // série de 200 épisodes ne doit pas perdre les premiers en route.
      for (var i = 0; i < 200; i++) {
        rememberContentUriName('content://test/$i', 'fichier$i.mp4');
      }
      expect(contentUriDisplayName('content://test/0'), 'fichier0.mp4');
      expect(contentUriDisplayName('content://test/199'), 'fichier199.mp4');
    });

    test('réinscrire un URI le remet en tête de file', () {
      rememberContentUriName('content://test/a', 'a.mp4');
      for (var i = 0; i < maxRememberedNames; i++) {
        rememberContentUriName('content://test/$i', 'fichier$i.mp4');
      }
      rememberContentUriName('content://test/a', 'a.mp4');
      rememberContentUriName('content://test/neuf', 'neuf.mp4');
      expect(contentUriDisplayName('content://test/a'), 'a.mp4');
    });
  });

  group('Copies faites par la plateforme', () {
    // Le fichier recopié en cache porte un nom horodaté et expurgé : sans le
    // registre, c'est « 1738..._Le_Voyage.avi » que l'utilisateur lisait, et
    // c'est ce nom-là que la recherche des voisins aurait présenté à
    // MediaStore, qui n'en connaît aucun.
    const copy =
        '/data/user/0/dev.omnia.mobile/cache/opened_media/1738_Le_Voyage.avi';
    const picked =
        '/data/user/0/dev.omnia.mobile/cache/file_picker/Le Voyage.avi';

    test('une copie est reconnue, un vrai fichier non', () {
      expect(isCopiedFromProvider(copy), isTrue);
      expect(isCopiedFromProvider(picked), isTrue);
      expect(
        isCopiedFromProvider('/storage/emulated/0/Films/Le Voyage.avi'),
        isFalse,
      );
    });

    test('le nom réel d une copie est retenu et affiché', () {
      rememberContentUriName(copy, 'Le Voyage.avi');
      const file = MediaFile(path: copy, type: MediaType.video);
      expect(file.name, 'Le Voyage.avi');
      expect(file.baseName, 'Le Voyage');
    });
  });

  group('Type de média derrière un URI', () {
    test('le nom relevé donne le type', () {
      rememberContentUriName(_videoUri, 'Le Voyage.avi');
      expect(MediaRouter.typeForPath(_videoUri), MediaType.video);
    });

    test('un document reste un document', () {
      rememberContentUriName(_docUri, 'Contrat.pdf');
      expect(MediaRouter.typeForPath(_docUri), MediaType.pdf);
    });

    test('sans nom relevé, le type reste inconnu', () {
      // Mieux vaut un refus franc qu'un document poussé dans le lecteur vidéo.
      expect(MediaRouter.typeForPath(_videoUri), MediaType.unknown);
    });

    test('un URI sans extension dans son nom reste inconnu', () {
      rememberContentUriName(_videoUri, 'piece_jointe');
      expect(MediaRouter.typeForPath(_videoUri), MediaType.unknown);
    });
  });

  group('Nom affiché du média', () {
    test('un URI porte le nom relevé, pas son dernier segment', () {
      rememberContentUriName(_videoUri, 'Le Voyage.avi');
      const file = MediaFile(path: _videoUri, type: MediaType.video);
      expect(file.name, 'Le Voyage.avi');
      expect(file.baseName, 'Le Voyage');
      expect(file.extension, 'avi');
    });

    test('un chemin ordinaire garde son nom de fichier', () {
      const file = MediaFile(
        path: '/storage/emulated/0/Films/episode-02.mkv',
        type: MediaType.video,
      );
      expect(file.name, 'episode-02.mkv');
      expect(file.baseName, 'episode-02');
      expect(file.extension, 'mkv');
    });
  });
}
