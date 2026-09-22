import 'dart:io';
import 'dart:ui' show Size;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Filtres prédéfinis applicables lors de la retouche d'image.
enum ImageFilterPreset {
  none,
  grayscale,
  sepia,
  invert,
}

/// Paramètres de modification et de redimensionnement d'une image.
class ImageEditParams {
  const ImageEditParams({
    this.targetWidth,
    this.targetHeight,
    this.brightness = 0.0, // -1.0 à 1.0 (0.0 = neutre)
    this.contrast = 1.0, // 0.0 à 2.0 (1.0 = neutre)
    this.saturation = 1.0, // 0.0 à 2.0 (1.0 = neutre, 0.0 = N&B)
    this.rotationAngle = 0, // 0, 90, 180, 270 degrés
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.preset = ImageFilterPreset.none,
  });

  final int? targetWidth;
  final int? targetHeight;
  final double brightness;
  final double contrast;
  final double saturation;
  final int rotationAngle;
  final bool flipHorizontal;
  final bool flipVertical;
  final ImageFilterPreset preset;

  bool get hasModifications =>
      targetWidth != null ||
      targetHeight != null ||
      brightness != 0.0 ||
      contrast != 1.0 ||
      saturation != 1.0 ||
      rotationAngle != 0 ||
      flipHorizontal ||
      flipVertical ||
      preset != ImageFilterPreset.none;

  ImageEditParams copyWith({
    int? targetWidth,
    int? targetHeight,
    double? brightness,
    double? contrast,
    double? saturation,
    int? rotationAngle,
    bool? flipHorizontal,
    bool? flipVertical,
    ImageFilterPreset? preset,
  }) {
    return ImageEditParams(
      targetWidth: targetWidth ?? this.targetWidth,
      targetHeight: targetHeight ?? this.targetHeight,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      rotationAngle: rotationAngle ?? this.rotationAngle,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      preset: preset ?? this.preset,
    );
  }
}

class _ImageJob {
  const _ImageJob({
    required this.sourcePath,
    required this.destPath,
    required this.params,
    required this.jpegQuality,
  });

  final String sourcePath;
  final String destPath;
  final ImageEditParams params;
  final int jpegQuality;
}

/// Service de traitement d'images haute performance (pur Dart, thread isolé).
class ImageProcessorService {
  /// Génère un chemin cible unique pour la copie sans écraser le fichier original ni une copie existante.
  static String generateCopyPath(String sourcePath, {String suffix = '_edit'}) {
    final dir = p.dirname(sourcePath);
    final ext = p.extension(sourcePath);
    final baseName = p.basenameWithoutExtension(sourcePath);

    var candidate = p.join(dir, '$baseName$suffix$ext');
    var index = 1;
    while (File(candidate).existsSync()) {
      candidate = p.join(dir, '$baseName${suffix}_$index$ext');
      index++;
    }
    return candidate;
  }

  /// Récupère les dimensions réelles en pixels d'une image sans blocage.
  static Future<Size?> getImageDimensions(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        return Size(decoded.width.toDouble(), decoded.height.toDouble());
      }
    } catch (_) {}
    return null;
  }

  /// Applique les transformations en arrière-plan et enregistre une NOUVELLE COPIE.
  /// Ne modifie JAMAIS l'image originale. Retourne le chemin du nouveau fichier créé.
  static Future<String> processAndSaveCopy({
    required String sourcePath,
    required ImageEditParams params,
    String suffix = '_edit',
    int jpegQuality = 92,
  }) async {
    final destPath = generateCopyPath(sourcePath, suffix: suffix);

    await compute(
      _processImageFile,
      _ImageJob(
        sourcePath: sourcePath,
        destPath: destPath,
        params: params,
        jpegQuality: jpegQuality,
      ),
    );

    return destPath;
  }
}

void _processImageFile(_ImageJob job) {
  final bytes = File(job.sourcePath).readAsBytesSync();
  var image = img.decodeImage(bytes);
  if (image == null) {
    throw Exception('Format d’image non supporté ou fichier illisible.');
  }

  final params = job.params;

  // 1. Redimensionnement
  if (params.targetWidth != null || params.targetHeight != null) {
    image = img.copyResize(
      image,
      width: params.targetWidth,
      height: params.targetHeight,
      maintainAspect: true,
      interpolation: img.Interpolation.linear,
    );
  }

  // 2. Rotation
  if (params.rotationAngle != 0) {
    image = img.copyRotate(image, angle: params.rotationAngle);
  }

  // 3. Miroir
  if (params.flipHorizontal) {
    image = img.copyFlip(image, direction: img.FlipDirection.horizontal);
  }
  if (params.flipVertical) {
    image = img.copyFlip(image, direction: img.FlipDirection.vertical);
  }

  // 4. Filtre preset
  switch (params.preset) {
    case ImageFilterPreset.grayscale:
      image = img.grayscale(image);
    case ImageFilterPreset.sepia:
      image = img.sepia(image);
    case ImageFilterPreset.invert:
      image = img.invert(image);
    case ImageFilterPreset.none:
      break;
  }

  // 5. Ajustements de couleur
  if (params.brightness != 0.0 || params.contrast != 1.0 || params.saturation != 1.0) {
    final b = 1.0 + params.brightness;
    image = img.adjustColor(
      image,
      brightness: b,
      contrast: params.contrast,
      saturation: params.saturation,
    );
  }

  // 6. Encodage selon extension du fichier cible
  final ext = p.extension(job.destPath).toLowerCase();
  final List<int> encoded;
  if (ext == '.png') {
    encoded = img.encodePng(image);
  } else {
    encoded = img.encodeJpg(image, quality: job.jpegQuality);
  }

  File(job.destPath).writeAsBytesSync(encoded);
}
