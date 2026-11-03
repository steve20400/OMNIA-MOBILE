import 'package:flutter/material.dart';

import '../../core/services/mobile_window_service.dart';
import '../../l10n/app_localizations.dart';

/// Demande l'autorisation d'afficher le mini-lecteur au-dessus des autres
/// applications.
///
/// Android ne laisse aucune application se l'accorder : seul l'utilisateur
/// peut la donner, depuis une page des réglages du système. Tout ce qu'OMNIA
/// peut faire, c'est expliquer à quoi elle sert et ouvrir cette page
/// directement — plutôt que de laisser chercher dans les réglages, ce qui
/// revenait à ne rien demander du tout.
///
/// Rend vrai si l'utilisateur a accepté d'aller la donner.
Future<bool> askOverlayPermission(
  BuildContext context,
  MobileWindowService window,
) async {
  final l10n = AppLocalizations.of(context);
  final accepte = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.overlayPermissionTitle),
      content: Text(l10n.overlayPermissionBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.overlayPermissionLater),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.overlayPermissionAllow),
        ),
      ],
    ),
  );
  if (accepte != true) return false;
  return window.requestOverlayPermission();
}
