import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/commands/player_command.dart';
import 'package:omnia_mobile/core/commands/player_command_bus.dart';
import 'package:omnia_mobile/core/models/app_preferences.dart';
import 'package:omnia_mobile/core/models/media_file.dart';
import 'package:omnia_mobile/core/models/media_type.dart';
import 'package:omnia_mobile/core/models/playback_state.dart';
import 'package:omnia_mobile/core/models/playback_status.dart';
import 'package:omnia_mobile/core/providers.dart';
import 'package:omnia_mobile/core/services/history_store.dart';
import 'package:omnia_mobile/core/services/settings_store.dart';
import 'package:omnia_mobile/l10n/app_localizations.dart';
import 'package:omnia_mobile/ui/screens/player_screen.dart';
import 'package:omnia_mobile/ui/theme/omnia_theme.dart';
import 'package:omnia_mobile/ui/widgets/stage.dart';

class _VideoPlaybackNotifier extends PlaybackStateNotifier {
  @override
  PlaybackState build() {
    return PlaybackState(
      file: MediaFile(
        path: '/storage/emulated/0/Movies/sample.mp4',
        type: MediaType.video,
        size: 1024 * 1024 * 15,
        modifiedAt: DateTime(2026),
      ),
      status: PlaybackStatus.playing,
      duration: const Duration(minutes: 10),
      position: const Duration(minutes: 2),
      speed: 1.0,
      hasVideo: true,
    );
  }
}

class _StaticPreferencesNotifier extends PreferencesNotifier {
  @override
  AppPreferences build() => const AppPreferences();
}

void main() {
  testWidgets('PlayerScreen lock button locks screen and displays unlock pill on tap', (tester) async {
    final history = MemoryHistoryStore();
    final settings = MemorySettingsStore();
    final bus = PlayerCommandBus();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyStoreProvider.overrideWithValue(history),
          settingsStoreProvider.overrideWithValue(settings),
          commandBusProvider.overrideWithValue(bus),
          playbackStateProvider.overrideWith(_VideoPlaybackNotifier.new),
          preferencesProvider.overrideWith(_StaticPreferencesNotifier.new),
          videoSurfaceProvider.overrideWithValue(
            (context, {required fit, aspectRatio}) => const ColoredBox(color: Colors.black),
          ),
        ],
        child: MaterialApp(
          theme: buildOmniaTheme(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('fr'),
          home: const PlayerScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verrouiller les gestes
    final lockBtn = find.byIcon(Icons.lock_outline_rounded);
    expect(lockBtn, findsOneWidget);
    await tester.tap(lockBtn);
    await tester.pumpAndSettle();

    // Vérifie l'apparition du bouton de déverrouillage
    expect(find.text('Déverrouiller l’écran'), findsOneWidget);

    // Déverrouille l'écran
    await tester.tap(find.text('Déverrouiller l’écran'));
    await tester.pumpAndSettle();

    // L'écran est déverrouillé
    expect(find.text('Déverrouiller l’écran'), findsNothing);
  });

  testWidgets('PlayerScreen long press triggers 2x speed boost', (tester) async {
    final history = MemoryHistoryStore();
    final settings = MemorySettingsStore();
    final bus = PlayerCommandBus();
    final List<PlayerCommand> dispatched = [];
    final sub = bus.commands.listen(dispatched.add);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyStoreProvider.overrideWithValue(history),
          settingsStoreProvider.overrideWithValue(settings),
          commandBusProvider.overrideWithValue(bus),
          playbackStateProvider.overrideWith(_VideoPlaybackNotifier.new),
          preferencesProvider.overrideWith(_StaticPreferencesNotifier.new),
          videoSurfaceProvider.overrideWithValue(
            (context, {required fit, aspectRatio}) => const ColoredBox(color: Colors.black),
          ),
        ],
        child: MaterialApp(
          theme: buildOmniaTheme(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('fr'),
          home: const PlayerScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Maintien prolongé sur l'écran (long press)
    final gesture = await tester.startGesture(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 600));

    // Vérifie l'apparition de l'indicateur 2x
    expect(find.text('2x Vitesse rapide'), findsOneWidget);

    // Relâchement du doigt
    await gesture.up();
    await tester.pumpAndSettle();

    // Vérifie la disparition de l'indicateur 2x
    expect(find.text('2x Vitesse rapide'), findsNothing);

    await sub.cancel();
    await bus.dispose();
  });
}
