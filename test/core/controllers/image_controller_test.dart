import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/commands/player_command.dart';
import 'package:omnia_mobile/core/controllers/image_controller.dart';
import 'package:omnia_mobile/core/controllers/media_controller.dart';
import 'package:omnia_mobile/core/models/document_layout.dart';
import 'package:omnia_mobile/core/models/media_file.dart';
import 'package:omnia_mobile/core/models/media_type.dart';
import 'package:omnia_mobile/core/models/playback_state.dart';
import 'package:omnia_mobile/core/models/playback_status.dart';
import 'package:path/path.dart' as p;

class _CapturingSink implements PlaybackStateSink {
  @override
  PlaybackState state = const PlaybackState();

  @override
  void update(PlaybackState Function(PlaybackState current) edit) {
    state = edit(state);
  }
}

void main() {
  group('ImageController', () {
    late Directory tempDir;
    late File dummyFile;
    late MediaFile file;
    late ImageController controller;
    late _CapturingSink sink;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('omnia_image_test_');
      dummyFile = File(p.join(tempDir.path, 'vacances.jpg'))..writeAsBytesSync([1, 2, 3]);
      file = MediaFile(path: dummyFile.path, type: MediaType.image);
      controller = ImageController();
      sink = _CapturingSink();
    });

    tearDown(() async {
      await controller.dispose();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('gère MediaType.image', () {
      expect(controller.supportedTypes, contains(MediaType.image));
    });

    test('open initialise l’état avec succès', () async {
      await controller.open(file, sink);

      expect(sink.state.status, PlaybackStatus.playing);
      expect(sink.state.mediaType, MediaType.image);
      expect(sink.state.file, file);
      expect(sink.state.zoom, 1.0);
      expect(sink.state.rotation, 0);
    });

    test('fichier introuvable → erreur claire', () async {
      final missing = MediaFile(path: p.join(tempDir.path, 'absent.jpg'), type: MediaType.image);
      await controller.open(missing, sink);
      expect(sink.state.status, PlaybackStatus.error);
    });

    test('ZoomRelative et SetZoom modifient le niveau de zoom dans les bornes', () async {
      await controller.open(file, sink);

      await controller.handle(const ZoomRelative(1.5));
      expect(sink.state.zoom, closeTo(1.5, 0.01));

      await controller.handle(const SetZoom(3.0));
      expect(sink.state.zoom, closeTo(3.0, 0.01));

      // Test des bornes (max 10.0, min 0.1)
      await controller.handle(const SetZoom(25.0));
      expect(sink.state.zoom, closeTo(10.0, 0.01));

      await controller.handle(const SetZoom(0.01));
      expect(sink.state.zoom, closeTo(0.1, 0.01));
    });

    test('RotateDocument pivote l’image par quart de tour modulo 4', () async {
      await controller.open(file, sink);

      await controller.handle(const RotateDocument(1));
      expect(sink.state.rotation, 1);

      await controller.handle(const RotateDocument(3));
      expect(sink.state.rotation, 0); // (1 + 3) % 4 == 0
    });

    test('FitZoom réinitialise le zoom à 1.0', () async {
      await controller.open(file, sink);

      await controller.handle(const SetZoom(2.5));
      expect(sink.state.zoom, 2.5);

      await controller.handle(const FitZoom(FitMode.width));
      expect(sink.state.zoom, 1.0);
    });
  });
}
