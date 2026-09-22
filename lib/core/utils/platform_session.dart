import 'dart:io';

/// Vrai si l'application tourne dans une session Wayland.
///
/// Wayland interdit à une fenêtre de connaître ou d'imposer sa position :
/// `getBounds()` y renvoie toujours (0, 0) et `setPosition()` ne fait rien.
/// Mémoriser puis restaurer une position dans ces conditions revient à figer
/// la fenêtre en haut à gauche à chaque démarrage. OMNIA n'y mémorise donc
/// que la taille.
bool get isWaylandSession {
  if (!Platform.isLinux) return false;
  final env = Platform.environment;
  return env['XDG_SESSION_TYPE']?.toLowerCase() == 'wayland' ||
      (env['WAYLAND_DISPLAY']?.isNotEmpty ?? false);
}

/// Vrai si la fenêtre est entièrement dessinée par OMNIA, bordures comprises.
///
/// Sous Linux, masquer la barre de titre retire toutes les décorations GTK,
/// y compris les bords de redimensionnement : l'application doit les fournir
/// elle-même. Windows et macOS gardent leur cadre natif.
bool get needsCustomResizeEdges => Platform.isLinux;
