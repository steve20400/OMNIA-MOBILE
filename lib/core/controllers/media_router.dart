import 'package:path/path.dart' as p;

import '../models/media_type.dart';
import 'media_controller.dart';

/// Associe une extension de fichier à un [MediaType], et un type à son
/// [MediaController].
///
/// Les listes d'extensions sont la source de vérité pour tout OMNIA : dialogue
/// d'ouverture, scan de dossier, associations MIME du fichier `.desktop`.
class MediaRouter {
  MediaRouter(Iterable<MediaController> controllers)
      : _controllers = List.unmodifiable(controllers);

  final List<MediaController> _controllers;

  // Vidéo et audio passent par mpv (FFmpeg), qui lit bien plus de formats
  // que le seul MP4 : la liste couvre ce que l'on croise réellement, du
  // fichier de téléphone au disque Blu-ray. Pas de guillemets dans ces
  // commentaires : tool/make_installer_assoc.py lit les chaînes de la liste.
  static const Set<String> videoExtensions = {
    // Conteneurs courants.
    'mp4', 'm4v', 'mkv', 'mk3d', 'webm', 'avi', 'mov', 'qt', 'wmv', 'asf',
    'flv', 'f4v', 'ogv', 'ogm', '3gp', '3g2', 'divx', 'xvid',
    // MPEG : DVD, caméscopes, enregistrements et diffusion TV.
    'mpg', 'mpeg', 'mpe', 'mpv', 'm1v', 'm2v', 'm2p', 'vob', 'evo',
    'ts', 'm2ts', 'mts', 'm2t', 'tp', 'trp', 'tod', 'wtv',
    // Flux bruts et formats professionnels.
    'h264', 'h265', 'hevc', '264', '265', 'ivf', 'y4m', 'dv', 'mxf', 'nut',
    'gxf',
    // Anciens formats.
    'rm', 'rmvb', 'amv', 'bik',
  };

  static const Set<String> audioExtensions = {
    // Formats courants.
    'mp3', 'aac', 'm4a', 'm4b', 'm4r', 'flac', 'wav', 'wave', 'ogg', 'oga',
    'opus', 'wma', 'weba',
    // Sans perte et haute résolution, DSD compris.
    'aiff', 'aif', 'aifc', 'ape', 'wv', 'tta', 'tak', 'w64', 'dsf', 'dff',
    'caf', 'shn', 'ofr',
    // Cinéma, Blu-ray et diffusion.
    'ac3', 'eac3', 'ec3', 'dts', 'dtshd', 'mlp', 'thd', 'truehd', 'mka',
    'mp2', 'mp1', 'mpa', 'adts',
    // Voix et anciens formats.
    'amr', 'awb', 'spx', 'gsm', 'au', 'snd', 'voc', 'ra', 'mpc', 'oma',
  };

  static const Set<String> pdfExtensions = {'pdf'};

  static const Set<String> docExtensions = {
    'docx', 'doc', 'odt', 'rtf', 'dotx', 'docm', 'dotm', 'fodt', 'ott',
    'pptx', 'ppt', 'ppsx', 'odp', 'fodp', 'otp',
  };

  static const Set<String> textExtensions = {
    'txt', 'md', 'markdown', 'log', 'json', 'yaml', 'yml', 'xml', 'csv',
    'tsv', 'ini', 'conf', 'cfg', 'properties', 'toml', 'srt', 'vtt', 'sub',
    'ass', 'lrc', 'sql', 'sh', 'bash', 'bat', 'cmd', 'ps1', 'html', 'htm',
    'css', 'js', 'dart', 'py', 'c', 'cpp', 'h', 'hpp', 'java', 'rs', 'go',
    'aux', 'tex', 'latex', 'bib', 'cls', 'sty', 'toc', 'lof', 'lot', 'bbl',
    'blg', 'idx', 'ilg', 'ind', 'out', 'diff', 'patch', 'env', 'reg', 'inf',
    'lock',
  };

  static const Set<String> imageExtensions = {
    'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'ico', 'svg', 'avif',
    'tif', 'tiff', 'heic', 'heif', 'jfif',
  };

  /// Toutes les extensions lisibles, sans le point.
  static Set<String> get allExtensions => {
        ...videoExtensions,
        ...audioExtensions,
        ...pdfExtensions,
        ...docExtensions,
        ...textExtensions,
        ...imageExtensions,
      };

  /// Type déduit de l'extension (insensible à la casse).
  static MediaType typeForPath(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    if (ext.isEmpty) return MediaType.unknown;
    if (videoExtensions.contains(ext)) return MediaType.video;
    if (audioExtensions.contains(ext)) return MediaType.audio;
    if (pdfExtensions.contains(ext)) return MediaType.pdf;
    if (docExtensions.contains(ext)) return MediaType.doc;
    if (imageExtensions.contains(ext)) return MediaType.image;
    if (textExtensions.contains(ext)) return MediaType.text;
    return MediaType.unknown;
  }

  static bool isSupported(String path) => typeForPath(path).isSupported;

  /// Contrôleur capable d'ouvrir [type], ou `null`.
  MediaController? controllerFor(MediaType type) {
    for (final c in _controllers) {
      if (c.supportedTypes.contains(type)) return c;
    }
    return null;
  }

  /// Contrôleur pour un chemin donné, ou `null` si non pris en charge.
  MediaController? controllerForPath(String path) =>
      controllerFor(typeForPath(path));

  Iterable<MediaController> get controllers => _controllers;
}
