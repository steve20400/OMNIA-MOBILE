import 'dart:async';
import 'dart:io';

import '../commands/player_command.dart';
import '../models/media_file.dart';
import '../models/media_type.dart';
import '../models/playback_status.dart';
import '../utils/os_errors.dart';
import 'media_controller.dart';


/// Contrôleur dédié à l'affichage des images (`.png`, `.jpg`, `.webp`, `.svg`, etc.).
///
/// Gère le zoom, la rotation à 90° et le centrage avec les gestes et raccourcis
/// habituels d'OMNIA.
class ImageController implements MediaController {
  PlaybackStateSink? _sink;
  MediaFile? _currentFile;

  static const double minZoom = 0.1;
  static const double maxZoom = 10.0;

  @override
  Set<MediaType> get supportedTypes => const {MediaType.image};

  MediaFile? get currentFile => _currentFile;

  @override
  Future<void> open(MediaFile file, PlaybackStateSink sink) async {
    _sink = sink;
    _currentFile = file;

    sink.update(
      (st) => st.copyWith(
        file: file,
        status: PlaybackStatus.loading,
        position: Duration.zero,
        duration: Duration.zero,
        hasVideo: false,
        zoom: 1.0,
        rotation: 0,
        videoZoom: 0,
        clearError: true,
      ),
    );

    try {
      final ioFile = File(file.path);
      if (!await ioFile.exists()) {
        throw PathNotFoundException(file.path, const OSError('Fichier introuvable', 2));
      }

      sink.update(
        (st) => st.copyWith(
          status: PlaybackStatus.playing,
          zoom: 1.0,
          rotation: 0,
        ),
      );

    } on FileSystemException catch (e) {
      _currentFile = null;
      sink.update(
        (st) => st.copyWith(
          status: PlaybackStatus.error,
          error: PlaybackError(classifyFileSystemError(e), detail: e.message),
        ),
      );
    } on Object catch (e) {
      _currentFile = null;
      sink.update(
        (st) => st.copyWith(
          status: PlaybackStatus.error,
          error: PlaybackError(PlaybackErrorCode.decodeFailed, detail: e.toString()),
        ),
      );
    }
  }

  @override
  Future<bool> handle(PlayerCommand command) async {
    final sink = _sink;
    if (sink == null || _currentFile == null) return false;

    switch (command) {
      case ZoomRelative(:final factor):
        sink.update((st) => st.copyWith(zoom: _clampZoom(st.zoom * factor)));
      case SetZoom(:final zoom):
        sink.update((st) => st.copyWith(zoom: _clampZoom(zoom)));
      case FitZoom():
        sink.update((st) => st.copyWith(zoom: 1.0));
      case RotateDocument(:final quarterTurns):
        sink.update((st) => st.copyWith(rotation: (st.rotation + quarterTurns) % 4));
      case RotateVideo(:final quarterTurns):
        sink.update((st) => st.copyWith(rotation: (st.rotation + quarterTurns) % 4));
      default:
        return false;
    }
    return true;
  }


  static double _clampZoom(double value) => value.clamp(minZoom, maxZoom);

  @override
  Future<void> close() async {
    _currentFile = null;
    _sink?.update(
      (st) => st.copyWith(
        clearFile: true,
        status: PlaybackStatus.idle,
        zoom: 1.0,
        rotation: 0,
        clearError: true,
      ),
    );

    _sink = null;
  }

  @override
  Future<void> dispose() async {
    _currentFile = null;
    _sink = null;
  }
}
