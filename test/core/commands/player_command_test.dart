import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/commands/player_command.dart';
import 'package:omnia_mobile/core/models/document_layout.dart';
import 'package:omnia_mobile/core/models/end_of_playback_mode.dart';
import 'package:omnia_mobile/core/models/equalizer.dart';
import 'package:omnia_mobile/core/models/playlist_sort.dart';
import 'package:omnia_mobile/core/models/video_adjust.dart';

void main() {
  group('PlayerCommand — sérialisation JSON', () {
    // Une instance de chaque commande : l'aller-retour JSON doit être exact.
    const samples = <PlayerCommand>[
      Play(),
      Pause(),
      TogglePlay(),
      Stop(),
      SeekRelative(-5),
      SeekAbsolute(Duration(minutes: 1, seconds: 30)),
      SetVolume(42.5),
      VolumeRelative(-5),
      ToggleMute(),
      NextFile(),
      PreviousFile(),
      SetSpeed(1.5),
      SpeedRelative(0.25),
      NextPage(),
      PreviousPage(),
      GoToPage(12),
      SetZoom(1.25),
      ToggleFullscreen(),
      ExitFullscreen(),
      TakeScreenshot(),
      ToggleRecording(),
      SetLoopMode(EndOfPlaybackMode.loopFolder),
      CycleLoopMode(),
      ToggleAlwaysOnTop(),
      ToggleSidePanel(),
      SetSidePanelVisible(false),
      SetSidePanelWidth(320),
      SetControlBarWidth(640),
      OpenFile('/videos/ep2.mkv'),
      OpenFolder('/videos'),
      // Phase 2
      SetPlaylistSort(PlaylistSort.size, descending: true),
      SetPlaylistFilter(PlaylistFilter.audio),
      SetPlaylistFilter(PlaylistFilter.images),
      SetPlaylistQuery('ep'),

      RemoveFromPlaylist('/videos/ep3.mkv'),
      RescanFolder(),
      RevealInFolder('/videos/ep2.mkv'),
      // Phase 3
      ClearHistory(),
      // Phase 4
      ZoomRelative(1.2),
      FitZoom(FitMode.page),
      RotateDocument(3),
      ToggleReadingDarkMode(),
      SetDocumentLayout(DocumentLayout.paged),
      ToggleDocumentLayout(),
      ScrollTo(0.42),
      ScrollDocument(175.0),
      // Phase 5
      SetSubtitleTrack('2'),
      SetSubtitleTrack(null),
      ToggleSubtitles(),
      LoadSubtitleFile('/videos/ep2.fr.srt'),
      SetSubtitleDelay(-0.5),
      SubtitleDelayRelative(0.5),
      SetSubtitleScale(1.5),
      SetAudioTrack('1'),
      CycleAbLoop(),
      ClearAbLoop(),
      SetAspectMode(AspectMode.wide),
      VideoZoomRelative(0.1),
      ResetVideoZoom(),
      RotateVideo(2),
      SetVideoAdjust(VideoAdjust(brightness: 10, contrast: -5, saturation: 20)),
      ResetVideoAdjust(),
      SetEqualizerGains([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
      SetEqualizerPreset('rock'),
      ToggleEqualizer(),
      ToggleMiniPlayer(),
      // Phase 6
      ClearRecentFiles(),
      ClearResumePositions(),
      AcceptResume(),
      DeclineResume(),
      UpdatePreferences({'seekStepSeconds': 10, 'equalizerGains': Equalizer.flat}),
      SetScreenshotFolder('/captures'),
      SetScreenshotFolder(null),
      SetRecordingFolder('/recordings'),
      SetRecordingFolder(null),
    ];


    for (final command in samples) {
      test('${command.type} survit à toJson → fromJson', () {
        final json = command.toJson();
        expect(json['type'], command.type);
        final restored = PlayerCommand.fromJson(json);
        expect(restored, equals(command));
        expect(restored.hashCode, command.hashCode);
        expect(restored.runtimeType, command.runtimeType);
      });
    }

    test('chaque commande a un type unique', () {
      // Deux échantillons de SetSubtitleTrack : on compare les types distincts
      // aux classes distinctes, pas au nombre d'échantillons.
      final types = samples.map((c) => c.type).toSet();
      final classes = samples.map((c) => c.runtimeType).toSet();
      expect(types.length, classes.length);
    });

    test('les arguments sont conservés', () {
      final seek = PlayerCommand.fromJson({'type': 'seekAbsolute', 'positionMs': 90000});
      expect(seek, isA<SeekAbsolute>());
      expect((seek as SeekAbsolute).position, const Duration(seconds: 90));

      final page = PlayerCommand.fromJson({'type': 'goToPage', 'page': 7});
      expect((page as GoToPage).page, 7);
    });

    test('un entier est accepté pour un argument décimal', () {
      final v = PlayerCommand.fromJson({'type': 'setVolume', 'volume': 80});
      expect((v as SetVolume).volume, 80.0);
    });

    test('type inconnu → FormatException', () {
      expect(
        () => PlayerCommand.fromJson({'type': 'teleport'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('argument manquant → FormatException', () {
      expect(
        () => PlayerCommand.fromJson({'type': 'seekRelative'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PlayerCommand.fromJson({'type': 'openFile'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('mode de boucle inconnu → repli sur « suivant »', () {
      final c = PlayerCommand.fromJson({'type': 'setLoopMode', 'mode': '???'});
      expect((c as SetLoopMode).mode, EndOfPlaybackMode.next);
    });

    test('égalité structurelle', () {
      expect(const SeekRelative(5), equals(const SeekRelative(5)));
      expect(const SeekRelative(5), isNot(equals(const SeekRelative(-5))));
      expect(const Play(), isNot(equals(const Pause())));
    });
  });
}
