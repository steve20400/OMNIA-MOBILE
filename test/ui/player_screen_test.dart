import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/models/app_preferences.dart';
import 'package:omnia_mobile/core/models/media_file.dart';
import 'package:omnia_mobile/core/models/media_type.dart';
import 'package:omnia_mobile/core/models/playback_state.dart';
import 'package:omnia_mobile/core/models/playback_status.dart';
import 'package:omnia_mobile/core/models/playlist_entry.dart';
import 'package:omnia_mobile/core/models/playlist_state.dart';
import 'package:omnia_mobile/core/providers.dart';
import 'package:omnia_mobile/core/services/history_store.dart';
import 'package:omnia_mobile/core/services/settings_store.dart';
import 'package:omnia_mobile/l10n/app_localizations.dart';
import 'package:omnia_mobile/ui/screens/player_screen.dart';
import 'package:omnia_mobile/ui/theme/omnia_theme.dart';
import 'package:omnia_mobile/ui/widgets/mobile_bottom_playlist.dart';
import 'package:omnia_mobile/ui/widgets/side_panel.dart';
import 'package:omnia_mobile/ui/widgets/stage.dart';

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

class _StaticPlaylistNotifier extends PlaylistStateNotifier {
  @override
  PlaylistState build() => PlaylistState(
        folder: '/storage/emulated/0/Documents',
        entries: const [
          PlaylistEntry(
            file: MediaFile(
              path: '/storage/emulated/0/Documents/notes.txt',
              type: MediaType.text,
            ),
          ),
          PlaylistEntry(
            file: MediaFile(
              path: '/storage/emulated/0/Documents/doc.pdf',
              type: MediaType.pdf,
            ),
          ),
        ],
        currentPath: '/storage/emulated/0/Documents/notes.txt',
      );
}

void main() {
  testWidgets('PlayerScreen renders controls, title, rotation, playlist, lock toggle and handles tap', (tester) async {
    final history = MemoryHistoryStore();
    final settings = MemorySettingsStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyStoreProvider.overrideWithValue(history),
          settingsStoreProvider.overrideWithValue(settings),
          playbackStateProvider.overrideWith(_DocumentPlaybackNotifier.new),
          preferencesProvider.overrideWith(_StaticPreferencesNotifier.new),
          playlistStateProvider.overrideWith(_StaticPlaylistNotifier.new),
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

    // Affichage initial sans laisser expirer le timer de masquage
    await tester.pump();

    // Vérifie le nom du fichier
    expect(find.text('notes.txt'), findsOneWidget);

    // Vérifie la présence des boutons média, OMNIA Connect, Verrouillage, Rotation et Playlist
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.wifi_tethering_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.screen_rotation_rounded), findsOneWidget);
    expect(find.byIcon(Icons.playlist_play_rounded), findsWidgets);

    // Teste la rotation d'écran en cliquant sur le bouton de rotation
    await tester.tap(find.byIcon(Icons.screen_rotation_rounded));
    await tester.pump(const Duration(milliseconds: 400));

    // Teste l'ouverture de la barre de playlist en portrait (MobileBottomPlaylist en dessous)
    await tester.tap(find.byIcon(Icons.playlist_play_rounded).first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MobileBottomPlaylist), findsOneWidget);

    // Ferme la playlist
    await tester.tap(find.byIcon(Icons.playlist_play_rounded).first);
    await tester.pump(const Duration(milliseconds: 400));

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

  testWidgets('PlayerScreen in landscape displays SidePanel on the left when opened', (tester) async {
    tester.view.physicalSize = const Size(1280, 720); // Mode paysage couché
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final history = MemoryHistoryStore();
    final settings = MemorySettingsStore();
    await settings.setSidePanelVisible(true); // Ouvert d'emblée

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyStoreProvider.overrideWithValue(history),
          settingsStoreProvider.overrideWithValue(settings),
          playbackStateProvider.overrideWith(_DocumentPlaybackNotifier.new),
          preferencesProvider.overrideWith(_StaticPreferencesNotifier.new),
          playlistStateProvider.overrideWith(_StaticPlaylistNotifier.new),
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

    await tester.pump();

    // En mode paysage (couché), le panneau latéral est présent (à gauche)
    expect(find.byType(SidePanel), findsOneWidget);
    expect(find.byType(MobileBottomPlaylist), findsNothing);

    await tester.pump(const Duration(seconds: 5));
  });
}
