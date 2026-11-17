import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../file_dialogs.dart';
import '../orientation.dart';
import '../projection.dart';
import '../theme/omnia_theme.dart';

enum _HomeMenuAction { openFile, openFolder, rotate, refreshProjection }

/// Le menu à trois points, en haut à droite.
///
/// Toujours au même endroit, qu'on soit à l'accueil, dans un document ou
/// dans une vidéo : ouvrir un fichier, ouvrir un dossier, tourner l'écran.
/// Les deux boutons d'ouverture qui encombraient l'accueil y sont rangés.
///
/// Relié à un PC avec un média ouvert, il offre aussi « Actualiser la
/// projection » : après avoir changé de fichier, un toucher l'envoie au PC,
/// sans rescanner le code ni rouvrir OMNIA Connect.
class HomeMenuButton extends ConsumerWidget {
  const HomeMenuButton({super.key, this.color});

  /// Couleur de l'icône ; celle du texte par défaut.
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;

    PopupMenuItem<_HomeMenuAction> item(
      _HomeMenuAction action,
      IconData icon,
      String label,
    ) {
      return PopupMenuItem<_HomeMenuAction>(
        value: action,
        child: Row(
          children: [
            Icon(icon, size: 20, color: colors.projector),
            const SizedBox(width: OmniaMetrics.space3),
            // Souple : un menu ne dépasse pas 280 points de large, et avec
            // une grande taille de texte dans les réglages du téléphone, le
            // libellé passe à la ligne au lieu de déborder.
            Flexible(
              child: Text(label, style: type.body.copyWith(color: colors.screen)),
            ),
          ],
        ),
      );
    }

    return PopupMenuButton<_HomeMenuAction>(
      key: const ValueKey('home-menu'),
      tooltip: "Plus d'options",
      icon: Icon(Icons.more_vert_rounded, color: color ?? colors.screen),
      color: colors.curtain,
      shape: RoundedRectangleBorder(
        borderRadius: OmniaMetrics.controlRadius,
        side: BorderSide(color: colors.seam),
      ),
      onSelected: (action) {
        switch (action) {
          case _HomeMenuAction.openFile:
            unawaited(pickAndOpenFile(ref));
          case _HomeMenuAction.openFolder:
            unawaited(pickAndOpenFolder(ref));
          case _HomeMenuAction.rotate:
            unawaited(toggleScreenOrientation(context));
          case _HomeMenuAction.refreshProjection:
            unawaited(_refreshProjection(context, ref));
        }
      },
      itemBuilder: (_) => [
        // En tête quand il est là : c'est le geste qu'on vient faire après
        // avoir changé de fichier pendant une projection.
        if (canProjectCurrentMedia(ref))
          item(
            _HomeMenuAction.refreshProjection,
            Icons.cast_rounded,
            'Actualiser la projection',
          ),
        item(_HomeMenuAction.openFile, Icons.file_open_rounded, 'Ouvrir un fichier'),
        item(_HomeMenuAction.openFolder, Icons.folder_open_rounded, 'Ouvrir un dossier'),
        item(_HomeMenuAction.rotate, Icons.screen_rotation_rounded, "Rotation de l'écran"),
      ],
    );
  }

  /// Envoie au PC le média ouvert, et dit en bas de l'écran ce qu'il en est.
  Future<void> _refreshProjection(BuildContext context, WidgetRef ref) async {
    final file = ref.read(playbackStateProvider).file;
    if (file == null) return;
    // Pris avant l'attente : le contexte du bouton ne se lit plus ensuite.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final message = await projectCurrentMedia(ref, file.path);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
