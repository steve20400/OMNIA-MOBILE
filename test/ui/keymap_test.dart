import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/commands/player_command.dart';
import 'package:omnia_mobile/core/models/app_preferences.dart';
import 'package:omnia_mobile/ui/shortcuts/default_keymap.dart';
import 'package:omnia_mobile/ui/shortcuts/key_combo.dart';
import 'package:omnia_mobile/ui/shortcuts/keymap.dart';

/// Raccourci de test : touche + modificateurs, sans répétition.
ShortcutAction? press(
  Keymap keymap,
  LogicalKeyboardKey key, {
  String? character,
  bool control = false,
  bool shift = false,
  bool alt = false,
  bool meta = false,
  bool repeat = false,
}) =>
    keymap.match(
      key: key,
      character: character,
      control: control,
      shift: shift,
      alt: alt,
      meta: meta,
      isRepeat: repeat,
    );

void main() {
  group('Table par défaut', () {
    final keymap = Keymap.defaults();

    test('chaque action a au moins un raccourci', () {
      for (final action in ShortcutAction.values) {
        expect(keymap.combosFor(action), isNotEmpty, reason: action.name);
      }
    });

    test('aucun raccourci n’est partagé entre deux actions', () {
      expect(keymap.conflicts(), isEmpty);
    });

    test('la table du cahier des charges (§8)', () {
      expect(press(keymap, LogicalKeyboardKey.space), ShortcutAction.togglePlay);
      expect(press(keymap, LogicalKeyboardKey.arrowRight), ShortcutAction.seekForward);
      expect(press(keymap, LogicalKeyboardKey.arrowRight, shift: true),
          ShortcutAction.seekForwardMedium);
      expect(press(keymap, LogicalKeyboardKey.arrowLeft, control: true),
          ShortcutAction.seekBackwardLong);
      expect(press(keymap, LogicalKeyboardKey.arrowUp), ShortcutAction.volumeUp);
      expect(press(keymap, LogicalKeyboardKey.keyM), ShortcutAction.toggleMute);
      expect(press(keymap, LogicalKeyboardKey.keyF), ShortcutAction.toggleFullscreen);
      expect(press(keymap, LogicalKeyboardKey.escape), ShortcutAction.exitFullscreen);
      expect(press(keymap, LogicalKeyboardKey.keyN), ShortcutAction.nextFile);
      expect(press(keymap, LogicalKeyboardKey.keyS), ShortcutAction.screenshot);
      expect(press(keymap, LogicalKeyboardKey.keyA), ShortcutAction.abLoop);
      expect(press(keymap, LogicalKeyboardKey.keyV), ShortcutAction.toggleSubtitles);
      expect(press(keymap, LogicalKeyboardKey.tab), ShortcutAction.toggleSidePanel);
      expect(press(keymap, LogicalKeyboardKey.keyO, control: true), ShortcutAction.openFile);
      expect(press(keymap, LogicalKeyboardKey.keyO, control: true, shift: true),
          ShortcutAction.openFolder);
      expect(press(keymap, LogicalKeyboardKey.keyL), ShortcutAction.cycleEndMode);
      expect(press(keymap, LogicalKeyboardKey.keyT), ShortcutAction.alwaysOnTop);
      expect(press(keymap, LogicalKeyboardKey.pageDown), ShortcutAction.nextPage);
      expect(press(keymap, LogicalKeyboardKey.keyG, control: true), ShortcutAction.goToPage);
      expect(press(keymap, LogicalKeyboardKey.keyF, control: true), ShortcutAction.find);
      expect(press(keymap, LogicalKeyboardKey.digit0, control: true), ShortcutAction.fitZoom);
      expect(press(keymap, LogicalKeyboardKey.f1), ShortcutAction.help);
    });

    test('les modificateurs doivent être exacts', () {
      // Ctrl+Maj+O ouvre un dossier, pas un fichier ; Ctrl+M n'est pas « muet ».
      expect(press(keymap, LogicalKeyboardKey.keyM, control: true), isNull);
      expect(press(keymap, LogicalKeyboardKey.keyS, alt: true), isNull);
    });

    test('+, - et = reconnus au caractère, quelle que soit la touche', () {
      // En AZERTY, « + » se tape avec Maj sur la touche « = ».
      expect(press(keymap, LogicalKeyboardKey.equal, character: '+', shift: true),
          ShortcutAction.speedUp);
      expect(press(keymap, LogicalKeyboardKey.digit6, character: '-'), ShortcutAction.speedDown);
      expect(press(keymap, LogicalKeyboardKey.equal, character: '='), ShortcutAction.speedReset);
      expect(press(keymap, LogicalKeyboardKey.numpadAdd, character: '+'), ShortcutAction.speedUp);
    });

    test('un caractère avec Ctrl ne déclenche pas la vitesse', () {
      expect(press(keymap, LogicalKeyboardKey.equal, character: '=', control: true), isNull);
    });

    test('répétition : seules les actions continues se répètent', () {
      expect(press(keymap, LogicalKeyboardKey.arrowRight, repeat: true),
          ShortcutAction.seekForward);
      expect(press(keymap, LogicalKeyboardKey.arrowUp, repeat: true), ShortcutAction.volumeUp);
      expect(press(keymap, LogicalKeyboardKey.space, repeat: true), isNull,
          reason: 'maintenir Espace ne doit pas faire clignoter la pause');
      expect(press(keymap, LogicalKeyboardKey.keyF, repeat: true), isNull);
    });
  });

  group('Personnalisation', () {
    test('réaffecter une touche la retire à l’autre action', () {
      final keymap = Keymap.defaults().bind(
        ShortcutAction.screenshot,
        KeyCombo(LogicalKeyboardKey.space.keyId),
      );
      expect(press(keymap, LogicalKeyboardKey.space), ShortcutAction.screenshot);
      expect(keymap.combosFor(ShortcutAction.togglePlay),
          [KeyCombo(LogicalKeyboardKey.mediaPlayPause.keyId)]);
      expect(press(keymap, LogicalKeyboardKey.keyS), isNull, reason: 'S est libéré');
      expect(keymap.conflicts(), isEmpty);
    });

    test('conflictFor signale l’action qui utilise déjà la touche', () {
      final keymap = Keymap.defaults();
      expect(keymap.conflictFor(KeyCombo(LogicalKeyboardKey.keyN.keyId)), ShortcutAction.nextFile);
      expect(
        keymap.conflictFor(KeyCombo(LogicalKeyboardKey.keyN.keyId), except: ShortcutAction.nextFile),
        isNull,
      );
      expect(keymap.conflictFor(KeyCombo(LogicalKeyboardKey.keyK.keyId)), isNull);
    });

    test('réinitialiser une action reprend ses touches à qui les avait', () {
      var keymap = Keymap.defaults().bind(
        ShortcutAction.screenshot,
        KeyCombo(LogicalKeyboardKey.space.keyId),
      );
      keymap = keymap.reset(ShortcutAction.togglePlay);
      expect(press(keymap, LogicalKeyboardKey.space), ShortcutAction.togglePlay);
      expect(keymap.combosFor(ShortcutAction.screenshot), isEmpty);
      expect(keymap.conflicts(), isEmpty);
    });

    test('resetAll revient aux valeurs par défaut', () {
      final keymap = Keymap.defaults()
          .bind(ShortcutAction.nextFile, KeyCombo(LogicalKeyboardKey.keyK.keyId))
          .resetAll();
      expect(keymap.isAllDefault, isTrue);
      expect(keymap.toOverrides(), isEmpty);
    });

    test('un raccourci personnalisé par touche passe avant un caractère', () {
      // Maj+= produit « + » en QWERTY : l'utilisateur l'a donné à la capture.
      final keymap = Keymap.defaults().bind(
        ShortcutAction.screenshot,
        KeyCombo(LogicalKeyboardKey.equal.keyId, shift: true),
      );
      expect(press(keymap, LogicalKeyboardKey.equal, character: '+', shift: true),
          ShortcutAction.screenshot);
    });
  });

  group('Persistance', () {
    test('seuls les écarts aux défauts sont enregistrés, et relus à l’identique', () {
      final keymap = Keymap.defaults()
          .bind(ShortcutAction.nextFile, KeyCombo(LogicalKeyboardKey.keyK.keyId, control: true))
          .bind(ShortcutAction.speedReset, const KeyCombo.character('*'));
      final overrides = keymap.toOverrides();

      expect(overrides.keys, unorderedEquals(['nextFile', 'speedReset']));
      final restored = Keymap.fromOverrides(overrides);
      for (final action in ShortcutAction.values) {
        expect(restored.combosFor(action), keymap.combosFor(action), reason: action.name);
      }
    });

    test('des données corrompues sont ignorées, pas fatales', () {
      final keymap = Keymap.fromOverrides(const {
        'actionInconnue': [
          {'key': 1},
        ],
        'nextFile': 'pas une liste',
        'screenshot': [
          {'key': 'x'},
          {'rien': true},
          7,
        ],
      });
      expect(keymap.combosFor(ShortcutAction.nextFile), Keymap.defaults().combosFor(ShortcutAction.nextFile));
      expect(keymap.combosFor(ShortcutAction.screenshot), isEmpty);
    });

    test('KeyCombo : aller-retour JSON', () {
      for (final combo in [
        KeyCombo(LogicalKeyboardKey.keyO.keyId, control: true, shift: true, alt: true, meta: true),
        const KeyCombo.character('+'),
      ]) {
        expect(KeyCombo.fromJson(combo.toJson()), combo);
      }
      expect(KeyCombo.fromJson(null), isNull);
      expect(KeyCombo.fromJson({'char': ''}), isNull);
    });

    test('capture : un modificateur seul n’est pas un raccourci', () {
      expect(
        KeyCombo.capture(
          key: LogicalKeyboardKey.shiftLeft,
          control: false,
          shift: true,
          alt: false,
          meta: false,
        ),
        isNull,
      );
      expect(
        KeyCombo.capture(
          key: LogicalKeyboardKey.keyK,
          control: true,
          shift: false,
          alt: false,
          meta: false,
        ),
        KeyCombo(LogicalKeyboardKey.keyK.keyId, control: true),
      );
    });
  });

  group('Résolution', () {
    test('le pas de ← / → suit les préférences', () {
      const prefs = AppPreferences(seekStepSeconds: 10);
      expect(resolveShortcut(ShortcutAction.seekForward, prefs), const SeekRelative(10));
      expect(resolveShortcut(ShortcutAction.seekBackward, prefs), const SeekRelative(-10));
      // Les pas moyen et long restent fixes.
      expect(resolveShortcut(ShortcutAction.seekForwardMedium, prefs), const SeekRelative(30));
      expect(resolveShortcut(ShortcutAction.seekBackwardLong, prefs), const SeekRelative(-60));
    });

    test('chaque action se résout en commande ou en action d’interface', () {
      for (final action in ShortcutAction.values) {
        final resolved = resolveShortcut(action, AppPreferences.defaults);
        expect(resolved is PlayerCommand || resolved is UiAction, isTrue, reason: action.name);
      }
    });
  });
}
