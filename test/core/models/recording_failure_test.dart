import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/models/playback_state.dart';
import 'package:omnia_mobile/core/models/recording_failure.dart';

void main() {
  group('Raison d’échec d’un extrait', () {
    test('la raison fait l’aller-retour JSON', () {
      const state = PlaybackState(recordingFailure: RecordingFailure.folderUnavailable);
      final json = state.toJson();
      expect(json['recordingFailure'], 'folderUnavailable');
      // Le booléen reste publié : les lectures existantes ne changent pas.
      expect(json['recordingFailed'], isTrue);

      final restored = PlaybackState.fromJson(json);
      expect(restored.recordingFailure, RecordingFailure.folderUnavailable);
      expect(restored.recordingFailed, isTrue);
      expect(restored.toJson(), json);
    });

    test('sans échec, rien n’est signalé', () {
      const state = PlaybackState();
      expect(state.recordingFailure, RecordingFailure.none);
      expect(state.recordingFailed, isFalse);
      expect(PlaybackState.fromJson(state.toJson()).recordingFailed, isFalse);
    });

    test('un état d’avant la raison garde son échec', () {
      final restored = PlaybackState.fromJson(const {'recordingFailed': true});
      expect(restored.recordingFailed, isTrue);
      expect(restored.recordingFailure, RecordingFailure.nothingRecorded);
    });

    test('une raison inconnue ne fait pas d’échec', () {
      final restored = PlaybackState.fromJson(const {'recordingFailure': 'vaudou'});
      expect(restored.recordingFailure, RecordingFailure.none);
      expect(restored.recordingFailed, isFalse);
    });

    test('le booléen suffit encore à poser et à effacer l’échec', () {
      const state = PlaybackState();
      final failed = state.copyWith(recordingFailed: true);
      expect(failed.recordingFailure, RecordingFailure.nothingRecorded);

      final cleared = failed.copyWith(recordingFailed: false);
      expect(cleared.recordingFailure, RecordingFailure.none);
      expect(cleared.recordingFailed, isFalse);

      // Sans mention, la raison est conservée.
      final moved = failed.copyWith(position: const Duration(seconds: 3));
      expect(moved.recordingFailure, RecordingFailure.nothingRecorded);
    });

    test('la raison l’emporte sur le booléen', () {
      final state = const PlaybackState().copyWith(
        recordingFailed: true,
        recordingFailure: RecordingFailure.engineRefused,
      );
      expect(state.recordingFailure, RecordingFailure.engineRefused);
    });
  });
}
