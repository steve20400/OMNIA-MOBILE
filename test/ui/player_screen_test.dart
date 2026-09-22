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

    // Affichage initial sans laisser expirer le timer de masquage
    await tester.pump();

    // Vérifie le nom du fichier
    expect(find.text('notes.txt'), findsOneWidget);

    // Vérifie la présence des boutons média, OMNIA Connect et Verrouillage
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.wifi_tethering_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);

    // Verrouille l'écran via le bouton cadenas
    await tester.tap(find.byIcon(Icons.lock_outline_rounded));
    // Attend la résolution du délai de double-tap (300ms)
    await tester.pump(const Duration(milliseconds: 400));

    // La pastille de déverrouillage apparaît
    expect(find.text('Déverrouiller l’écran'), findsOneWidget);

    // Un tap sur la pastille déverrouille l'écran
    await tester.tap(find.text('Déverrouiller l’écran'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Déverrouiller l’écran'), findsNothing);

    // Écoulement propre de tous les timers en attente
    await tester.pump(const Duration(seconds: 5));
  });
}
