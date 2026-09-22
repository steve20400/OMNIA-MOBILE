import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/models/app_preferences.dart';
import 'package:omnia_mobile/core/services/local_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('omnia_snapshot_'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Nettoyé par le système.
    }
  });

  group('Copie en clair des préférences', () {
    test('absente : rien à relire', () {
      expect(readPreferencesSnapshot(dir), isNull);
    });

    test('écrite puis relue à l’identique', () async {
      final prefs = AppPreferences.defaults.copyWith(
        language: AppLanguage.en,
        themeMode: AppThemeMode.light,
        seekStepSeconds: 10,
      );
      await writePreferencesSnapshot(dir, prefs);
      expect(readPreferencesSnapshot(dir), prefs);
    });

    test('corrompue : ignorée, sans exception', () {
      File(p.join(dir.path, preferencesSnapshotName)).writeAsStringSync('{ pas du json');
      expect(readPreferencesSnapshot(dir), isNull);
    });

    test('le dossier est créé s’il manque', () async {
      final nested = Directory(p.join(dir.path, 'a', 'b'));
      await writePreferencesSnapshot(nested, AppPreferences.defaults);
      expect(readPreferencesSnapshot(nested), AppPreferences.defaults);
    });
  });
}
