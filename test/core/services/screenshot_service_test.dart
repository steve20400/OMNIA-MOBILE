import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/services/screenshot_service.dart';
import 'package:omnia_mobile/core/services/settings_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
  final when = DateTime(2026, 9, 7, 21, 4, 5);

  setUp(() => dir = Directory.systemTemp.createTempSync('omnia_shot_'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Nettoyé par le système.
    }
  });

  test('enregistre dans le dossier par défaut, avec le nom attendu', () async {
    final service = ScreenshotService(defaultFolder: () async => dir);
    final path = await service.save(png, mediaPath: '/films/ep1.mkv', now: when);

    expect(p.dirname(path), dir.path);
    expect(p.basename(path), 'ep1 2026-09-07 21-04-05.png');
    expect(File(path).readAsBytesSync(), png);
  });

  test('le dossier des préférences a priorité', () async {
    final custom = Directory(p.join(dir.path, 'perso'));
    final settings = MemorySettingsStore();
    await settings.setScreenshotFolder(custom.path);
    final service = ScreenshotService(settings: settings, defaultFolder: () async => dir);

    final path = await service.save(png, mediaPath: '/films/ep1.mkv', now: when);
    expect(p.dirname(path), custom.path);
    expect(custom.existsSync(), isTrue);
  });

  test('deux captures dans la même seconde ne s’écrasent pas', () async {
    final service = ScreenshotService(defaultFolder: () async => dir);
    final first = await service.save(png, mediaPath: '/films/ep1.mkv', now: when);
    final second = await service.save(png, mediaPath: '/films/ep1.mkv', now: when);
    final third = await service.save(png, mediaPath: '/films/ep1.mkv', now: when);

    expect(first, isNot(second));
    expect(p.basename(second), 'ep1 2026-09-07 21-04-05 (2).png');
    expect(p.basename(third), 'ep1 2026-09-07 21-04-05 (3).png');
  });

  group('Extraits', () {
    test('même dossier et même motif que les captures, conteneur Matroska', () async {
      final service = ScreenshotService(defaultFolder: () async => dir);
      final video = await service.recordingPath(mediaPath: '/films/ep1.mkv', audioOnly: false, now: when);
      final audio = await service.recordingPath(mediaPath: '/musique/a.flac', audioOnly: true, now: when);

      expect(p.dirname(video), dir.path);
      expect(p.basename(video), 'ep1 2026-09-07 21-04-05.mkv');
      expect(p.basename(audio), 'a 2026-09-07 21-04-05.mka');
    });

    test('un extrait existant n’est jamais écrasé', () async {
      final service = ScreenshotService(defaultFolder: () async => dir);
      final first = await service.recordingPath(mediaPath: '/films/ep1.mkv', audioOnly: false, now: when);
      File(first).writeAsStringSync('déjà là');
      final second = await service.recordingPath(mediaPath: '/films/ep1.mkv', audioOnly: false, now: when);
      expect(p.basename(second), 'ep1 2026-09-07 21-04-05 (2).mkv');
    });

    test('le dossier est créé s’il manque', () async {
      final nested = Directory(p.join(dir.path, 'extraits', 'OMNIA'));
      final service = ScreenshotService(defaultFolder: () async => nested);
      await service.recordingPath(mediaPath: '/films/ep1.mkv', audioOnly: false, now: when);
      expect(nested.existsSync(), isTrue);
    });

    test('séparation distincte des dossiers de captures vidéo et extraits audio', () async {
      final shotsDir = Directory(p.join(dir.path, 'video_shots'));
      final audioDir = Directory(p.join(dir.path, 'audio_records'));
      final settings = MemorySettingsStore();
      await settings.setScreenshotFolder(shotsDir.path);
      await settings.setRecordingFolder(audioDir.path);
      final service = ScreenshotService(settings: settings, defaultFolder: () async => dir);

      final shotPath = await service.save(png, mediaPath: '/films/ep1.mkv', now: when);
      final audioPath = await service.recordingPath(mediaPath: '/musique/son.mp3', audioOnly: true, now: when);

      expect(p.dirname(shotPath), shotsDir.path);
      expect(p.dirname(audioPath), audioDir.path);
    });
  });
}

