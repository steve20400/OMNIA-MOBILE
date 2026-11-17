import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/commands/player_command.dart';
import '../../core/controllers/media_router.dart';
import '../../core/models/media_type.dart';
import '../../core/providers.dart';
import '../home_navigation.dart';
import '../theme/omnia_theme.dart';

enum _FileAction { open, folder, details }

/// Taille lisible, à la française : « 1,4 Go », « 820 Ko ».
String formatFileSize(int bytes) {
  const units = ['o', 'Ko', 'Mo', 'Go', 'To'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = unit == 0 || value >= 100
      ? value.round().toString()
      : value.toStringAsFixed(1).replaceAll('.', ',');
  return '$text ${units[unit]}';
}

/// Date lisible : « 7/11/2026 à 10:04 ».
String formatFileDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.day}/${date.month}/${date.year} à ${two(date.hour)}:${two(date.minute)}';
}

String _typeLabel(MediaType type) => switch (type) {
      MediaType.video => 'Vidéo',
      MediaType.audio => 'Audio',
      MediaType.image => 'Image',
      MediaType.pdf => 'Document PDF',
      MediaType.doc => 'Document',
      MediaType.text => 'Texte',
      MediaType.unknown => 'Fichier',
    };

/// Le menu à trois points d'un fichier : l'ouvrir, aller à son emplacement,
/// voir ses détails.
///
/// Le chemin n'est plus écrit sous chaque fichier de l'accueil : il prenait
/// une ligne entière pour une information qu'on ne cherche que rarement. Il
/// est ici, à la demande.
class FileActionsButton extends ConsumerWidget {
  const FileActionsButton({
    super.key,
    required this.path,
    this.size,
    this.added,
    this.modified,
    this.enabled = true,
  });

  final String path;
  final int? size;
  final DateTime? added;
  final DateTime? modified;

  /// Faux pour un fichier disparu : seuls ses détails restent consultables.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;

    PopupMenuItem<_FileAction> item(_FileAction action, IconData icon, String label,
        {bool active = true}) {
      return PopupMenuItem<_FileAction>(
        value: action,
        enabled: active,
        child: Row(
          children: [
            Icon(icon, size: 20, color: active ? colors.projector : colors.dust),
            const SizedBox(width: OmniaMetrics.space3),
            Text(label, style: type.body.copyWith(color: active ? colors.screen : colors.dust)),
          ],
        ),
      );
    }

    return PopupMenuButton<_FileAction>(
      tooltip: 'Options du fichier',
      icon: Icon(Icons.more_vert_rounded, size: 20, color: colors.dust),
      color: colors.curtain,
      shape: RoundedRectangleBorder(
        borderRadius: OmniaMetrics.controlRadius,
        side: BorderSide(color: colors.seam),
      ),
      onSelected: (action) {
        switch (action) {
          case _FileAction.open:
            ref.dispatch(OpenFile(path));
          case _FileAction.folder:
            revealFolder(ref, p.dirname(path));
          case _FileAction.details:
            showFileDetails(
              context,
              ref,
              path: path,
              size: size,
              added: added,
              modified: modified,
            );
        }
      },
      itemBuilder: (_) => [
        item(_FileAction.open, Icons.play_arrow_rounded, 'Ouvrir', active: enabled),
        item(
          _FileAction.folder,
          Icons.folder_open_rounded,
          "Ouvrir l'emplacement",
          active: enabled,
        ),
        item(_FileAction.details, Icons.info_outline_rounded, 'Détails'),
      ],
    );
  }
}

/// Les détails d'un fichier : où il est, ce qu'il pèse, quand il est arrivé.
Future<void> showFileDetails(
  BuildContext context,
  WidgetRef ref, {
  required String path,
  int? size,
  DateTime? added,
  DateTime? modified,
}) {
  final colors = context.colors;
  final type = context.type;
  final file = File(path);
  final exists = file.existsSync();
  FileStat? stat;
  if (exists) {
    try {
      stat = file.statSync();
    } on FileSystemException {
      // Lecture refusée : les détails connus suffisent.
    }
  }
  final knownSize = size ?? stat?.size;
  final knownModified = modified ?? stat?.modified;

  Widget row(String label, String value, {bool selectable = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: OmniaMetrics.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: type.caption.copyWith(color: colors.dust, letterSpacing: 1.1)),
          const SizedBox(height: 2),
          selectable
              ? SelectableText(value, style: type.body.copyWith(color: colors.screen))
              : Text(value, style: type.body.copyWith(color: colors.screen)),
        ],
      ),
    );
  }

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: colors.curtain,
      title: Text(p.basename(path), style: type.bodyStrong.copyWith(color: colors.screen)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('Emplacement', p.dirname(path), selectable: true),
            row('Type', _typeLabel(MediaRouter.typeForPath(path))),
            if (knownSize != null) row('Taille', formatFileSize(knownSize)),
            if (added != null) row('Ajouté le', formatFileDate(added)),
            if (knownModified != null) row('Modifié le', formatFileDate(knownModified)),
            if (!exists)
              Text(
                "Ce fichier n'est plus à cet endroit : il a été déplacé ou supprimé.",
                style: type.secondary.copyWith(color: colors.alert),
              ),
          ],
        ),
      ),
      actions: [
        if (exists)
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              revealFolder(ref, p.dirname(path));
            },
            child: Text("Ouvrir l'emplacement", style: TextStyle(color: colors.projector)),
          ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text('Fermer', style: TextStyle(color: colors.screen)),
        ),
      ],
    ),
  );
}
