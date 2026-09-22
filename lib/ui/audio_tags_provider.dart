import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/media_type.dart';
import '../core/providers.dart';
import '../core/services/audio_metadata_service.dart';

/// Tags du fichier audio courant, `null` tant qu'ils ne sont pas lus (ou si
/// le fichier n'en a pas). Rechargés à chaque changement de fichier.
final audioTagsProvider = NotifierProvider<AudioTagsNotifier, AudioTags?>(AudioTagsNotifier.new);

class AudioTagsNotifier extends Notifier<AudioTags?> {
  String? _loading;

  @override
  AudioTags? build() {
    final path = ref.watch(
      playbackStateProvider.select((s) => s.mediaType == MediaType.audio ? s.file?.path : null),
    );
    if (path == null) return null;
    _load(path);
    return null;
  }

  Future<void> _load(String path) async {
    _loading = path;
    final tags = await ref.read(audioMetadataServiceProvider).read(path);
    // Un autre fichier a pu être ouvert pendant la lecture des tags.
    if (_loading == path) state = tags;
  }
}
