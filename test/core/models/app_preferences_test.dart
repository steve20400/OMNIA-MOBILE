import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/models/app_preferences.dart';
import 'package:omnia_mobile/core/models/document_layout.dart';
import 'package:omnia_mobile/core/models/equalizer.dart';

void main() {
  group('AppPreferences — valeurs par défaut', () {
    test('conformes au cahier des charges', () {
      const p = AppPreferences.defaults;
      expect(p.language, AppLanguage.system);
      expect(p.themeMode, AppThemeMode.dark);
      expect(p.resumePolicy, ResumePolicy.auto);
      expect(p.singleInstance, isTrue);
      expect(p.seekStepSeconds, 5);
      expect(p.defaultSpeed, 1.0);
      expect(p.startupVolume, StartupVolume.last);
      expect(p.subtitleAutoLoad, isTrue);
      expect(p.equalizerEnabled, isFalse);
      expect(p.pdfLayout, DocumentLayout.continuous);
      expect(p.screenshotNamePattern, AppPreferences.defaultScreenshotPattern);
      expect(p.normalPlayerAlwaysOnTop, isFalse);
      expect(p.miniPlayerAlwaysOnTop, isTrue);
      expect(p.docAutoSave, isTrue);
      expect(p.docAutoSaveIntervalSeconds, 2);
      expect(p.unsavedChangesPolicy, UnsavedChangesPolicy.ask);
      expect(p.inAppOpenTarget, InAppOpenTarget.currentWindow);
      expect(p.rememberPlaybackState, isTrue);
      expect(p.historyRetentionDays, 30);
      expect(p.desktopPromoDismissed, isFalse);
      expect(p.desktopPromoSnoozeUntil, isNull);
      expect(p.omniaConnectEnabled, isTrue);
      expect(p.allowRemoteControl, isTrue);
      expect(p.allowRemoteStreaming, isTrue);
      expect(p.wirelessMode, 'wifi');
      expect(p.autoCheckUpdates, isTrue);
      expect(p.updateChannel, 'stable');
    });
  });

  group('AppPreferences — JSON', () {
    test('aller-retour exact', () {
      final p = AppPreferences.defaults.copyWith(
        language: AppLanguage.en,
        themeMode: AppThemeMode.light,
        resumePolicy: ResumePolicy.ask,
        singleInstance: false,
        seekStepSeconds: 30,
        defaultSpeed: 1.25,
        startupVolume: StartupVolume.fixed,
        fixedVolume: 42,
        subtitleScale: 1.5,
        subtitleAutoLoad: false,
        subtitleDelay: -1.5,
        equalizerEnabled: true,
        equalizerGains: Equalizer.presets['rock'],
        pdfLayout: DocumentLayout.paged,
        readingDark: true,
        textScale: 1.4,
        docAutoSave: false,
        docAutoSaveIntervalSeconds: 5,
        unsavedChangesPolicy: UnsavedChangesPolicy.save,
        screenshotNamePattern: '{name} @ {position}',
        normalPlayerAlwaysOnTop: true,
        miniPlayerAlwaysOnTop: false,
        inAppOpenTarget: InAppOpenTarget.newWindow,
        rememberPlaybackState: false,
        historyRetentionDays: 90,
        omniaConnectEnabled: false,
        allowRemoteControl: false,
        allowRemoteStreaming: false,
        wirelessMode: 'hotspot',
        autoCheckUpdates: false,
        updateChannel: 'preview',
      );

      final restored = AppPreferences.fromJson(p.toJson());
      expect(restored, p);
      expect(restored.hashCode, p.hashCode);
    });

    test('carte vide → valeurs par défaut', () {
      expect(AppPreferences.fromJson(const {}), AppPreferences.defaults);
    });

    test('types erronés → valeurs par défaut, sans exception', () {
      final p = AppPreferences.fromJson(const {
        'language': 42,
        'themeMode': 'violet',
        'resumePolicy': null,
        'singleInstance': 'oui',
        'seekStepSeconds': 'cinq',
        'defaultSpeed': 'vite',
        'equalizerGains': 'plat',
        'screenshotNamePattern': 7,
      });
      expect(p, AppPreferences.defaults);
    });

    test('valeurs hors bornes ramenées dans les bornes', () {
      final p = AppPreferences.fromJson(const {
        'seekStepSeconds': 7,
        'defaultSpeed': 9.0,
        'fixedVolume': 250,
        'subtitleScale': 10,
        'subtitleDelay': -99,
        'textScale': 0.1,
        'equalizerGains': [40, -40],
      });
      expect(p.seekStepSeconds, 5, reason: 'pas le plus proche de 7');
      expect(p.defaultSpeed, 4.0);
      expect(p.fixedVolume, 100);
      expect(p.subtitleScale, 2.5);
      expect(p.subtitleDelay, -30);
      expect(p.textScale, 0.6);
      expect(p.equalizerGains.length, Equalizer.bands.length);
      expect(p.equalizerGains.first, Equalizer.maxGain);
      expect(p.equalizerGains[1], Equalizer.minGain);
      expect(p.equalizerGains.last, 0);
    });

    test('un motif de capture vide retombe sur le motif par défaut', () {
      expect(
        AppPreferences.defaults.copyWith(screenshotNamePattern: '   ').screenshotNamePattern,
        AppPreferences.defaultScreenshotPattern,
      );
    });
  });

  group('AppPreferences — copyWith', () {
    test('ne modifie que ce qui est demandé', () {
      final p = AppPreferences.defaults.copyWith(seekStepSeconds: 10);
      expect(p.seekStepSeconds, 10);
      expect(p.copyWith(), p);
      expect(p == AppPreferences.defaults, isFalse);
    });

    test('la vitesse suit le pas de 0,25', () {
      expect(AppPreferences.defaults.copyWith(defaultSpeed: 1.3).defaultSpeed, 1.25);
      expect(AppPreferences.defaults.copyWith(defaultSpeed: 0.1).defaultSpeed, 0.25);
    });
  });

  group('changements partiels', () {
    test('preferencesDiff ne garde que ce qui change', () {
      final a = AppPreferences.defaults;
      final b = a.copyWith(seekStepSeconds: 30, equalizerGains: Equalizer.presets['rock']);
      final diff = preferencesDiff(a, b);
      expect(diff.keys, unorderedEquals(['seekStepSeconds', 'equalizerGains']));
      expect(preferencesDiff(a, a), isEmpty);
    });

    test('merge applique un changement partiel et ignore l’inconnu', () {
      final merged = AppPreferences.defaults.merge(const {
        'seekStepSeconds': 60,
        'cléInconnue': 1,
      });
      expect(merged.seekStepSeconds, 60);
      expect(merged.copyWith(seekStepSeconds: 5), AppPreferences.defaults);
    });

    test('merge borne les valeurs comme la relecture', () {
      expect(AppPreferences.defaults.merge(const {'fixedVolume': 500}).fixedVolume, 100);
    });

    test('diff puis merge redonne l’état visé', () {
      final a = AppPreferences.defaults;
      final b = a.copyWith(language: AppLanguage.en, readingDark: true, textScale: 1.5);
      expect(a.merge(preferencesDiff(a, b)), b);
    });
  });

  test('les énumérations tolèrent une valeur inconnue', () {
    expect(AppLanguage.fromJson('klingon'), AppLanguage.system);
    expect(AppThemeMode.fromJson(null), AppThemeMode.dark);
    expect(ResumePolicy.fromJson('peut-être'), ResumePolicy.auto);
    expect(StartupVolume.fromJson(3), StartupVolume.last);
    expect(InAppOpenTarget.fromJson('inconnu'), InAppOpenTarget.currentWindow);
  });
}
