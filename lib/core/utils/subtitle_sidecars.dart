import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/track_info.dart';

/// Extensions de sous-titres reconnues, sans le point.
const Set<String> subtitleExtensions = {'srt', 'ass', 'ssa', 'vtt', 'sub'};

/// Fichiers de sous-titres voisins d'un média : même dossier, même nom de
/// base, éventuellement suivi d'un code de langue (`film.fr.srt`).
///
/// Retourne des [TrackInfo] externes dont l'identifiant est le chemin, la
/// langue le suffixe s'il existe. Le tri met les fichiers sans suffixe en
/// premier, puis par nom.
List<TrackInfo> findSubtitleSidecars(String mediaPath, {List<String>? candidates}) {
  final folder = p.dirname(mediaPath);
  final base = p.basenameWithoutExtension(mediaPath).toLowerCase();

  final names = candidates ??
      (() {
        try {
          return Directory(folder)
              .listSync(followLinks: false)
              .whereType<File>()
              .map((f) => p.basename(f.path))
              .toList();
        } on FileSystemException {
          return const <String>[];
        }
      })();

  final found = <TrackInfo>[];
  for (final name in names) {
    final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
    if (!subtitleExtensions.contains(ext)) continue;
    final stem = p.basenameWithoutExtension(name);
    final lowerStem = stem.toLowerCase();
    if (lowerStem == base) {
      found.add(TrackInfo(id: p.join(folder, name), title: name, external: true));
    } else if (lowerStem.startsWith('$base.')) {
      final suffix = stem.substring(base.length + 1);
      // Un suffixe de langue est court (« fr », « eng », « fr-FR ») ; un titre
      // plus long serait un autre fichier qui commence pareil.
      if (suffix.length <= 6) {
        found.add(
          TrackInfo(id: p.join(folder, name), title: name, language: suffix, external: true),
        );
      }
    }
  }

  found.sort((a, b) {
    final la = a.language == null ? 0 : 1;
    final lb = b.language == null ? 0 : 1;
    if (la != lb) return la - lb;
    return a.id.toLowerCase().compareTo(b.id.toLowerCase());
  });
  return found;
}
