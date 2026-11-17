import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/models/app_preferences.dart';
import 'package:omnia_mobile/core/models/history_entry.dart';
import 'package:omnia_mobile/core/models/media_type.dart';
import 'package:omnia_mobile/core/models/playback_state.dart';
import 'package:omnia_mobile/core/providers.dart';
import 'package:omnia_mobile/core/services/history_store.dart';
import 'package:omnia_mobile/core/services/media_library.dart';
import 'package:omnia_mobile/core/services/settings_store.dart';
import 'package:omnia_mobile/l10n/app_localizations.dart';
import 'package:omnia_mobile/ui/recent_files.dart';
import 'package:omnia_mobile/ui/screens/home_shell.dart';
import 'package:omnia_mobile/ui/theme/omnia_theme.dart';
import 'package:omnia_mobile/ui/widgets/omnia_connect_modal.dart';

class _NoPlayback extends PlaybackStateNotifier {
  @override
  PlaybackState build() => const PlaybackState();
}

class _Preferences extends PreferencesNotifier {
  @override
  AppPreferences build() => const AppPreferences();
}

class _Recents extends RecentFilesNotifier {
  @override
  List<RecentFile> build() => [
        RecentFile(
          entry: HistoryEntry(
            path: '/storage/emulated/0/Movies/vacances.mp4',
            position: const Duration(minutes: 12, seconds: 5),
            duration: const Duration(minutes: 40),
            lastOpened: DateTime.now(),
          ),
          exists: true,
        ),
      ];
}

/// Une bibliothèque qui rend des fichiers connus, sans toucher au système.
class _Library implements MediaLibrary {
  @override
  Future<List<LibraryFile>> recentlyAdded({int limit = 60}) async => [
        LibraryFile(
          path: '/storage/emulated/0/Download/rapport.pdf',
          name: 'rapport.pdf',
          size: 2400000,
          added: DateTime.now(),
        ),
      ];

  @override
  Future<Uint8List?> thumbnail(String path, MediaType type, {int size = 320}) async =>
      null;
}

Future<void> _mount(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        historyStoreProvider.overrideWithValue(MemoryHistoryStore()),
        settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
        playbackStateProvider.overrideWith(_NoPlayback.new),
        preferencesProvider.overrideWith(_Preferences.new),
        recentFilesProvider.overrideWith(_Recents.new),
        mediaLibraryProvider.overrideWithValue(_Library()),
      ],
      child: MaterialApp(
        theme: buildOmniaTheme(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('fr'),
        home: const HomeShell(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group("L'accueil", () {
    testWidgets('quatre onglets en bas, et le menu à trois points en haut', (tester) async {
      await _mount(tester);

      expect(find.text('OMNIA'), findsOneWidget);
      expect(find.text('Accueil'), findsOneWidget);
      expect(find.text('Dossiers'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Paramètres'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-menu')), findsOneWidget);

      // Les deux gros boutons d'ouverture ont quitté l'accueil : ils sont
      // rangés dans le menu.
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.tap(find.byKey(const ValueKey('home-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Ouvrir un fichier'), findsOneWidget);
      expect(find.text('Ouvrir un dossier'), findsOneWidget);
      expect(find.text("Rotation de l'écran"), findsOneWidget);
      // Rien d'ouvert, aucun PC relié : rien à projeter.
      expect(find.text('Actualiser la projection'), findsNothing);
    });

    testWidgets('ajoutés récemment et ouverts récemment, sans chemin affiché', (tester) async {
      await _mount(tester);

      expect(find.text('AJOUTÉS RÉCEMMENT'), findsOneWidget);
      expect(find.text('Tout afficher'), findsOneWidget);
      expect(find.text('rapport.pdf'), findsOneWidget);

      expect(find.text('OUVERTS RÉCEMMENT'), findsOneWidget);
      expect(find.text('vacances.mp4'), findsOneWidget);
      // Où on en était, et non plus le chemin du fichier : celui-ci est
      // rangé dans le menu du fichier.
      expect(find.text('Reprise à 12:05 sur 40:00'), findsOneWidget);
      expect(find.textContaining('/storage/emulated/0'), findsNothing);

      // La bannière vers la version bureau reste là.
      expect(find.text('Découvrez OMNIA pour PC'), findsOneWidget);
    });

    testWidgets("OMNIA Connect n'est construit qu'une fois son onglet ouvert", (tester) async {
      // Le construire démarre le serveur d'appairage : il ne doit pas tourner
      // dès le lancement, à l'insu de l'utilisateur.
      await _mount(tester);
      expect(find.byType(OmniaConnectModal), findsNothing);

      await tester.tap(find.text('Dossiers'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Stockages du téléphone'), findsOneWidget);
      expect(find.text('Mémoire interne'), findsOneWidget);
      expect(find.byType(OmniaConnectModal), findsNothing);
    });
  });
}
