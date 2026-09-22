import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

/// Ce qu'OMNIA affiche d'un fichier audio : titre, artiste, album, pochette.
class AudioTags {
  const AudioTags({
    this.title,
    this.artist,
    this.album,
    this.year,
    this.trackNumber,
    this.cover,
    this.coverMime,
  });

  final String? title;
  final String? artist;
  final String? album;
  final int? year;
  final int? trackNumber;

  /// Pochette encodée (JPEG/PNG), `null` si le fichier n'en a pas.
  final Uint8List? cover;
  final String? coverMime;

  bool get hasCover => cover != null && cover!.isNotEmpty;
  bool get isEmpty => title == null && artist == null && album == null && !hasCover;

  Map<String, Object?> toTransfer() => {
        'title': title,
        'artist': artist,
        'album': album,
        'year': year,
        'trackNumber': trackNumber,
        'cover': cover,
        'coverMime': coverMime,
      };

  factory AudioTags.fromTransfer(Map<String, Object?> map) => AudioTags(
        title: map['title'] as String?,
        artist: map['artist'] as String?,
        album: map['album'] as String?,
        year: map['year'] as int?,
        trackNumber: map['trackNumber'] as int?,
        cover: map['cover'] as Uint8List?,
        coverMime: map['coverMime'] as String?,
      );
}

/// Lit les tags d'un fichier audio, hors du fil de l'interface.
abstract interface class AudioMetadataService {
  /// `null` si le fichier n'a pas de tags lisibles.
  Future<AudioTags?> read(String path);
}

/// Implémentation `audio_metadata_reader` (pur Dart), dans un isolate : un
/// FLAC de 100 Mo avec une pochette de 5 Mo ne doit pas figer l'interface.
class IsolateAudioMetadataService implements AudioMetadataService {
  const IsolateAudioMetadataService();

  @override
  Future<AudioTags?> read(String path) async {
    try {
      final map = await Isolate.run(() => readAudioTagsSync(path));
      if (map == null) return null;
      final tags = AudioTags.fromTransfer(map);
      return tags.isEmpty ? null : tags;
    } on Object {
      return null;
    }
  }
}

/// Lecture synchrone, exposée pour l'isolate et les tests. Retourne une carte
/// de valeurs simples, transférable entre isolates.
Map<String, Object?>? readAudioTagsSync(String path) {
  try {
    final metadata = readMetadata(File(path), getImage: true);
    final picture = metadata.pictures.isEmpty ? null : metadata.pictures.first;
    return AudioTags(
      title: _clean(metadata.title),
      artist: _clean(metadata.artist),
      album: _clean(metadata.album),
      year: metadata.year?.year,
      trackNumber: metadata.trackNumber,
      cover: picture == null ? null : Uint8List.fromList(picture.bytes),
      coverMime: picture?.mimetype,
    ).toTransfer();
  } on Object {
    // Format inconnu ou tags corrompus : la vue affiche le nom du fichier.
    return null;
  }
}

String? _clean(String? value) {
  final v = value?.trim();
  return v == null || v.isEmpty ? null : v;
}

/// Service factice pour les tests.
class FakeAudioMetadataService implements AudioMetadataService {
  FakeAudioMetadataService(this.tagsByPath);

  final Map<String, AudioTags?> tagsByPath;

  @override
  Future<AudioTags?> read(String path) async => tagsByPath[path];
}
