import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// État d'interface propre aux documents : barre de recherche, champ « aller
/// à la page », mode édition pour les fichiers texte/code modifiables.
class DocumentUiState {
  const DocumentUiState({
    this.findVisible = false,
    this.goToPageRequest = 0,
    this.isEditing = false,
    this.saveRequest = 0,
    this.hasUnsavedChanges = false,
    this.documentFocused = false,
    this.draftPath,
    this.draftText,
  });

  /// La barre de recherche (`Ctrl+F`) est affichée.
  final bool findVisible;

  /// Compteur incrémenté à chaque `Ctrl+G` : la barre de document réagit au
  /// changement en donnant le focus au champ de page.
  final int goToPageRequest;

  /// Vrai si l'utilisateur est en mode édition (lecture / écriture).
  final bool isEditing;

  /// Compteur incrémenté pour déclencher l'enregistrement (`Ctrl+S` ou bouton).
  final int saveRequest;

  /// Vrai si le texte a été modifié mais pas encore enregistré sur le disque.
  final bool hasUnsavedChanges;

  /// Vrai si l'utilisateur a cliqué sur la zone du document (pour orienter PgUp/PgDn).
  final bool documentFocused;

  /// Chemin absolu du document en cours de modification.
  final String? draftPath;

  /// Dernier texte saisi en cours d'édition.
  final String? draftText;

  DocumentUiState copyWith({
    bool? findVisible,
    int? goToPageRequest,
    bool? isEditing,
    int? saveRequest,
    bool? hasUnsavedChanges,
    bool? documentFocused,
    String? draftPath,
    String? draftText,
  }) =>
      DocumentUiState(
        findVisible: findVisible ?? this.findVisible,
        goToPageRequest: goToPageRequest ?? this.goToPageRequest,
        isEditing: isEditing ?? this.isEditing,
        saveRequest: saveRequest ?? this.saveRequest,
        hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
        documentFocused: documentFocused ?? this.documentFocused,
        draftPath: draftPath ?? this.draftPath,
        draftText: draftText ?? this.draftText,
      );
}

final documentUiProvider =
    NotifierProvider<DocumentUiController, DocumentUiState>(DocumentUiController.new);

class DocumentUiController extends Notifier<DocumentUiState> {
  @override
  DocumentUiState build() => const DocumentUiState();

  void showFind() => state = state.copyWith(findVisible: true);
  void hideFind() => state = state.copyWith(findVisible: false);
  void toggleFind() => state = state.copyWith(findVisible: !state.findVisible);
  void requestGoToPage() =>
      state = state.copyWith(goToPageRequest: state.goToPageRequest + 1);

  void toggleEdit() => state = state.copyWith(isEditing: !state.isEditing);
  void setEditing(bool value) => state = state.copyWith(isEditing: value);
  void requestSave() => state = state.copyWith(saveRequest: state.saveRequest + 1);
  void setUnsavedChanges(bool value) =>
      state = state.copyWith(hasUnsavedChanges: value);

  void setDocumentFocused(bool value) {
    if (state.documentFocused != value) {
      state = state.copyWith(documentFocused: value);
    }
  }

  /// Enregistre les modifications textuelles en mémoire.
  void setDraft({required String path, required String text}) {
    state = state.copyWith(
      hasUnsavedChanges: true,
      draftPath: path,
      draftText: text,
    );
  }

  /// Efface le brouillon en cours après enregistrement ou rejet.
  void clearDraft() {
    state = DocumentUiState(
      findVisible: state.findVisible,
      goToPageRequest: state.goToPageRequest,
      isEditing: state.isEditing,
      saveRequest: state.saveRequest,
      hasUnsavedChanges: false,
      documentFocused: false,
      draftPath: null,
      draftText: null,
    );
  }

  /// Sauvegarde immédiate et synchrone du brouillon sur le disque.
  bool saveDraftSync() {
    final path = state.draftPath;
    final text = state.draftText;
    if (path == null || text == null) return false;
    try {
      File(path).writeAsStringSync(text, flush: true);
      clearDraft();
      return true;
    } catch (_) {
      return false;
    }
  }
}
