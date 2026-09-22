import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/commands/player_command.dart';
import 'package:omnia_mobile/core/controllers/media_controller.dart';
import 'package:omnia_mobile/core/controllers/text_controller.dart';
import 'package:omnia_mobile/core/models/document_layout.dart';
import 'package:omnia_mobile/core/models/media_file.dart';
import 'package:omnia_mobile/core/models/media_type.dart';
import 'package:omnia_mobile/core/models/playback_state.dart';
import 'package:omnia_mobile/core/models/playback_status.dart';
import 'package:path/path.dart' as p;

class _Sink implements PlaybackStateSink {
  PlaybackState _state = const PlaybackState();
  @override
  PlaybackState get state => _state;
  @override
  void update(PlaybackState Function(PlaybackState) reducer) => _state = reducer(_state);
}

void main() {
  late Directory dir;
  late TextController controller;
  late _Sink sink;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('omnia_text_');
    controller = TextController();
    sink = _Sink();
  });

  tearDown(() async {
    await controller.dispose();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Nettoyé par le système.
    }
  });

  MediaFile write(String name, List<int> bytes) {
    final file = File(p.join(dir.path, name))..writeAsBytesSync(bytes);
    return MediaFile(path: file.path, type: MediaType.text);
  }

  test('ouvre un .txt UTF-8 et publie le document', () async {
    final file = write('notes.txt', 'ligne 1\r\nligne 2\n'.codeUnits);
    await controller.open(file, sink);

    expect(sink.state.status, PlaybackStatus.playing);
    expect(sink.state.file, file);
    expect(sink.state.hasVideo, isFalse);
    expect(controller.document?.text, 'ligne 1\nligne 2\n');
    expect(controller.document?.isMarkdown, isFalse);
    expect(controller.document?.encoding, 'UTF-8');
    expect(controller.document?.lineCount, 3);
  });

  test('un .md est marqué Markdown', () async {
    final file = write('lisez-moi.md', '# Titre'.codeUnits);
    await controller.open(file, sink);
    expect(controller.document?.isMarkdown, isTrue);
  });

  test('un fichier Latin-1 s’ouvre avec ses accents', () async {
    final file = write('vieux.txt', [0x63, 0x61, 0x66, 0xE9]);
    await controller.open(file, sink);
    expect(controller.document?.text, 'café');
    expect(controller.document?.encoding, 'Windows-1252');
  });

  test('fichier introuvable → erreur claire, pas d’exception', () async {
    final missing = MediaFile(path: p.join(dir.path, 'absent.txt'), type: MediaType.text);
    await controller.open(missing, sink);
    expect(sink.state.status, PlaybackStatus.error);
    expect(sink.state.error?.code, PlaybackErrorCode.fileNotFound);
    expect(controller.document, isNull);
  });

  test('le flux émet le document puis null à la fermeture', () async {
    final events = <TextDocument?>[];
    final sub = controller.documents.listen(events.add);
    final file = write('a.txt', 'x'.codeUnits);
    await controller.open(file, sink);
    await controller.close();
    await Future<void>.delayed(Duration.zero);

    expect(events.length, 2);
    expect(events.first?.text, 'x');
    expect(events.last, isNull);
    expect(sink.state.hasFile, isFalse);
    await sub.cancel();
  });

  group('commandes', () {
    setUp(() => controller.open(write('a.txt', 'texte'.codeUnits), sink));

    test('zoom relatif borné', () async {
      for (var i = 0; i < 20; i++) {
        await controller.handle(const ZoomRelative(1.25));
      }
      expect(sink.state.zoom, TextController.maxScale);
      for (var i = 0; i < 40; i++) {
        await controller.handle(const ZoomRelative(0.8));
      }
      expect(sink.state.zoom, TextController.minScale);
    });

    test('FitZoom ramène à l’échelle normale', () async {
      await controller.handle(const SetZoom(2.0));
      expect(sink.state.zoom, 2.0);
      await controller.handle(const FitZoom(FitMode.width));
      expect(sink.state.zoom, 1.0);
    });

    test('mode sombre de lecture', () async {
      await controller.handle(const ToggleReadingDarkMode());
      expect(sink.state.readingDark, isTrue);
      await controller.handle(const ToggleReadingDarkMode());
      expect(sink.state.readingDark, isFalse);
    });

    test('ScrollTo borné à 0–1', () async {
      await controller.handle(const ScrollTo(0.42));
      expect(sink.state.scrollFraction, 0.42);
      await controller.handle(const ScrollTo(7));
      expect(sink.state.scrollFraction, 1.0);
    });

    test('une commande média est refusée', () async {
      expect(await controller.handle(const SeekRelative(5)), isFalse);
      expect(await controller.handle(const TogglePlay()), isFalse);
    });
  });

  test('updateText met à jour le texte et le nombre de lignes', () async {
    final file = write('edit.txt', 'texte original'.codeUnits);
    await controller.open(file, sink);
    expect(controller.document?.text, 'texte original');

    controller.updateText('ligne 1\nligne 2\nligne 3');
    expect(controller.document?.text, 'ligne 1\nligne 2\nligne 3');
    expect(controller.document?.lineCount, 3);
  });

  test('sans document, toute commande est refusée', () async {
    expect(await controller.handle(const ZoomRelative(2)), isFalse);
  });
}
