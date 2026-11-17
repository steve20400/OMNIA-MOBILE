import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controllers/media_router.dart';
import '../../core/models/media_type.dart';
import '../../core/providers.dart';
import '../theme/omnia_theme.dart';

/// Icône d'un type de média, posée là où il n'y a pas d'aperçu.
IconData iconForMediaType(MediaType type) => switch (type) {
      MediaType.video => Icons.movie_rounded,
      MediaType.audio => Icons.music_note_rounded,
      MediaType.image => Icons.image_rounded,
      MediaType.pdf || MediaType.doc || MediaType.text => Icons.description_rounded,
      MediaType.unknown => Icons.insert_drive_file_rounded,
    };

/// Aperçu d'un fichier : une image de la vidéo, la pochette d'une musique, la
/// photo elle-même, la première page d'un PDF.
///
/// L'accueil n'affichait que des icônes, toutes pareilles : on n'y
/// reconnaissait rien. Tant que l'aperçu se prépare, ou quand il n'y en a pas,
/// c'est l'icône du type qui tient la place — la mise en page ne saute pas.
class MediaThumbnail extends ConsumerStatefulWidget {
  const MediaThumbnail({
    super.key,
    required this.path,
    this.size = 320,
    this.iconSize = 26,
  });

  final String path;

  /// Côté le plus long demandé au système, en pixels.
  final int size;

  final double iconSize;

  @override
  ConsumerState<MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends ConsumerState<MediaThumbnail> {
  late Future<Uint8List?> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _load();
  }

  @override
  void didUpdateWidget(MediaThumbnail old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.size != widget.size) _bytes = _load();
  }

  Future<Uint8List?> _load() => ref.read(mediaLibraryProvider).thumbnail(
        widget.path,
        MediaRouter.typeForPath(widget.path),
        size: widget.size,
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = MediaRouter.typeForPath(widget.path);
    final placeholder = ColoredBox(
      color: colors.curtain,
      child: Center(
        child: Icon(
          iconForMediaType(type),
          size: widget.iconSize,
          color: colors.projector.withValues(alpha: 0.75),
        ),
      ),
    );

    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) return placeholder;
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => placeholder,
        );
      },
    );
  }
}
