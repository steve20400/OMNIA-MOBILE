import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/services/audio_metadata_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('omnia_tags_'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Nettoyé par le système.
    }
  });

  test('un fichier qui n’est pas de l’audio → null, sans exception', () async {
    final file = File(p.join(dir.path, 'faux.mp3'))..writeAsStringSync('pas du son');
    expect(readAudioTagsSync(file.path), isNull);
    expect(await const IsolateAudioMetadataService().read(file.path), isNull);
  });

  test('fichier absent → null', () async {
    expect(await const IsolateAudioMetadataService().read(p.join(dir.path, 'absent.flac')), isNull);
  });

  test('AudioTags : transfert entre isolates et vacuité', () {
    final tags = AudioTags(
      title: 'Titre',
      artist: 'Artiste',
      cover: Uint8List.fromList([1, 2, 3]),
      coverMime: 'image/jpeg',
    );
    final restored = AudioTags.fromTransfer(tags.toTransfer());
    expect(restored.title, 'Titre');
    expect(restored.hasCover, isTrue);
    expect(restored.isEmpty, isFalse);
    expect(const AudioTags().isEmpty, isTrue);
  });
}
