import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

class _DocumentPlaybackNotifier extends PlaybackStateNotifier {
  @override
  PlaybackState build() {
    return PlaybackState(
      file: MediaFile(
        path: '/storage/emulated/0/Documents/notes.txt',
        type: MediaType.text,
        size: 1024 * 12,
        modifiedAt: DateTime(2026),
      ),
      status: PlaybackStatus.playing,
      duration: const Duration(minutes: 5),
      position: const Duration(minutes: 1),
      totalPages: 3,
      currentPage: 1,
    );
  }
}

class _StaticPreferencesNotifier extends PreferencesNotifier {
  @override
  AppPreferences build() => const AppPreferences();
}

void main() {
  testWidgets('PlayerScreen renders controls, title, lock toggle and handles tap', (tester) async {
    final history = MemoryHistoryStore();
    final settings = MemorySettingsStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyStoreProvider.overrideWithValue(history),
          settingsStoreProvider.overrideWithValue(settings),
          playbackStateProvider.overrideWith(_DocumentPlaybackNotifier.new),
          preferencesProvider.overrideWith(_StaticPreferencesNotifier.new),
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

    // Vérifie le nom du fichier
    expect(find.text('notes.txt'), findsOneWidget);

    // Vérifie la présence des boutons média, OMNIA Connect et Verrouillage
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.wifi_tethering_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);

    // Réaffiche les contrôles si masqués
    await tester.tap(find.byType(PlayerScreen));
    await tester.pump();

    // Verrouille l'écran via le bouton cadenas
    await tester.tap(find.byIcon(Icons.lock_outline_rounded));
    await tester.pump();

    // La pastille de déverrouillage apparaît
    expect(find.text('Déverrouiller l’écran'), findsOneWidget);

    // Un tap sur la pastille déverrouille l'écran
    await tester.tap(find.text('Déverrouiller l’écran'));
    await tester.pump();

    expect(find.text('Déverrouiller l’écran'), findsNothing);
  });
}
