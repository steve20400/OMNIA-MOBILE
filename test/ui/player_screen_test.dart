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

class _MiniDocumentPlaybackNotifier extends PlaybackStateNotifier {
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
      miniPlayer: true,
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
    tester.view.physicalSize = const Size(400, 800); // Mode portrait debout (largeur < hauteur)
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

    // Vérifie la présence du bouton retour et de la languette latérale PanelEdgeTab
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byType(PanelEdgeTab), findsOneWidget);

    // Teste l'ouverture de la barre de playlist en portrait via PanelEdgeTab (MobileBottomPlaylist en dessous)
    await tester.tap(find.byType(PanelEdgeTab));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MobileBottomPlaylist), findsOneWidget);

    // Ferme la playlist via le bouton de repli
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MobileBottomPlaylist), findsNothing);

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

  testWidgets('PlayerScreen in mini-player mode displays MobileBottomPlaylist on the bottom even in landscape', (tester) async {
    tester.view.physicalSize = const Size(800, 450); // Mode paysage couché
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
          playbackStateProvider.overrideWith(_MiniDocumentPlaybackNotifier.new),
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

    // En mode mini-lecteur, la liste est TOUJOURS en dessous (MobileBottomPlaylist) même en paysage
    expect(find.byType(MobileBottomPlaylist), findsOneWidget);
    expect(find.byType(SidePanel), findsNothing);

    await tester.pump(const Duration(seconds: 5));
  });
}
