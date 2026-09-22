import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/commands/player_command_bus.dart';
import '../../core/models/document_layout.dart';
import '../../core/models/media_type.dart';
import '../../core/providers.dart';
import '../document_ui_controller.dart';
import '../file_dialogs.dart';
import '../help_overlay_controller.dart';
import '../player_focus.dart';
import '../settings/settings_controller.dart';
import 'default_keymap.dart';
import 'keymap_provider.dart';

/// Traduit un événement clavier en commande sur le bus, d'après la table de
/// raccourcis de l'utilisateur.
///
/// Quand un champ de saisie a le focus (recherche du panneau), les raccourcis
/// se taisent : taper « pause » dans la recherche ne doit pas mettre le film en
/// pause. `Échap` fait exception — elle rend le focus au lecteur, sans quoi
/// l'utilisateur resterait piégé dans le champ, clavier inopérant.
///
/// [panelDrawerOpen] : le panneau est ouvert en tiroir par-dessus la scène.
/// `Échap` le referme alors, avant de servir à quoi que ce soit d'autre.
KeyEventResult handleShortcut(
  KeyEvent event,
  WidgetRef ref, {
  bool panelDrawerOpen = false,
}) {
  if (event is KeyUpEvent) return KeyEventResult.ignored;

  // Le panneau d'aide ouvert capte Échap et F1 pour se fermer, et rien
  // d'autre : on ne pilote pas la lecture à l'aveugle derrière un voile.
  final help = ref.read(helpVisibleProvider.notifier);
  if (ref.read(helpVisibleProvider)) {
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.f1) {
      help.hide();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  if (textFieldHasFocus()) {
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // Rendre le focus au lecteur lui-même : un simple `unfocus()` le
      // donnerait à la portée englobante, et les raccourcis resteraient muets.
      ref.read(playerFocusProvider).restore();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // Paramètres ouverts : leur feuille garde normalement le focus et gère
  // Échap elle-même. Garde-fou si le focus est resté au lecteur : on ne
  // pilote pas la lecture derrière la feuille.
  if (ref.read(settingsUiProvider).visible) {
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      ref.read(settingsUiProvider.notifier).hide();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // Tiroir posé sur la scène : `Échap` le referme d'abord — c'est le geste
  // attendu, et il passe avant le retour de plein écran.
  if (panelDrawerOpen && event.logicalKey == LogicalKeyboardKey.escape) {
    ref.dispatch(const SetSidePanelVisible(false));
    return KeyEventResult.handled;
  }

  final keyboard = HardwareKeyboard.instance;
  final action = ref.read(keymapProvider).match(
        key: event.logicalKey,
        character: event.character,
        control: keyboard.isControlPressed,
        shift: keyboard.isShiftPressed,
        alt: keyboard.isAltPressed,
        meta: keyboard.isMetaPressed,
        isRepeat: event is KeyRepeatEvent,
      );
  if (action == null) {
    // `Shift+Tab` n'est volontairement pas capturé : il reste le moyen clavier
    // d'atteindre la recherche du panneau. Le piège classique — se retrouver
    // dans un champ, tous les raccourcis muets — est levé par `Échap`.
    return KeyEventResult.ignored;
  }

  final state = ref.read(playbackStateProvider);

  // Spécialisation contextuelle selon le type de média :
  // Sur un document ou une photo, monter / descendre et gauche / droite
  // doivent piloter la navigation du document et JAMAIS le volume !
  PlayerCommand? contextualCommand;

  final isPageKey = event.logicalKey == LogicalKeyboardKey.pageUp ||
      event.logicalKey == LogicalKeyboardKey.pageDown;
  final isFileNavAction = action == ShortcutAction.nextFile ||
      action == ShortcutAction.previousFile;
  final isPageNavAction = action == ShortcutAction.nextPage ||
      action == ShortcutAction.previousPage;

  if (state.isDocument && (isPageKey || isFileNavAction || isPageNavAction)) {
    final isForward = event.logicalKey == LogicalKeyboardKey.pageDown ||
        action == ShortcutAction.nextFile ||
        action == ShortcutAction.nextPage;
    final docFocused = ref.read(documentUiProvider).documentFocused;

    if (docFocused) {
      // Document cliqué : défilement ou changement de page dans le document
      if (state.mediaType == MediaType.pdf) {
        contextualCommand = isForward ? const NextPage() : const PreviousPage();
      } else {
        final delta = isForward ? 0.15 : -0.15;
        contextualCommand = ScrollTo((state.scrollFraction + delta).clamp(0.0, 1.0));
      }
    } else {
      // Document non cliqué ou clic sur la barre latérale : fichier suivant/précédent
      final playlist = ref.read(playlistServiceProvider);
      final target = isForward
          ? playlist.nextNonLoopingPath()
          : playlist.previousNonLoopingPath();
      if (target != null) {
        contextualCommand = isForward ? const NextFile() : const PreviousFile();
      } else {
        // Repli : si aucun autre fichier n'est disponible dans cette direction, faire défiler le document
        if (state.mediaType == MediaType.pdf) {
          contextualCommand = isForward ? const NextPage() : const PreviousPage();
        } else {
          final delta = isForward ? 0.15 : -0.15;
          contextualCommand = ScrollTo((state.scrollFraction + delta).clamp(0.0, 1.0));
        }
      }
    }
  }

  if (contextualCommand == null) {
    if (state.mediaType == MediaType.pdf) {
      if (state.documentLayout == DocumentLayout.continuous) {
        contextualCommand = switch (action) {
          ShortcutAction.volumeUp => const ScrollDocument(-175.0),
          ShortcutAction.volumeDown => const ScrollDocument(175.0),
          ShortcutAction.previousPage || ShortcutAction.seekBackward => const PreviousPage(),
          ShortcutAction.nextPage || ShortcutAction.seekForward => const NextPage(),
          _ => null,
        };
      } else {
        contextualCommand = switch (action) {
          ShortcutAction.volumeUp ||
          ShortcutAction.previousPage ||
          ShortcutAction.seekBackward =>
            const PreviousPage(),
          ShortcutAction.volumeDown ||
          ShortcutAction.nextPage ||
          ShortcutAction.seekForward =>
            const NextPage(),
          _ => null,
        };
      }
    } else if (state.isDocument) {
      contextualCommand = switch (action) {
        ShortcutAction.volumeUp => ScrollTo((state.scrollFraction - 0.05).clamp(0.0, 1.0)),
        ShortcutAction.volumeDown => ScrollTo((state.scrollFraction + 0.05).clamp(0.0, 1.0)),
        ShortcutAction.previousPage => ScrollTo((state.scrollFraction - 0.2).clamp(0.0, 1.0)),
        ShortcutAction.nextPage => ScrollTo((state.scrollFraction + 0.2).clamp(0.0, 1.0)),
        _ => null,
      };
    } else if (state.mediaType == MediaType.image) {
      contextualCommand = switch (action) {
        ShortcutAction.volumeUp => const ZoomRelative(1.15),
        ShortcutAction.volumeDown => const ZoomRelative(1 / 1.15),
        ShortcutAction.seekBackward || ShortcutAction.previousPage => const PreviousFile(),
        ShortcutAction.seekForward || ShortcutAction.nextPage => const NextFile(),
        _ => null,
      };
    }
  }

  if (contextualCommand != null) {
    ref.dispatch(contextualCommand, source: CommandSource.keyboard);
    return KeyEventResult.handled;
  }

  switch (resolveShortcut(action, ref.read(preferencesProvider))) {
    case final PlayerCommand command:
      ref.dispatch(command, source: CommandSource.keyboard);
    case UiAction.openFileDialog:
      pickAndOpenFile(ref);
    case UiAction.openFolderDialog:
      pickAndOpenFolder(ref);
    case UiAction.toggleHelp:
      // Pas d'aide dans la fenêtre compacte du mini-lecteur : le panneau n'y
      // est pas monté, et l'ouvrir rendrait le clavier muet (le gestionnaire
      // se croirait derrière un voile qui n'existe pas).
      if (ref.read(playbackStateProvider).miniPlayer) return KeyEventResult.ignored;
      help.toggle();
    case UiAction.toggleSettings:
      // Pas de paramètres dans la fenêtre compacte du mini-lecteur.
      if (ref.read(playbackStateProvider).miniPlayer) return KeyEventResult.ignored;
      ref.read(settingsUiProvider.notifier).toggle();
    case UiAction.goToPage:
      if (!ref.read(playbackStateProvider).isDocument) return KeyEventResult.ignored;
      ref.read(documentUiProvider.notifier).requestGoToPage();
    case UiAction.findInDocument:
      if (!ref.read(playbackStateProvider).isDocument) return KeyEventResult.ignored;
      ref.read(documentUiProvider.notifier).showFind();
    case _:
      return KeyEventResult.ignored;
  }
  return KeyEventResult.handled;
}

/// Vrai si le focus est dans un champ de texte.
bool textFieldHasFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText ||
      context.findAncestorWidgetOfExactType<EditableText>() != null;
}
