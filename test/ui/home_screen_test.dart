import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/models/playback_state.dart';
import 'package:omnia_mobile/core/providers.dart';
import 'package:omnia_mobile/core/services/history_store.dart';
import 'package:omnia_mobile/core/services/settings_store.dart';
import 'package:omnia_mobile/l10n/app_localizations.dart';
import 'package:omnia_mobile/ui/screens/home_screen.dart';
import 'package:omnia_mobile/ui/theme/omnia_theme.dart';

void main() {
  testWidgets('HomeScreen renders OMNIA branding, filter chips, and empty state', (tester) async {
    final history = MemoryHistoryStore();
    final settings = MemorySettingsStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyStoreProvider.overrideWithValue(history),
          settingsStoreProvider.overrideWithValue(settings),
          playbackStateProvider.overrideWith((ref) => const PlaybackState()),
        ],
        child: MaterialApp(
          theme: buildOmniaTheme(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('fr'),
          home: const HomeScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Vérifie la présence du logo/titre OMNIA
    expect(find.text('OMNIA'), findsOneWidget);

    // Vérifie les puces de filtrage
    expect(find.text('Tous'), findsOneWidget);
    expect(find.text('Vidéos'), findsOneWidget);
    expect(find.text('Audios'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Images'), findsOneWidget);

    // Vérifie l'état vide initial
    expect(find.byIcon(Icons.folder_open_rounded), findsOneWidget);
  });
}
