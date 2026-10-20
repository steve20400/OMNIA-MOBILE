import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/models/media_type.dart';
import 'package:omnia_mobile/core/utils/content_uri.dart';
import 'package:omnia_mobile/core/utils/shared_siblings.dart';

/// L'URI que le gestionnaire de fichiers a transmis par « Ouvrir avec » : il ne
/// dit rien du stockage, et n'a pas de dossier parent à scanner.
const String _opened =
    'content://com.android.externalstorage.documents/document/primary%3AFilms%2Fep02.mkv';

/// Les voisins, eux, sont désignés par leur ligne MediaStore.
String _mediaUri(int id) => 'content://media/external/video/media/$id';

Map<String, Object?> _row(
  String name,
  String path, {
  int? size,
  int? modified,
}) =>
    <String, Object?>{
      'name': name,
      'path': path,
      'size': size,
      'modified': modified,
    };

void main() {
  setUp(forgetContentUriNames);
  tearDown(forgetContentUriNames);

  group('Voisins d un média partagé', () {
    test('le dossier retrouvé remplit la liste', () {
      final siblings = parseSharedSiblings(
        <String, Object?>{
          'folder': '/storage/emulated/0/Films',
          'self': _mediaUri(12),
          'files': <Object?>[
            _row('ep01.mkv', _mediaUri(11)),
            _row('ep02.mkv', _mediaUri(12)),
            _row('ep03.mkv', _mediaUri(13)),
          ],
        },
        openedPath: _opened,
        openedName: 'ep02.mkv',
      );

      expect(siblings.folder, '/storage/emulated/0/Films');
      expect(siblings.files.length, 3);
      // Le fichier déjà ouvert garde le chemin par lequel le lecteur le
      // connaît : sans cela le panneau ne surlignerait rien, et la reprise
      // chercherait la position d'un autre chemin.
      expect(siblings.files[1].path, _opened);
      expect(siblings.files[0].path, _mediaUri(11));
      expect(siblings.files[2].path, _mediaUri(13));
    });

    test('le nom de chaque voisin est retenu, donc son type et son libellé',
        () {
      final siblings = parseSharedSiblings(
        <String, Object?>{
          'folder': '/storage/emulated/0/Films',
          'self': _mediaUri(12),
          'files': <Object?>[
            _row('ep01.mkv', _mediaUri(11)),
            _row('ep02.mkv', _mediaUri(12)),
          ],
        },
        openedPath: _opened,
        openedName: 'ep02.mkv',
      );

      // Sans le registre des noms, la liste afficherait « media » et le tri
      // naturel n'aurait rien à comparer.
      expect(siblings.files.first.name, 'ep01.mkv');
      expect(siblings.files.first.type, MediaType.video);
      expect(contentUriDisplayName(_mediaUri(11)), 'ep01.mkv');
    });

    test('taille et date remontent telles quelles, en millisecondes', () {
      final siblings = parseSharedSiblings(
        <String, Object?>{
          'folder': '/storage/emulated/0/Films',
          'self': _mediaUri(12),
          'files': <Object?>[
            _row('ep02.mkv', _mediaUri(12), size: 4096, modified: 1700000000000),
            _row('ep03.mkv', _mediaUri(13)),
          ],
        },
        openedPath: _opened,
        openedName: 'ep02.mkv',
      );

      expect(siblings.files.first.size, 4096);
      expect(
        siblings.files.first.modifiedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      // Colonnes absentes : le tri par date et par taille les range en dernier,
      // il ne doit pas croire à un fichier vide de 1970.
      expect(siblings.files.last.size, isNull);
      expect(siblings.files.last.modifiedAt, isNull);
    });

    test('ce qu OMNIA ne lit pas est écarté', () {
      final siblings = parseSharedSiblings(
        <String, Object?>{
          'folder': '/storage/emulated/0/Films',
          'self': _mediaUri(12),
          'files': <Object?>[
            _row('ep02.mkv', _mediaUri(12)),
            _row('ep02.nfo', _mediaUri(14)),
            _row('vignette.db', _mediaUri(15)),
            _row('bande-son.mp3', _mediaUri(16)),
          ],
        },
        openedPath: _opened,
        openedName: 'ep02.mkv',
      );

      expect(
        siblings.files.map((f) => f.name),
        <String>['ep02.mkv', 'bande-son.mp3'],
      );
    });

    test('un voisin déjà listé ne fait pas deux lignes', () {
      // Un même fichier indexé dans deux collections rendrait deux entrées
      // identiques : deux lignes dans le panneau, et deux crans de navigation
      // pour le même film.
      final siblings = parseSharedSiblings(
        <String, Object?>{
          'folder': '/storage/emulated/0/Films',
          'self': _mediaUri(12),
          'files': <Object?>[
            _row('ep02.mkv', _mediaUri(12)),
            _row('ep02.mkv', _mediaUri(12)),
            _row('ep03.mkv', _mediaUri(13)),
          ],
        },
        openedPath: _opened,
        openedName: 'ep02.mkv',
      );

      expect(siblings.files.length, 2);
    });
  });

  group('Dégradation : le fichier demandé se lit toujours', () {
    test('sans réponse du tout, il reste le fichier ouvert', () {
      // Permission de lecture des médias refusée, ou canal absent : la
      // plateforme ne rend rien. Ouvrir le fichier doit quand même marcher.
      final siblings = parseSharedSiblings(
        null,
        openedPath: _opened,
        openedName: 'ep02.mkv',
      );

      expect(siblings.folder, isNull);
      expect(siblings.files.length, 1);
      expect(siblings.files.single.path, _opened);
      expect(siblings.files.single.type, MediaType.video);
    });

    test('un fichier hors MediaStore est seul mais lisible', () {
      final siblings = parseSharedSiblings(
        <String, Object?>{
          'folder': null,
          'self': null,
          'files': <Object?>[],
        },
        openedPath: _opened,
        openedName: 'ep02.mkv',
      );

      expect(siblings.folder, isNull);
      expect(siblings.files.single.path, _opened);
      expect(siblings.files.single.type, MediaType.video);
    });

    test('un dossier listé sans la ligne du fichier ouvert le garde quand même',
        () {
      // Le fichier vient d'une messagerie mais son dossier a pu être deviné :
      // c'est tout de même de lui que part « suivant / précédent ».
      final siblings = parseSharedSiblings(
        <String, Object?>{
          'folder': '/storage/emulated/0/Films',
          'self': null,
          'files': <Object?>[
            _row('ep01.mkv', _mediaUri(11)),
            _row('ep03.mkv', _mediaUri(13)),
          ],
        },
        openedPath: _opened,
        openedName: 'ep02.mkv',
      );

      expect(siblings.files.length, 3);
      expect(siblings.files.map((f) => f.path), contains(_opened));
    });

    test('une réponse incompréhensible ne fait pas échouer l ouverture', () {
      for (final reply in <Object?>[
        'rien du tout',
        42,
        <String, Object?>{'files': 'pas une liste'},
        <String, Object?>{
          'files': <Object?>[1, null, 'x', <String, Object?>{}],
        },
      ]) {
        final siblings = parseSharedSiblings(
          reply,
          openedPath: _opened,
          openedName: 'ep02.mkv',
        );
        expect(siblings.files.single.path, _opened, reason: 'réponse : $reply');
      }
    });

    test('un nom ou un chemin vide est ignoré, pas fatal', () {
      final siblings = parseSharedSiblings(
        <String, Object?>{
          'folder': '/storage/emulated/0/Films',
          'self': _mediaUri(12),
          'files': <Object?>[
            _row('', _mediaUri(10)),
            _row('ep02.mkv', ''),
            _row('ep03.mkv', _mediaUri(13)),
          ],
        },
        openedPath: _opened,
        openedName: 'ep02.mkv',
      );

      // ep03 listé, ep02 rattrapé parce que sa ligne était inutilisable.
      expect(
        siblings.files.map((f) => f.path),
        containsAll(<String>[_mediaUri(13), _opened]),
      );
      expect(siblings.files.length, 2);
    });
  });

  group('Copie faite par la plateforme', () {
    const copy =
        '/data/user/0/dev.omnia.mobile/cache/opened_media/1738_Le_Voyage.avi';

    test('les voisins de l original remplacent le dossier de cache', () {
      // Le dossier de la copie ne contient que des copies : ce sont les voisins
      // de l'original qu'il faut, et le nom réel que le panneau doit afficher.
      final siblings = parseSharedSiblings(
        <String, Object?>{
          'folder': '/storage/emulated/0/Download',
          'self': '/storage/emulated/0/Download/Le Voyage.avi',
          'files': <Object?>[
            _row('Le Voyage.avi', '/storage/emulated/0/Download/Le Voyage.avi'),
            _row('Le Retour.avi', '/storage/emulated/0/Download/Le Retour.avi'),
          ],
        },
        openedPath: copy,
        openedName: 'Le Voyage.avi',
      );

      expect(siblings.folder, '/storage/emulated/0/Download');
      expect(siblings.files.length, 2);
      expect(siblings.files.first.path, copy);
      expect(siblings.files.first.name, 'Le Voyage.avi');
    });
  });
}
