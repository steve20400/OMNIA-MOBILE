import 'dart:typed_data';

/// Un contrôleur capable de fournir l'image affichée (capture d'écran).
///
/// Séparé de [MediaController] : seuls les contrôleurs vidéo ont une image à
/// capturer, et le service de lecture n'a pas à savoir lequel.
abstract interface class FrameCapturer {
  /// Image courante en PNG, ou `null` s'il n'y a rien à capturer.
  Future<Uint8List?> captureFrame();
}
