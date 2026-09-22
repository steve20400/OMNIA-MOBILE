import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/commands/player_command_bus.dart';
import 'package:omnia_mobile/core/controllers/media_router.dart';
import 'package:omnia_mobile/core/providers.dart';
import 'package:omnia_mobile/core/services/folder_scanner.dart';
import 'package:omnia_mobile/core/services/history_store.dart';
import 'package:omnia_mobile/core/services/local_storage.dart';
import 'package:omnia_mobile/core/services/playback_service.dart';
import 'package:omnia_mobile/core/services/playlist_service.dart';
import 'package:omnia_mobile/core/services/settings_store.dart';
import 'package:omnia_mobile/core/services/window_service.dart';
import 'package:omnia_mobile/l10n/app_localizations.dart';
import 'package:omnia_mobile/ui/settings/settings_controller.dart';
import 'package:omnia_mobile/ui/settings/settings_screen.dart';
import 'package:omnia_mobile/ui/theme/omnia_theme.dart';

class _FakeWindowService implements WindowService {
  @override
  bool get isFullscreen => false;
  @override
  bool get isMiniPlayer => false;
  @override
  bool get isAlwaysOnTop => false;
  @override
  void enterFullscreen() {}
  @override
  void exitFullscreen() {}
  @override
  void toggleFullscreen() {}
  @override
  void enterMiniPlayer() {}
  @override
  void exitMiniPlayer() {}
  @override
  void toggleMiniPlayer() {}
  @override
  void setAlwaysOnTop(bool value) {}
  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('SettingsOverlay shows Wireless and Network sections', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final bus = PlayerCommandBus();
    final storage = MemoryLocalStorage();
    final store = SettingsStore(storage: storage);
    await store.init();
    final history = HistoryStore(storage: storage);
    await history.init();
    final playlist = PlaylistService(
      bus: bus,
      scanner: FakeFolderScanner(const {}),
      history: history,
      settings: store,
    );
    final service = PlaybackService(
      bus: bus,
      router: MediaRouter(const []),
      window: _FakeWindowService(),
      playlist: playlist,
      history: history,
      settings: store,
    );

    final container = ProviderContainer(
      overrides: [
        commandBusProvider.overrideWithValue(bus),
        settingsStoreProvider.overrideWithValue(store),
        historyStoreProvider.overrideWithValue(history),
        playbackServiceProvider.overrideWithValue(service),
        playlistServiceProvider.overrideWithValue(playlist),
      ],
    );

    container.read(settingsUiProvider.notifier).show(SettingsSection.connect);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildOmniaTheme(Brightness.dark),
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Material(child: SettingsOverlay()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Section Connexions sans fil
    expect(find.text('Connexions sans fil'), findsWidgets);
    expect(find.text('OMNIA Connect local'), findsOneWidget);
    expect(find.text('Mode de liaison'), findsOneWidget);
    expect(find.text('Contrôle à distance'), findsOneWidget);
    expect(find.text('Diffusion locale (Streaming)'), findsOneWidget);

    // Section Réseau & Mises à jour
    container.read(settingsUiProvider.notifier).select(SettingsSection.network);
    await tester.pumpAndSettle();

    expect(find.text('Réseau & Mises à jour'), findsWidgets);
    expect(find.text('Version de l\'application'), findsOneWidget);
    expect(find.text('Canal de mise à jour'), findsOneWidget);

    container.dispose();
    await service.dispose();
    await playlist.dispose();
    await bus.dispose();
  });
}
