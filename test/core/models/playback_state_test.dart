import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/models/media_file.dart';
import 'package:omnia_mobile/core/models/media_type.dart';
import 'package:omnia_mobile/core/models/playback_state.dart';

void main() {
  group('PlaybackState — dimensions de l’image', () {
    test('aller-retour JSON', () {
      const state = PlaybackState(
        file: MediaFile(path: '/a/b.mkv', type: MediaType.video),
        hasVideo: true,
        videoWidth: 1920,
        videoHeight: 1080,
      );
      final json = state.toJson();
      expect(json['videoWidth'], 1920);
      expect(json['videoHeight'], 1080);

      final restored = PlaybackState.fromJson(json);
      expect(restored.videoWidth, 1920);
      expect(restored.videoHeight, 1080);
      expect(restored.videoAspect, closeTo(16 / 9, 1e-9));
      expect(restored.toJson(), json);
    });

    test('JSON sans dimensions : 0, ratio inconnu', () {
      final restored = PlaybackState.fromJson(const {'hasVideo': true});
      expect(restored.videoWidth, 0);
      expect(restored.videoHeight, 0);
      expect(restored.videoAspect, isNull);
    });

    test('le ratio exige une image aux deux dimensions connues', () {
      expect(
        const PlaybackState(hasVideo: true, videoWidth: 1920, videoHeight: 1080).videoAspect,
        closeTo(16 / 9, 1e-9),
      );
      expect(
        const PlaybackState(hasVideo: true, videoWidth: 1080, videoHeight: 1920).videoAspect,
        closeTo(9 / 16, 1e-9),
      );
      expect(const PlaybackState(hasVideo: true, videoWidth: 1920).videoAspect, isNull);
      // Des dimensions sans piste vidéo ne comptent pas.
      expect(const PlaybackState(videoWidth: 1920, videoHeight: 1080).videoAspect, isNull);
    });

    test('copyWith garde ou remplace les dimensions', () {
      const state = PlaybackState(hasVideo: true, videoWidth: 1920, videoHeight: 1080);
      final moved = state.copyWith(position: const Duration(seconds: 1));
      expect(moved.videoWidth, 1920);
      expect(moved.videoHeight, 1080);

      final next = state.copyWith(videoWidth: 1280, videoHeight: 720);
      expect(next.videoWidth, 1280);
      expect(next.videoHeight, 720);
    });
  });
}
