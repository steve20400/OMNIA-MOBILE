import 'package:flutter/services.dart';

import 'default_keymap.dart';
import 'key_combo.dart';

/// Table des raccourcis : pour chaque action, ses combinaisons.
///
/// Immuable : chaque modification rend une nouvelle table. Seuls les écarts
/// aux valeurs par défaut sont enregistrés ([toOverrides]) : une mise à jour
/// d'OMNIA qui ajoute un raccourci le propose aussitôt, sans écraser ceux que
/// l'utilisateur a changés.
class Keymap {
  const Keymap._(this._bindings);

  factory Keymap.defaults() => Keymap._(defaultBindings);

  /// Relit les écarts enregistrés. Une action inconnue ou une combinaison
  /// illisible est ignorée ; les conflits éventuels sont résolus en faveur de
  /// l'action personnalisée.
  factory Keymap.fromOverrides(Map<String, Object?> overrides) {
    var keymap = Keymap.defaults();
    overrides.forEach((name, raw) {
      final action = ShortcutAction.fromName(name);
      if (action == null || raw is! List) return;
      final combos = raw.map(KeyCombo.fromJson).whereType<KeyCombo>().toList();
      keymap = keymap._withBindings(action, combos);
    });
    return keymap;
  }

  final Map<ShortcutAction, List<KeyCombo>> _bindings;

  List<KeyCombo> combosFor(ShortcutAction action) => _bindings[action] ?? const [];

  bool isDefault(ShortcutAction action) =>
      _sameCombos(combosFor(action), defaultBindings[action] ?? const []);

  bool get isAllDefault => ShortcutAction.values.every(isDefault);

  /// Action déclenchée par une touche, ou `null`.
  ///
  /// Deux passes : d'abord les combinaisons par touche, ensuite celles par
  /// caractère. Sans cela, un raccourci personnalisé comme `Maj+=` (qui
  /// produit « + » en QWERTY) serait masqué par « vitesse + ».
  ShortcutAction? match({
    required LogicalKeyboardKey key,
    String? character,
    required bool control,
    required bool shift,
    required bool alt,
    required bool meta,
    bool isRepeat = false,
  }) {
    for (final byCharacter in [false, true]) {
      for (final action in ShortcutAction.values) {
        if (isRepeat && !action.repeats) continue;
        for (final combo in combosFor(action)) {
          if (combo.isCharacter != byCharacter) continue;
          if (combo.matches(
            key: key,
            character: character,
            control: control,
            shift: shift,
            alt: alt,
            meta: meta,
          )) {
            return action;
          }
        }
      }
    }
    return null;
  }

  /// Autre action qui utilise déjà [combo], ou `null`.
  ShortcutAction? conflictFor(KeyCombo combo, {ShortcutAction? except}) {
    for (final action in ShortcutAction.values) {
      if (action == except) continue;
      if (combosFor(action).contains(combo)) return action;
    }
    return null;
  }

  /// Attribue [combo] à [action], qui n'a plus que ce raccourci. Si une autre
  /// action l'utilisait, elle le perd : une touche ne déclenche qu'une chose.
  Keymap bind(ShortcutAction action, KeyCombo combo) => _withBindings(action, [combo]);

  /// Rend à [action] ses raccourcis par défaut, retirés au passage des
  /// actions qui les avaient repris.
  Keymap reset(ShortcutAction action) =>
      _withBindings(action, defaultBindings[action] ?? const []);

  Keymap resetAll() => Keymap.defaults();

  Keymap _withBindings(ShortcutAction action, List<KeyCombo> combos) {
    final next = <ShortcutAction, List<KeyCombo>>{};
    for (final entry in _bindings.entries) {
      next[entry.key] = entry.key == action
          ? List.unmodifiable(combos)
          : List.unmodifiable(entry.value.where((c) => !combos.contains(c)));
    }
    next.putIfAbsent(action, () => List.unmodifiable(combos));
    return Keymap._(Map.unmodifiable(next));
  }

  /// Combinaisons affectées à plusieurs actions (ne devrait jamais arriver
  /// avec [bind] ; sert de garde-fou sur des données relues).
  Map<KeyCombo, List<ShortcutAction>> conflicts() {
    final owners = <KeyCombo, List<ShortcutAction>>{};
    for (final action in ShortcutAction.values) {
      for (final combo in combosFor(action)) {
        owners.putIfAbsent(combo, () => []).add(action);
      }
    }
    owners.removeWhere((_, actions) => actions.length < 2);
    return owners;
  }

  /// Écarts aux valeurs par défaut, sérialisables.
  Map<String, Object?> toOverrides() => {
        for (final action in ShortcutAction.values)
          if (!isDefault(action))
            action.name: combosFor(action).map((c) => c.toJson()).toList(),
      };

  static bool _sameCombos(List<KeyCombo> a, List<KeyCombo> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
