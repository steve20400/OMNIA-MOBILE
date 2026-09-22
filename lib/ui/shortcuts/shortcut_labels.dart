import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_preferences.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import 'default_keymap.dart';
import 'key_combo.dart';
import 'keymap_provider.dart';

/// Nom lisible d'une combinaison, dans la langue de l'interface :
/// `Ctrl+Maj+O` en français, `Ctrl+Shift+O` en anglais.
String comboLabel(KeyCombo combo, AppLocalizations l10n) {
  final parts = <String>[
    if (combo.control) l10n.keyCtrl,
    if (combo.alt) l10n.keyAlt,
    if (combo.shift) l10n.keyShift,
    if (combo.meta) _metaLabel,
    combo.isCharacter ? combo.character! : keyName(combo.key!, l10n),
  ];
  return parts.join('+');
}

/// La touche « système » s'appelle différemment selon la plateforme.
String get _metaLabel {
  if (Platform.isMacOS) return '⌘';
  if (Platform.isWindows) return 'Win';
  return 'Super';
}

/// Nom d'une touche seule.
String keyName(LogicalKeyboardKey key, AppLocalizations l10n) {
  final named = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.space: l10n.keySpace,
    LogicalKeyboardKey.escape: l10n.keyEscape,
    LogicalKeyboardKey.tab: l10n.keyTab,
    LogicalKeyboardKey.enter: l10n.keyEnter,
    LogicalKeyboardKey.numpadEnter: l10n.keyEnter,
    LogicalKeyboardKey.backspace: l10n.keyBackspace,
    LogicalKeyboardKey.delete: l10n.keyDelete,
    LogicalKeyboardKey.insert: l10n.keyInsert,
    LogicalKeyboardKey.home: l10n.keyHome,
    LogicalKeyboardKey.end: l10n.keyEnd,
    LogicalKeyboardKey.pageUp: l10n.keyPageUp,
    LogicalKeyboardKey.pageDown: l10n.keyPageDown,
    LogicalKeyboardKey.arrowLeft: '←',
    LogicalKeyboardKey.arrowRight: '→',
    LogicalKeyboardKey.arrowUp: '↑',
    LogicalKeyboardKey.arrowDown: '↓',
    LogicalKeyboardKey.mediaPlayPause: l10n.keyMediaPlayPause,
    LogicalKeyboardKey.numpadAdd: l10n.keyNumpad('+'),
    LogicalKeyboardKey.numpadSubtract: l10n.keyNumpad('−'),
    LogicalKeyboardKey.numpadMultiply: l10n.keyNumpad('×'),
    LogicalKeyboardKey.numpadDivide: l10n.keyNumpad('÷'),
  };
  final known = named[key];
  if (known != null) return known;

  final label = key.keyLabel;
  if (label.isEmpty) return key.debugName ?? '?';
  // Les lettres s'affichent en capitales, comme sur le clavier.
  return label.length == 1 ? label.toUpperCase() : label;
}

/// Libellé d'une action, tel que l'éditeur et l'aide le présentent.
String actionLabel(ShortcutAction action, AppLocalizations l10n, AppPreferences prefs) {
  return switch (action) {
    ShortcutAction.togglePlay => l10n.helpPlayPause,
    ShortcutAction.seekBackward => l10n.scSeekBackward(prefs.seekStepSeconds),
    ShortcutAction.seekForward => l10n.scSeekForward(prefs.seekStepSeconds),
    ShortcutAction.seekBackwardMedium => l10n.scSeekBackward(30),
    ShortcutAction.seekForwardMedium => l10n.scSeekForward(30),
    ShortcutAction.seekBackwardLong => l10n.scSeekBackward(60),
    ShortcutAction.seekForwardLong => l10n.scSeekForward(60),
    ShortcutAction.volumeUp => l10n.scVolumeUp,
    ShortcutAction.volumeDown => l10n.scVolumeDown,
    ShortcutAction.toggleMute => l10n.scToggleMute,
    ShortcutAction.speedUp => l10n.scSpeedUp,
    ShortcutAction.speedDown => l10n.scSpeedDown,
    ShortcutAction.speedReset => l10n.resetSpeed,
    ShortcutAction.nextFile => l10n.nextFile,
    ShortcutAction.previousFile => l10n.previousFile,
    ShortcutAction.cycleEndMode => l10n.endModeLabel,
    ShortcutAction.toggleSidePanel => l10n.helpPanelToggle,
    ShortcutAction.screenshot => l10n.screenshot,
    ShortcutAction.recordClip => l10n.recordClip,
    ShortcutAction.abLoop => l10n.abLoop,
    ShortcutAction.toggleSubtitles => l10n.scToggleSubtitles,
    ShortcutAction.toggleFullscreen => l10n.fullscreen,
    ShortcutAction.exitFullscreen => l10n.exitFullscreen,
    ShortcutAction.alwaysOnTop => l10n.alwaysOnTop,
    ShortcutAction.miniPlayer => l10n.miniPlayer,
    ShortcutAction.previousPage => l10n.docPreviousPage,
    ShortcutAction.nextPage => l10n.docNextPage,
    ShortcutAction.goToPage => l10n.docGoToPage,
    ShortcutAction.find => l10n.docFind,
    ShortcutAction.fitZoom => l10n.docFitWidth,
    ShortcutAction.rotateDocument => l10n.docRotate,
    ShortcutAction.readingDark => l10n.docReadingDark,
    ShortcutAction.openFile => l10n.openFile,
    ShortcutAction.openFolder => l10n.openFolder,
    ShortcutAction.settings => l10n.settingsTitle,
    ShortcutAction.help => l10n.helpTitle,
  };
}

/// Groupes d'actions, pour l'éditeur de raccourcis et l'aide `F1`.
enum ShortcutGroup {
  playback([
    ShortcutAction.togglePlay,
    ShortcutAction.seekBackward,
    ShortcutAction.seekForward,
    ShortcutAction.seekBackwardMedium,
    ShortcutAction.seekForwardMedium,
    ShortcutAction.seekBackwardLong,
    ShortcutAction.seekForwardLong,
    ShortcutAction.volumeUp,
    ShortcutAction.volumeDown,
    ShortcutAction.toggleMute,
    ShortcutAction.speedUp,
    ShortcutAction.speedDown,
    ShortcutAction.speedReset,
    ShortcutAction.abLoop,
    ShortcutAction.toggleSubtitles,
    ShortcutAction.screenshot,
    ShortcutAction.recordClip,
  ]),
  navigation([
    ShortcutAction.nextFile,
    ShortcutAction.previousFile,
    ShortcutAction.cycleEndMode,
    ShortcutAction.toggleSidePanel,
  ]),
  documents([
    ShortcutAction.previousPage,
    ShortcutAction.nextPage,
    ShortcutAction.goToPage,
    ShortcutAction.find,
    ShortcutAction.fitZoom,
    ShortcutAction.rotateDocument,
    ShortcutAction.readingDark,
  ]),
  window([
    ShortcutAction.toggleFullscreen,
    ShortcutAction.exitFullscreen,
    ShortcutAction.alwaysOnTop,
    ShortcutAction.miniPlayer,
    ShortcutAction.openFile,
    ShortcutAction.openFolder,
    ShortcutAction.settings,
    ShortcutAction.help,
  ]);

  const ShortcutGroup(this.actions);
  final List<ShortcutAction> actions;

  String label(AppLocalizations l10n) => switch (this) {
        ShortcutGroup.playback => l10n.helpGroupPlayback,
        ShortcutGroup.navigation => l10n.helpGroupNavigation,
        ShortcutGroup.documents => l10n.helpGroupDocuments,
        ShortcutGroup.window => l10n.helpGroupWindow,
      };
}

extension ShortcutHintX on WidgetRef {
  /// Premier raccourci de [action] dans la table de l'utilisateur, ou `null`
  /// s'il n'en a plus. À afficher dans les infobulles et les menus : il suit
  /// les réaffectations et la langue.
  String? shortcutOf(ShortcutAction action, AppLocalizations l10n) {
    final combos = watch(keymapProvider).combosFor(action);
    return combos.isEmpty ? null : comboLabel(combos.first, l10n);
  }

  /// Infobulle « libellé · raccourci », ou le libellé seul sans raccourci.
  String tooltipWith(String label, ShortcutAction action, AppLocalizations l10n) {
    final shortcut = shortcutOf(action, l10n);
    return shortcut == null ? label : '$label  ·  $shortcut';
  }

  /// Préférences courantes (libellés dépendant du pas d'avance, par exemple).
  AppPreferences get preferences => watch(preferencesProvider);
}
