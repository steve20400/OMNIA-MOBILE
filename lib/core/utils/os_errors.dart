import 'dart:io';

import '../models/playback_status.dart';

/// Traduit une erreur du système de fichiers en code d'erreur d'OMNIA.
///
/// Les numéros d'erreur ne veulent pas dire la même chose partout : `13` est
/// `EACCES` (accès refusé) sous Linux et macOS, mais `ERROR_INVALID_DATA` sous
/// Windows, où l'accès refusé porte le numéro `5`. Supposer les codes POSIX
/// afficherait « accès refusé » sous Windows pour un fichier simplement
/// introuvable, et enverrait l'utilisateur chercher des droits qui ne sont pas
/// en cause.
PlaybackErrorCode classifyFileSystemError(FileSystemException exception) {
  final code = exception.osError?.errorCode;
  if (code == null) return PlaybackErrorCode.fileNotFound;

  if (Platform.isWindows) {
    return switch (code) {
      // ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND, ERROR_INVALID_NAME,
      // ERROR_BAD_NETPATH, ERROR_NOT_READY (lecteur ou partage absent)
      2 || 3 || 15 || 21 || 53 || 123 => PlaybackErrorCode.fileNotFound,
      // ERROR_ACCESS_DENIED, ERROR_SHARING_VIOLATION, ERROR_LOCK_VIOLATION,
      // ERROR_NETWORK_ACCESS_DENIED
      5 || 32 || 33 || 65 => PlaybackErrorCode.permissionDenied,
      _ => PlaybackErrorCode.unknown,
    };
  }

  // Linux et macOS : codes POSIX.
  return switch (code) {
    // ENOENT, ENXIO, ENODEV, ENOTDIR, ENAMETOOLONG
    2 || 6 || 19 || 20 || 36 => PlaybackErrorCode.fileNotFound,
    // EPERM, EACCES, EROFS
    1 || 13 || 30 => PlaybackErrorCode.permissionDenied,
    _ => PlaybackErrorCode.unknown,
  };
}
