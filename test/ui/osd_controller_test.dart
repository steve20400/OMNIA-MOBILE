// Retour à l'écran dans une fenêtre où la barre de contrôles est VISIBLE :
// c'est le cas que l'utilisateur voyait muet. Le volume doit s'y annoncer, et
// un extrait doit toujours dire ce qu'il est devenu — fichier écrit ou rien
// du tout —, car il n'a aucun autre retour.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/commands/player_command.dart';
import 'package:omnia_mobile/core/commands/player_command_bus.dart';
import 'package:omnia_mobile/core/controllers/media_router.dart';
import 'package:omnia_mobile/core/models/media_file.dart';
import 'package:omnia_mobile/core/models/media_type.dart';
import 'package:omnia_mobile/core/models/playback_state.dart';
import 'package:omnia_mobile/core/models/playback_status.dart';
import 'package:omnia_mobile/core/providers.dart';
import 'package:omnia_mobile/core/services/folder_scanner.dart';
import 'package:omnia_mobile/core/services/playback_service.dart';
import 'package:omnia_mobile/core/services/playlist_service.dart';
import 'package:omnia_mobile/core/services/window_service.dart';
import 'package:omnia_mobile/ui/osd/osd_controller.dart';
import 'package:omnia_mobile/ui/osd/osd_message.dart';

void main() {
  late PlayerCommandBus bus;
  late PlaylistService playlist;
  late PlaybackService service;
  late ProviderContainer container;

  /// Laisse le bus livrer ses événements et le service vider sa file.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  /// Simule le démarrage d'un extrait, comme le fait le service.
  void startRecording(String path) => service.update(
        (s) => s.copyWith(
          recordingPath: path,
          recordingStartedAt: DateTime.now(),
          recordingFailed: false,
          clearLastRecording: true,
        ),
      );

  setUp(() {
    bus = PlayerCommandBus();
    playlist = PlaylistService(bus: bus, scanner: FakeFolderScanner(const {}));
    service = PlaybackService(
      bus: bus,
      router: MediaRouter(const []),
      window: FakeWindowService(),
      playlist: playlist,
      recordingCheckDelay: Duration.zero,
      initialState: const PlaybackState(
        file: MediaFile(path: '/serie/ep2.mkv', type: MediaType.video),
        status: PlaybackStatus.playing,
        duration: Duration(minutes: 40),
        volume: 60,
      ),
    );
    container = ProviderContainer(
      overrides: [
        commandBusProvider.overrideWithValue(bus),
        playbackServiceProvider.overrideWithValue(service),
      ],
    );
    // Première lecture : le contrôleur se construit et s'abonne. La barre de
    // contrôles est visible (chromeProvider vaut vrai au départ).
    container.read(osdProvider);
  });

  tearDown(() async {
    container.dispose();
    await service.dispose();
    await playlist.dispose();
    await bus.dispose();
  });

  test('le volume à la souris s’annonce alors que la barre est visible', () async {
    bus.dispatch(const VolumeRelative(5));
    await settle();

    final message = container.read(osdProvider);
    expect(message, isA<OsdVolume>());
    expect((message! as OsdVolume).volume, 65);
  });

  test('une action ordinaire à la souris reste muette, barre visible', () async {
    bus.dispatch(const SpeedRelative(0.25));
    await settle();

    expect(container.read(osdProvider), isNull);
  });

  test('un extrait enregistré s’annonce avec son chemin', () async {
    startRecording('/omnia/extrait.mkv');
    await settle();
    service.update(
      (s) => s.copyWith(clearRecording: true, lastRecording: '/omnia/extrait.mkv'),
    );
    await settle();

    final message = container.read(osdProvider);
    expect(message, isA<OsdRecordingSaved>());
    final saved = message! as OsdRecordingSaved;
    expect(saved.path, '/omnia/extrait.mkv');
    expect(saved.length, isNotNull);
  });

  test('un extrait qui n’écrit rien s’annonce comme un échec', () async {
    startRecording('/omnia/vide.mkv');
    await settle();
    service.update(
      (s) => s.copyWith(
        clearRecording: true,
        clearLastRecording: true,
        recordingFailed: true,
      ),
    );
    await settle();

    expect(container.read(osdProvider), isA<OsdRecordingFailed>());
  });

  test('un extrait arrêté sans fichier s’annonce même sans drapeau', () async {
    startRecording('/omnia/rien.mkv');
    await settle();
    service.update((s) => s.copyWith(clearRecording: true, clearLastRecording: true));
    await settle();

    expect(container.read(osdProvider), isA<OsdRecordingFailed>());
  });

  test('un extrait impossible s’annonce encore au second appui', () async {
    // Première tentative impossible : la raison de l'échec est posée.
    service.update((s) => s.copyWith(recordingFailed: true));
    await settle();
    // Un autre message prend la place de la pastille.
    bus.dispatch(const VolumeRelative(5));
    await settle();
    expect(container.read(osdProvider), isA<OsdVolume>());

    // Second appui : l'état ne bouge plus (même échec, même raison), donc le
    // suivi d'état n'a aucun front à voir. Seule la commande peut répondre.
    bus.dispatch(const ToggleRecording());
    await settle();

    expect(container.read(osdProvider), isA<OsdRecordingFailed>());
  });

  test('une capture qui ne rend aucune image s’annonce comme un échec', () async {
    // Image annoncée, mais aucun contrôleur pour la capturer : le service
    // remet l'état à zéro et sort sans rien écrire. C'est un échec, et il doit
    // se lire à l'écran, barre visible comprise.
    service.update((s) => s.copyWith(hasVideo: true));
    await settle();
    bus.dispatch(const TakeScreenshot());
    await settle();

    expect(container.read(osdProvider), isA<OsdScreenshotFailed>());
  });

  test('un extrait qui ne démarre pas s’annonce comme un échec', () async {
    // Premier échec après un état sans reproche : l'indicateur REC ne s'allume
    // même pas, seul ce message dit qu'il s'est passé quelque chose.
    service.update((s) => s.copyWith(recordingFailed: false, clearLastRecording: true));
    await settle();
    service.update((s) => s.copyWith(recordingFailed: true));
    await settle();

    expect(container.read(osdProvider), isA<OsdRecordingFailed>());
  });
}
