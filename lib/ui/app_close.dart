import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/models/app_preferences.dart';
import '../core/providers.dart';
import '../core/services/window_service.dart';
import 'document_ui_controller.dart';
import 'widgets/unsaved_changes_dialog.dart';

/// Clé globale pour accéder au navigateur racine.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Vérifie et résout les modifications non enregistrées selon la politique configurée
/// (`ask`, `save`, `discard`).
///
/// Retourne `true` si la fermeture de l'application est autorisée à se poursuivre,
/// ou `false` si l'utilisateur a annulé.
Future<bool> handleUnsavedChangesGuard(dynamic ref, [BuildContext? context]) async {
  final docUi = ref.read(documentUiProvider) as DocumentUiState;
  if (!docUi.isEditing || !docUi.hasUnsavedChanges) {
    return true;
  }

  final prefs = ref.read(preferencesProvider) as AppPreferences;
  final policy = prefs.unsavedChangesPolicy;

  if (policy == UnsavedChangesPolicy.ask) {
    final ctx = context ?? rootNavigatorKey.currentContext;
    if (ctx != null) {
      final fileName = docUi.draftPath != null
          ? p.basename(docUi.draftPath!)
          : 'document';
      final choice = await UnsavedChangesDialog.show(ctx, fileName: fileName);
      if (choice == null || choice == UnsavedChangesAction.cancel) {
        return false; // L'utilisateur annule la fermeture
      }
      if (choice == UnsavedChangesAction.save) {
        (ref.read(documentUiProvider.notifier) as DocumentUiController).saveDraftSync();
      } else {
        (ref.read(documentUiProvider.notifier) as DocumentUiController).clearDraft();
      }
      return true;
    } else {
      (ref.read(documentUiProvider.notifier) as DocumentUiController).saveDraftSync();
      return true;
    }
  } else if (policy == UnsavedChangesPolicy.save) {
    (ref.read(documentUiProvider.notifier) as DocumentUiController).saveDraftSync();
    return true;
  } else if (policy == UnsavedChangesPolicy.discard) {
    (ref.read(documentUiProvider.notifier) as DocumentUiController).clearDraft();
    return true;
  }

  return true;
}

/// Ferme proprement et immédiatement l'application en gérant les modifications non enregistrées :
/// 1. Si un document texte/code est en cours d'édition avec des modifications non sauvegardées :
///    applique la politique de fermeture (Demander confirmation, Enregistrer automatiquement ou Ignorer).
/// 2. Coupe instantanément tout flux audio et vidéo mpv en cours
///    (pour éliminer le son résiduel qui traîne après la fermeture).
/// 3. Ferme la fenêtre native de l'application.
///
/// Retourne `true` si l'application s'est fermée, ou `false` si l'utilisateur a annulé.
Future<bool> closeApplication(dynamic ref, [BuildContext? context]) async {
  final canClose = await handleUnsavedChangesGuard(ref, context);
  if (!canClose) {
    return false;
  }

  try {
    await (ref.read(avControllerProvider) as dynamic).player.stop();
  } catch (_) {}
  try {
    await (ref.read(playbackServiceProvider) as dynamic).stopImmediately();
  } catch (_) {}
  await (ref.read(windowServiceProvider) as WindowService).close();
  return true;
}
