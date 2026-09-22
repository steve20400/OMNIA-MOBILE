import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/models/app_preferences.dart';
import 'package:omnia_mobile/l10n/app_localizations.dart';
import 'package:omnia_mobile/ui/shortcuts/default_keymap.dart';
import 'package:omnia_mobile/ui/shortcuts/key_combo.dart';
import 'package:omnia_mobile/ui/shortcuts/shortcut_labels.dart';

void main() {
  final fr = lookupAppLocalizations(const Locale('fr'));
  final en = lookupAppLocalizations(const Locale('en'));

  group('comboLabel', () {
    test('modificateurs dans la langue de l’interface', () {
      final combo = KeyCombo(LogicalKeyboardKey.keyO.keyId, control: true, shift: true);
      expect(comboLabel(combo, fr), 'Ctrl+Maj+O');
      expect(comboLabel(combo, en), 'Ctrl+Shift+O');
    });

    test('touches nommées', () {
      expect(comboLabel(KeyCombo(LogicalKeyboardKey.space.keyId), fr), 'Espace');
      expect(comboLabel(KeyCombo(LogicalKeyboardKey.space.keyId), en), 'Space');
      expect(comboLabel(KeyCombo(LogicalKeyboardKey.escape.keyId), fr), 'Échap');
      expect(comboLabel(KeyCombo(LogicalKeyboardKey.escape.keyId), en), 'Esc');
      expect(comboLabel(KeyCombo(LogicalKeyboardKey.pageDown.keyId), en), 'PgDn');
    });

    test('flèches en symboles, identiques dans toutes les langues', () {
      final left = KeyCombo(LogicalKeyboardKey.arrowLeft.keyId, shift: true);
      expect(comboLabel(left, fr), 'Maj+←');
      expect(comboLabel(left, en), 'Shift+←');
    });

    test('pavé numérique', () {
      expect(comboLabel(KeyCombo(LogicalKeyboardKey.numpadAdd.keyId), fr), 'Pavé +');
      expect(comboLabel(KeyCombo(LogicalKeyboardKey.numpadAdd.keyId), en), 'Num +');
    });

    test('lettres en capitales, touches de fonction, caractères', () {
      expect(comboLabel(KeyCombo(LogicalKeyboardKey.keyS.keyId), fr), 'S');
      expect(comboLabel(KeyCombo(LogicalKeyboardKey.f1.keyId), fr), 'F1');
      expect(comboLabel(const KeyCombo.character('+'), fr), '+');
      expect(comboLabel(KeyCombo(LogicalKeyboardKey.digit0.keyId, control: true), en), 'Ctrl+0');
    });
  });

  group('actionLabel', () {
    test('chaque action a un libellé, dans les deux langues', () {
      for (final action in ShortcutAction.values) {
        expect(actionLabel(action, fr, AppPreferences.defaults), isNotEmpty, reason: action.name);
        expect(actionLabel(action, en, AppPreferences.defaults), isNotEmpty, reason: action.name);
      }
    });

    test('le libellé d’avance suit le pas choisi', () {
      const prefs = AppPreferences(seekStepSeconds: 10);
      expect(actionLabel(ShortcutAction.seekForward, fr, prefs), contains('10'));
      expect(actionLabel(ShortcutAction.seekBackwardLong, en, prefs), contains('60'));
    });

    test('deux actions différentes n’ont jamais le même libellé', () {
      final labels = ShortcutAction.values
          .map((a) => actionLabel(a, fr, AppPreferences.defaults))
          .toList();
      expect(labels.toSet().length, labels.length);
    });
  });

  test('les groupes couvrent chaque action une seule fois', () {
    final grouped = [for (final g in ShortcutGroup.values) ...g.actions];
    expect(grouped.toSet().length, grouped.length, reason: 'aucun doublon');
    expect(grouped.toSet(), ShortcutAction.values.toSet(),
        reason: 'une action absente des groupes serait introuvable dans l’éditeur');
  });
}
