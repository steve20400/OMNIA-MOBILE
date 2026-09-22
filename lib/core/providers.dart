import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'commands/player_command.dart';
import 'commands/player_command_bus.dart';
import 'controllers/av_controller.dart';
import 'controllers/image_controller.dart';
import 'controllers/media_router.dart';
import 'controllers/pdf_controller.dart';
import 'controllers/text_controller.dart';
import 'models/app_preferences.dart';
import 'models/playback_state.dart';
import 'models/playlist_state.dart';
import 'services/audio_metadata_service.dart';
import 'services/folder_scanner.dart';
import 'services/history_store.dart';
import 'services/mobile_window_service.dart';
import 'services/playback_service.dart';
import 'services/playlist_service.dart';
import 'services/screen_wake.dart';
import 'services/screenshot_service.dart';
import 'services/settings_store.dart';
import 'services/system_integration.dart';
import 'services/window_service.dart';

/// Arguments de lancement éventuels.
final launchArgumentsProvider = Provider<List<String>>((_) => const []);

/// Préférences persistantes (Hive). Surchargé dans `main()`.
final settingsStoreProvider = Provider<SettingsStore>(
  (_) => throw UnimplementedError('settingsStoreProvider doit être surchargé'),
);

/// Historique et positions de lecture. Surchargé dans `main()`.
final historyStoreProvider = Provider<HistoryStore>(
  (_) => throw UnimplementedError('historyStoreProvider doit être surchargé'),
);

final commandBusProvider = Provider<PlayerCommandBus>((ref) {
  final bus = PlayerCommandBus();
  ref.onDispose(bus.dispose);
  return bus;
});

final windowServiceProvider = Provider<WindowService>((ref) {
  final service = MobileWindowService();
  ref.onDispose(service.dispose);
  return service;
});

final systemIntegrationProvider =
    Provider<SystemIntegration>((_) => const NoopSystemIntegration());

final folderScannerProvider =
    Provider<FolderScanner>((_) => const IsolateFolderScanner());

final screenWakeProvider = Provider<ScreenWake>((_) => const WakelockScreenWake());

final screenshotServiceProvider = Provider<ScreenshotService>(
  (ref) => ScreenshotService(settings: ref.watch(settingsStoreProvider)),
);

final audioMetadataServiceProvider =
    Provider<AudioMetadataService>((_) => const IsolateAudioMetadataService());

final avControllerProvider = Provider<AvController>((ref) {
  final settings = ref.watch(settingsStoreProvider);
  final controller = AvController(preferences: () => settings.preferences);
  ref.onDispose(controller.dispose);
  return controller;
});

final videoControllerProvider =
    Provider<VideoController>((ref) => ref.watch(avControllerProvider).videoController);

final textControllerProvider = Provider<TextController>((ref) {
  final settings = ref.watch(settingsStoreProvider);
  final controller = TextController(preferences: () => settings.preferences);
  ref.onDispose(controller.dispose);
  return controller;
});

final pdfControllerProvider = Provider<PdfController>((ref) {
  final controller = PdfController();
  ref.onDispose(controller.dispose);
  return controller;
});

final imageControllerProvider = Provider<ImageController>((ref) {
  final controller = ImageController();
  ref.onDispose(controller.dispose);
  return controller;
});

final mediaRouterProvider = Provider<MediaRouter>(
  (ref) => MediaRouter([
    ref.watch(avControllerProvider),
    ref.watch(textControllerProvider),
    ref.watch(pdfControllerProvider),
    ref.watch(imageControllerProvider),
  ]),
);

final playlistServiceProvider = Provider<PlaylistService>((ref) {
  final router = ref.watch(mediaRouterProvider);
  final service = PlaylistService(
    bus: ref.watch(commandBusProvider),
    scanner: ref.watch(folderScannerProvider),
    history: ref.watch(historyStoreProvider),
    settings: ref.watch(settingsStoreProvider),
    isPlayable: (path) => router.controllerForPath(path) != null,
  );
  ref.onDispose(service.dispose);
  return service;
});

final playbackServiceProvider = Provider<PlaybackService>((ref) {
  final service = PlaybackService(
    bus: ref.watch(commandBusProvider),
    router: ref.watch(mediaRouterProvider),
    window: ref.watch(windowServiceProvider),
    playlist: ref.watch(playlistServiceProvider),
    history: ref.watch(historyStoreProvider),
    settings: ref.watch(settingsStoreProvider),
    screenshots: ref.watch(screenshotServiceProvider),
    system: ref.watch(systemIntegrationProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final playbackStateProvider =
    NotifierProvider<PlaybackStateNotifier, PlaybackState>(PlaybackStateNotifier.new);

class PlaybackStateNotifier extends Notifier<PlaybackState> {
  @override
  PlaybackState build() {
    final service = ref.watch(playbackServiceProvider);
    final sub = service.stream.listen((s) => state = s);
    ref.onDispose(sub.cancel);
    return service.state;
  }
}

final preferencesProvider =
    NotifierProvider<PreferencesNotifier, AppPreferences>(PreferencesNotifier.new);

class PreferencesNotifier extends Notifier<AppPreferences> {
  @override
  AppPreferences build() {
    final service = ref.watch(playbackServiceProvider);
    final sub = service.preferencesChanges.listen((p) => state = p);
    ref.onDispose(sub.cancel);
    return service.preferences;
  }
}

final playlistStateProvider =
    NotifierProvider<PlaylistStateNotifier, PlaylistState>(PlaylistStateNotifier.new);

class PlaylistStateNotifier extends Notifier<PlaylistState> {
  @override
  PlaylistState build() {
    ref.watch(playbackServiceProvider);
    final service = ref.watch(playlistServiceProvider);
    final sub = service.stream.listen((s) => state = s);
    ref.onDispose(sub.cancel);
    return service.state;
  }
}

extension DispatchX on WidgetRef {
  void dispatch(PlayerCommand command, {CommandSource source = CommandSource.ui}) {
    read(commandBusProvider).dispatch(command, source: source);
  }
}
