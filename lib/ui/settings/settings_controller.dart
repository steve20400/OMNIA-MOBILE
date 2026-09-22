import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sections de l'écran Paramètres (§10 du cahier des charges).
enum SettingsSection {
  general,
  playback,
  subtitles,
  audio,
  documents,
  shortcuts,
  screenshots,
  history,
}

/// État d'affichage de l'écran Paramètres : ouvert ou non, et sur quelle
/// section. Purement visuel.
class SettingsUiState {
  const SettingsUiState({this.visible = false, this.section = SettingsSection.general});

  final bool visible;
  final SettingsSection section;

  SettingsUiState copyWith({bool? visible, SettingsSection? section}) => SettingsUiState(
        visible: visible ?? this.visible,
        section: section ?? this.section,
      );
}

final settingsUiProvider =
    NotifierProvider<SettingsUiController, SettingsUiState>(SettingsUiController.new);

class SettingsUiController extends Notifier<SettingsUiState> {
  @override
  SettingsUiState build() => const SettingsUiState();

  /// Ouvre l'écran, sur [section] si elle est précisée, sinon sur la dernière
  /// section consultée.
  void show([SettingsSection? section]) =>
      state = state.copyWith(visible: true, section: section);

  void hide() => state = state.copyWith(visible: false);

  void toggle() => state = state.copyWith(visible: !state.visible);

  void select(SettingsSection section) => state = state.copyWith(section: section);
}
