import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Une combinaison de touches : une touche et ses modificateurs, ou un
/// caractère (pour `+`, `-`, `=`, dont la place change selon la disposition
/// du clavier).
@immutable
class KeyCombo {
  const KeyCombo(
    int this.keyId, {
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  }) : character = null;

  const KeyCombo.character(String this.character)
      : keyId = null,
        control = false,
        shift = false,
        alt = false,
        meta = false;

  /// Identifiant de [LogicalKeyboardKey], `null` pour une combinaison par
  /// caractère.
  final int? keyId;
  final String? character;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;

  LogicalKeyboardKey? get key => keyId == null ? null : LogicalKeyboardKey(keyId!);

  bool get isCharacter => character != null;

  /// Vrai si la touche pressée correspond.
  ///
  /// Les modificateurs doivent être exactement ceux de la combinaison :
  /// `Ctrl+O` ne se déclenche pas sur `Ctrl+Maj+O`. Une combinaison par
  /// caractère accepte `Maj` (souvent nécessaire pour taper `+`), jamais
  /// `Ctrl`, `Alt` ou `Méta`.
  bool matches({
    required LogicalKeyboardKey key,
    String? character,
    required bool control,
    required bool shift,
    required bool alt,
    required bool meta,
  }) {
    final ch = this.character;
    if (ch != null) return character == ch && !control && !alt && !meta;
    return key.keyId == keyId &&
        control == this.control &&
        shift == this.shift &&
        alt == this.alt &&
        meta == this.meta;
  }

  /// Touches qui ne font qu'accompagner une autre : on ne les capture pas
  /// seules dans l'éditeur de raccourcis.
  static final Set<LogicalKeyboardKey> modifierKeys = {
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.numLock,
    LogicalKeyboardKey.fn,
  };

  /// Combinaison saisie dans l'éditeur, `null` pour un modificateur seul.
  static KeyCombo? capture({
    required LogicalKeyboardKey key,
    required bool control,
    required bool shift,
    required bool alt,
    required bool meta,
  }) {
    if (modifierKeys.contains(key)) return null;
    return KeyCombo(key.keyId, control: control, shift: shift, alt: alt, meta: meta);
  }

  Map<String, Object?> toJson() => character != null
      ? {'char': character}
      : {
          'key': keyId,
          if (control) 'ctrl': true,
          if (shift) 'shift': true,
          if (alt) 'alt': true,
          if (meta) 'meta': true,
        };

  /// `null` sur une donnée illisible : un raccourci corrompu est ignoré, pas
  /// fatal.
  static KeyCombo? fromJson(Object? json) {
    if (json is! Map) return null;
    final ch = json['char'];
    if (ch is String && ch.isNotEmpty) return KeyCombo.character(ch);
    final key = json['key'];
    if (key is! int) return null;
    return KeyCombo(
      key,
      control: json['ctrl'] == true,
      shift: json['shift'] == true,
      alt: json['alt'] == true,
      meta: json['meta'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KeyCombo &&
      other.keyId == keyId &&
      other.character == character &&
      other.control == control &&
      other.shift == shift &&
      other.alt == alt &&
      other.meta == meta;

  @override
  int get hashCode => Object.hash(keyId, character, control, shift, alt, meta);

  @override
  String toString() => 'KeyCombo(${toJson()})';
}
