import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'default_keymap.dart';
import 'key_combo.dart';
import 'keymap.dart';

/// Table des raccourcis de l'utilisateur.
///
/// Configuration de la couche clavier de cette machine : elle ne transite pas
/// par le bus de commandes (une télécommande n'a pas à réaffecter les touches
/// du poste), elle est enregistrée directement dans les préférences.
final keymapProvider = NotifierProvider<KeymapNotifier, Keymap>(KeymapNotifier.new);

class KeymapNotifier extends Notifier<Keymap> {
  @override
  Keymap build() => Keymap.fromOverrides(ref.watch(settingsStoreProvider).keymapOverrides);

  void bind(ShortcutAction action, KeyCombo combo) => _set(state.bind(action, combo));

  void reset(ShortcutAction action) => _set(state.reset(action));

  void resetAll() => _set(state.resetAll());

  void _set(Keymap next) {
    state = next;
    unawaited(ref.read(settingsStoreProvider).setKeymapOverrides(next.toOverrides()));
  }
}
