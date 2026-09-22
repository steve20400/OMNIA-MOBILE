import 'package:path/path.dart' as p;

import 'media_type.dart';

/// Un fichier ouvrable par OMNIA.
///
/// Immuable et sérialisable : il apparaît dans [PlaybackState] et, demain,
/// dans les messages échangés avec la télécommande.
class MediaFile {
  const MediaFile({
    required this.path,
    required this.type,
    this.size,
    this.modifiedAt,
  });

  /// Chemin absolu du fichier.
  final String path;

  /// Type de média déduit de l'extension.
  final MediaType type;

  /// Taille en octets, si connue (renseignée par le scan de dossier).
  final int? size;

  /// Date de dernière modification, si connue.
  final DateTime? modifiedAt;

  /// Nom de fichier avec extension (ex. `episode-02.mkv`).
  String get name => p.basename(path);

  /// Nom de fichier sans extension.
  String get baseName => p.basenameWithoutExtension(path);

  /// Extension en minuscules, sans le point (ex. `mkv`).
  String get extension =>
      p.extension(path).toLowerCase().replaceFirst('.', '');

  /// Dossier parent.
  String get directory => p.dirname(path);

  Map<String, Object?> toJson() => {
        'path': path,
        'type': type.name,
        if (size != null) 'size': size,
        if (modifiedAt != null) 'modifiedAt': modifiedAt!.toIso8601String(),
      };

  factory MediaFile.fromJson(Map<String, Object?> json) => MediaFile(
        path: json['path'] as String,
        type: MediaType.fromJson(json['type']),
        size: json['size'] as int?,
        modifiedAt: json['modifiedAt'] is String
            ? DateTime.tryParse(json['modifiedAt']! as String)
            : null,
      );

  MediaFile copyWith({int? size, DateTime? modifiedAt}) => MediaFile(
        path: path,
        type: type,
        size: size ?? this.size,
        modifiedAt: modifiedAt ?? this.modifiedAt,
      );

  /// Deux [MediaFile] sont égaux s'ils désignent le même chemin.
  @override
  bool operator ==(Object other) => other is MediaFile && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'MediaFile($name, ${type.name})';
}
