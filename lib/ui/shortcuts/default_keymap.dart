import 'package:flutter/services.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/app_preferences.dart';
import '../../core/models/document_layout.dart';
import 'key_combo.dart';

/// Actions clavier qui ne sont pas des commandes du lecteur (dialogues, aide,
/// champs de saisie des documents).
enum UiAction {
  openFileDialog,
  openFolderDialog,
  toggleHelp,
  toggleSettings,
  goToPage,
  findInDocument,
}

/// Toutes les actions qu'un raccourci peut déclencher (§8 du cahier des
/// charges), dans l'ordre où l'éditeur de raccourcis les présente.
///
/// [repeats] : l'action se répète quand on maintient la touche (avancer,
/// volume, pages). Les bascules (lecture, plein écran…) ne se répètent pas :
/// maintenir `Espace` ne doit pas faire clignoter la pause.
enum ShortcutAction {
  togglePlay,
  seekBackward(repeats: true),
  seekForward(repeats: true),
  seekBackwardMedium(repeats: true),
  seekForwardMedium(repeats: true),
  seekBackwardLong(repeats: true),
  seekForwardLong(repeats: true),
  volumeUp(repeats: true),
  volumeDown(repeats: true),
  toggleMute,
  speedUp(repeats: true),
  speedDown(repeats: true),
  speedReset,
  nextFile,
  previousFile,
  cycleEndMode,
  toggleSidePanel,
  screenshot,
  recordClip,
  abLoop,
  toggleSubtitles,
  toggleFullscreen,
  exitFullscreen,
  alwaysOnTop,
  miniPlayer,
  previousPage(repeats: true),
  nextPage(repeats: true),
  goToPage,
  find,
  fitZoom,
  rotateDocument,
  readingDark,
  openFile,
  openFolder,
  settings,
  help;

  const ShortcutAction({this.repeats = false});

  final bool repeats;

  static ShortcutAction? fromName(String name) {
    for (final action in values) {
      if (action.name == name) return action;
    }
    return null;
  }
}

/// Raccourcis par défaut.
///
/// `+`, `-` et `=` sont reconnus par le caractère produit : ils ne sont pas au
/// même endroit en AZERTY et en QWERTY.
final Map<ShortcutAction, List<KeyCombo>> defaultBindings = Map.unmodifiable({
  ShortcutAction.togglePlay: [
    KeyCombo(LogicalKeyboardKey.space.keyId),
    KeyCombo(LogicalKeyboardKey.mediaPlayPause.keyId),
  ],
  ShortcutAction.seekBackward: [KeyCombo(LogicalKeyboardKey.arrowLeft.keyId)],
  ShortcutAction.seekForward: [KeyCombo(LogicalKeyboardKey.arrowRight.keyId)],
  ShortcutAction.seekBackwardMedium: [KeyCombo(LogicalKeyboardKey.arrowLeft.keyId, shift: true)],
  ShortcutAction.seekForwardMedium: [KeyCombo(LogicalKeyboardKey.arrowRight.keyId, shift: true)],
  ShortcutAction.seekBackwardLong: [KeyCombo(LogicalKeyboardKey.arrowLeft.keyId, control: true)],
  ShortcutAction.seekForwardLong: [KeyCombo(LogicalKeyboardKey.arrowRight.keyId, control: true)],
  ShortcutAction.volumeUp: [KeyCombo(LogicalKeyboardKey.arrowUp.keyId)],
  ShortcutAction.volumeDown: [KeyCombo(LogicalKeyboardKey.arrowDown.keyId)],
  ShortcutAction.toggleMute: [KeyCombo(LogicalKeyboardKey.keyM.keyId)],
  ShortcutAction.speedUp: [
    KeyCombo(LogicalKeyboardKey.numpadAdd.keyId),
    const KeyCombo.character('+'),
  ],
  ShortcutAction.speedDown: [
    KeyCombo(LogicalKeyboardKey.numpadSubtract.keyId),
    const KeyCombo.character('-'),
  ],
  ShortcutAction.speedReset: [const KeyCombo.character('=')],
  ShortcutAction.nextFile: [KeyCombo(LogicalKeyboardKey.keyN.keyId)],
  ShortcutAction.previousFile: [KeyCombo(LogicalKeyboardKey.keyP.keyId)],
  ShortcutAction.cycleEndMode: [KeyCombo(LogicalKeyboardKey.keyL.keyId)],
  ShortcutAction.toggleSidePanel: [KeyCombo(LogicalKeyboardKey.tab.keyId)],
  ShortcutAction.screenshot: [KeyCombo(LogicalKeyboardKey.keyS.keyId)],
  // Maj+R : le raccourci d'enregistrement de VLC.
  ShortcutAction.recordClip: [KeyCombo(LogicalKeyboardKey.keyR.keyId, shift: true)],
  ShortcutAction.abLoop: [KeyCombo(LogicalKeyboardKey.keyA.keyId)],
  ShortcutAction.toggleSubtitles: [KeyCombo(LogicalKeyboardKey.keyV.keyId)],
  ShortcutAction.toggleFullscreen: [KeyCombo(LogicalKeyboardKey.keyF.keyId)],
  ShortcutAction.exitFullscreen: [KeyCombo(LogicalKeyboardKey.escape.keyId)],
  ShortcutAction.alwaysOnTop: [KeyCombo(LogicalKeyboardKey.keyT.keyId)],
  ShortcutAction.miniPlayer: [KeyCombo(LogicalKeyboardKey.keyM.keyId, control: true, shift: true)],
  ShortcutAction.previousPage: [KeyCombo(LogicalKeyboardKey.pageUp.keyId)],
  ShortcutAction.nextPage: [KeyCombo(LogicalKeyboardKey.pageDown.keyId)],
  ShortcutAction.goToPage: [KeyCombo(LogicalKeyboardKey.keyG.keyId, control: true)],
  ShortcutAction.find: [KeyCombo(LogicalKeyboardKey.keyF.keyId, control: true)],
  ShortcutAction.fitZoom: [KeyCombo(LogicalKeyboardKey.digit0.keyId, control: true)],
  ShortcutAction.rotateDocument: [KeyCombo(LogicalKeyboardKey.keyR.keyId, control: true)],
  ShortcutAction.readingDark: [KeyCombo(LogicalKeyboardKey.keyD.keyId, control: true)],
  ShortcutAction.openFile: [KeyCombo(LogicalKeyboardKey.keyO.keyId, control: true)],
  ShortcutAction.openFolder: [KeyCombo(LogicalKeyboardKey.keyO.keyId, control: true, shift: true)],
  // Ctrl+, : la convention des applications de bureau pour les réglages.
  ShortcutAction.settings: [KeyCombo(LogicalKeyboardKey.comma.keyId, control: true)],
  ShortcutAction.help: [KeyCombo(LogicalKeyboardKey.f1.keyId)],
});

/// Ce que déclenche une action : une [PlayerCommand] publiée sur le bus, ou
/// une [UiAction] traitée par l'interface.
///
/// Le pas d'avance / recul de `←` / `→` vient des préférences ; les pas moyen
/// (30 s) et long (60 s) sont fixes, comme dans le cahier des charges.
Object resolveShortcut(ShortcutAction action, AppPreferences prefs) {
  final step = prefs.seekStepSeconds.toDouble();
  return switch (action) {
    ShortcutAction.togglePlay => const TogglePlay(),
    ShortcutAction.seekBackward => SeekRelative(-step),
    ShortcutAction.seekForward => SeekRelative(step),
    ShortcutAction.seekBackwardMedium => const SeekRelative(-30),
    ShortcutAction.seekForwardMedium => const SeekRelative(30),
    ShortcutAction.seekBackwardLong => const SeekRelative(-60),
    ShortcutAction.seekForwardLong => const SeekRelative(60),
    ShortcutAction.volumeUp => const VolumeRelative(5),
    ShortcutAction.volumeDown => const VolumeRelative(-5),
    ShortcutAction.toggleMute => const ToggleMute(),
    ShortcutAction.speedUp => const SpeedRelative(0.25),
    ShortcutAction.speedDown => const SpeedRelative(-0.25),
    ShortcutAction.speedReset => const SetSpeed(1.0),
    ShortcutAction.nextFile => const NextFile(),
    ShortcutAction.previousFile => const PreviousFile(),
    ShortcutAction.cycleEndMode => const CycleLoopMode(),
    ShortcutAction.toggleSidePanel => const ToggleSidePanel(),
    ShortcutAction.screenshot => const TakeScreenshot(),
    ShortcutAction.recordClip => const ToggleRecording(),
    ShortcutAction.abLoop => const CycleAbLoop(),
    ShortcutAction.toggleSubtitles => const ToggleSubtitles(),
    ShortcutAction.toggleFullscreen => const ToggleFullscreen(),
    ShortcutAction.exitFullscreen => const ExitFullscreen(),
    ShortcutAction.alwaysOnTop => const ToggleAlwaysOnTop(),
    ShortcutAction.miniPlayer => const ToggleMiniPlayer(),
    ShortcutAction.previousPage => const PreviousPage(),
    ShortcutAction.nextPage => const NextPage(),
    ShortcutAction.goToPage => UiAction.goToPage,
    ShortcutAction.find => UiAction.findInDocument,
    ShortcutAction.fitZoom => const FitZoom(FitMode.width),
    ShortcutAction.rotateDocument => const RotateDocument(),
    ShortcutAction.readingDark => const ToggleReadingDarkMode(),
    ShortcutAction.openFile => UiAction.openFileDialog,
    ShortcutAction.openFolder => UiAction.openFolderDialog,
    ShortcutAction.settings => UiAction.toggleSettings,
    ShortcutAction.help => UiAction.toggleHelp,
  };
}
