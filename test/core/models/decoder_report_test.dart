import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/models/decoder_report.dart';

void main() {
  group('DecoderReport.fromMpv', () {
    test('relève le décodage matériel d une vidéo 4K', () {
      final report = DecoderReport.fromMpv(const {
        'hwdec-current': 'mediacodec-copy',
        'video-format': 'h264',
        'file-format': 'mov,mp4,m4a,3gp,3g2,mj2',
        'width': '3840',
        'height': '2160',
        'container-fps': '23.976024',
        'estimated-vf-fps': '23.974000',
        'frame-drop-count': '0',
        'decoder-frame-drop-count': '0',
        'demuxer-cache-duration': '18.500000',
      });

      expect(report.hardware, isTrue);
      expect(report.decoder, 'h264');
      expect(report.width, 3840);
      expect(report.height, 2160);
      expect(report.totalDroppedFrames, 0);
      expect(report.summary, contains('Matériel (mediacodec-copy)'));
      expect(report.summary, contains('3840×2160'));
      expect(report.summary, contains('aucune image perdue'));
      expect(report.summary, contains('cache 19 s'));
    });

    test('relève le décodage logiciel d un AVI qui décroche', () {
      final report = DecoderReport.fromMpv(const {
        'hwdec-current': 'no',
        'video-format': 'mpeg4',
        'file-format': 'avi',
        'width': '720',
        'height': '400',
        'container-fps': '25.000000',
        'estimated-vf-fps': '8.200000',
        'frame-drop-count': '120',
        'decoder-frame-drop-count': '8',
        'demuxer-cache-duration': '0.000000',
      });

      expect(report.hardware, isFalse);
      expect(report.totalDroppedFrames, 128);
      expect(report.summary, startsWith('Logiciel'));
      // L'écart entre cadence annoncée et cadence rendue est ce que
      // l'utilisateur appelle « au ralenti » : il doit sauter aux yeux.
      expect(report.summary, contains('25 i/s (réel 8.2)'));
      expect(report.summary, contains('128 images perdues'));
      // Cache vide : la ligne ne l'affiche pas plutôt que d'annoncer « 0 s ».
      expect(report.summary, isNot(contains('cache')));
    });

    test('une cadence tenue ne mentionne pas la cadence réelle', () {
      final report = DecoderReport.fromMpv(const {
        'hwdec-current': 'no',
        'video-format': 'mpeg4',
        'container-fps': '25.000000',
        'estimated-vf-fps': '24.900000',
      });
      expect(report.summary, contains('25 i/s'));
      expect(report.summary, isNot(contains('réel')));
    });

    test('une image perdue reste au singulier', () {
      final report = DecoderReport.fromMpv(const {'frame-drop-count': '1'});
      expect(report.summary, contains('1 image perdue'));
    });

    test('des propriétés absentes ou illisibles valent zéro', () {
      final report = DecoderReport.fromMpv(const {
        'hwdec-current': '',
        'width': '',
        'container-fps': 'indisponible',
      });

      expect(report.hardware, isFalse);
      expect(report.width, 0);
      expect(report.fps, 0);
      // La ligne survit à une version de mpv qui ne connaîtrait pas tout.
      expect(report.summary, 'Logiciel · aucune image perdue');
    });
  });
}
