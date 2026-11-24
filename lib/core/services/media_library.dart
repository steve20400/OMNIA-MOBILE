import 'dart:collection';

import 'package:flutter/services.dart';

import '../controllers/media_router.dart';
import '../models/media_type.dart';

/// Un fichier du téléphone, tel que l'accueil le présente.
class LibraryFile {
  const LibraryFile({
    required this.path,
    required this.name,
    this.size,
    this.added,
    this.modified,
  });

  final String path;
  final String name;

  /// Taille en octets, quand elle est connue.
  final int? size;

  /// Arrivée du fichier sur le téléphone.
  final DateTime? added;
  final DateTime? modified;

  MediaType get type => MediaRouter.typeForPath(path);
}

/// Ce que le téléphone contient : les fichiers récemment ajoutés, et la
/// vignette de chacun.
///
/// L'accueil n'en lit que des données ; ouvrir un fichier passe toujours par
/// le bus de commandes.
abstract interface class MediaLibrary {
  /// Les fichiers qu'OMNIA sait lire, du plus récemment ajouté au plus ancien.
  Future<List<LibraryFile>> recentlyAdded({int limit = 60});

  /// La vignette de [path], en JPEG, ou `null` s'il n'y en a pas.
  Future<Uint8List?> thumbnail(String path, MediaType type, {int size = 320});

  /// La vignette de [path] si elle est déjà en mémoire, tout de suite ;
  /// `null` sinon.
  ///
  /// Une case qui revient à l'écran l'affiche dès sa première image : en
  /// passant par [thumbnail], même servie depuis le cache, elle restait une
  /// trame sur l'icône d'attente — le clignotement de la rangée de l'accueil.
  Uint8List? cachedThumbnail(String path, {int size = 320});
}

/// Aucune bibliothèque : hors d'Android, et dans les tests.
class NoMediaLibrary implements MediaLibrary {
  const NoMediaLibrary();

  @override
  Future<List<LibraryFile>> recentlyAdded({int limit = 60}) async => const [];

  @override
  Future<Uint8List?> thumbnail(String path, MediaType type, {int size = 320}) async =>
      null;

  @override
  Uint8List? cachedThumbnail(String path, {int size = 320}) => null;
}

/// La bibliothèque d'Android, interrogée par le canal de la plateforme.
class AndroidMediaLibrary implements MediaLibrary {
  AndroidMediaLibrary({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('dev.omnia.mobile/intent');

  final MethodChannel _channel;

  /// Vignettes déjà rendues, les plus récentes gardées.
  ///
  /// Défiler l'accueil redemande sans cesse les mêmes : sans ce cache, chaque
  /// retour sur une ligne relancerait le décodage d'une image vidéo.
  final LinkedHashMap<String, Uint8List?> _thumbnails = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _pending = {};
  static const int _thumbnailCache = 160;

  @override
  Future<List<LibraryFile>> recentlyAdded({int limit = 60}) async {
    final Object? reply;
    try {
      // Plus de lignes que demandé : une bonne part n'est pas lisible par
      // OMNIA, et le filtre se fait ici, sur le nom.
      reply = await _channel
          .invokeMethod<Object?>('recentlyAdded', {'limit': limit * 5});
    } on Object {
      return const [];
    }
    if (reply is! List) return const [];
    final files = <LibraryFile>[];
    for (final row in reply) {
      if (row is! Map) continue;
      final path = row['path'];
      if (path is! String || path.isEmpty) continue;
      // Les fichiers cachés — vignettes du système, états de messagerie,
      // corbeilles d'applications — n'ont rien à faire à l'accueil.
      if (path.contains('/.')) continue;
      final file = LibraryFile(
        path: path,
        name: row['name'] is String ? row['name'] as String : path.split('/').last,
        size: (row['size'] as num?)?.toInt(),
        added: _date(row['added']),
        modified: _date(row['modified']),
      );
      if (file.type == MediaType.unknown) continue;
      files.add(file);
      if (files.length >= limit) break;
    }
    return files;
  }

  static DateTime? _date(Object? millis) =>
      millis is num ? DateTime.fromMillisecondsSinceEpoch(millis.toInt()) : null;

  @override
  Future<Uint8List?> thumbnail(String path, MediaType type, {int size = 320}) {
    final kind = switch (type) {
      MediaType.video => 'video',
      MediaType.audio => 'audio',
      MediaType.image => 'image',
      MediaType.pdf => 'pdf',
      _ => null,
    };
    if (kind == null) return Future.value();
    final key = '$size|$path';
    if (_thumbnails.containsKey(key)) {
      // Remis en tête : c'est le plus récemment servi.
      final bytes = _thumbnails.remove(key);
      _thumbnails[key] = bytes;
      return Future.value(bytes);
    }
    return _pending[key] ??= _render(key, path, kind, size);
  }

  @override
  Uint8List? cachedThumbnail(String path, {int size = 320}) {
    final key = '$size|$path';
    if (!_thumbnails.containsKey(key)) return null;
    // Remis en tête, comme par [thumbnail].
    final bytes = _thumbnails.remove(key);
    _thumbnails[key] = bytes;
    return bytes;
  }

  Future<Uint8List?> _render(String key, String path, String kind, int size) async {
    Uint8List? bytes;
    try {
      bytes = await _channel.invokeMethod<Uint8List>(
        'thumbnail',
        {'path': path, 'kind': kind, 'size': size},
      );
    } on Object {
      bytes = null;
    }
    // Le futur retiré est celui-ci même, en train de s'achever : il n'y a
    // rien à en attendre.
    _pending.remove(key)?.ignore();
    _thumbnails[key] = bytes;
    while (_thumbnails.length > _thumbnailCache) {
      _thumbnails.remove(_thumbnails.keys.first);
    }
    return bytes;
  }
}
