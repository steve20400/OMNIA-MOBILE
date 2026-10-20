import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/commands/player_command.dart';
import 'package:omnia_mobile/core/commands/player_command_bus.dart';
import 'package:omnia_mobile/core/models/app_preferences.dart';
import 'package:omnia_mobile/core/models/playback_state.dart';
import 'package:omnia_mobile/core/models/playlist_state.dart';
import 'package:omnia_mobile/core/providers.dart';
import 'package:omnia_mobile/core/services/history_store.dart';
import 'package:omnia_mobile/core/services/settings_store.dart';
import 'package:omnia_mobile/l10n/app_localizations.dart';
import 'package:omnia_mobile/ui/recent_files.dart';
import 'package:omnia_mobile/ui/screens/player_screen.dart';
import 'package:omnia_mobile/ui/theme/omnia_theme.dart';
import 'package:omnia_mobile/ui/widgets/stage.dart';

class _Preferences extends PreferencesNotifier {
  _Preferences(this.value);

  final AppPreferences value;

  @override
  AppPreferences build() => value;
}

class _NoPlayback extends PlaybackStateNotifier {
  @override
  PlaybackState build() => const PlaybackState();
}

/// L'écran d'accueil liste les récents, et cette liste réclamerait le moteur
/// de lecture, absent d'un test.
class _NoRecents extends RecentFilesNotifier {
  @override
  List<RecentFile> build() => const [];
}

class _NoPlaylist extends PlaylistStateNotifier {
  @override
  PlaylistState build() => PlaylistState();
}

void main() {
  late Directory dir;
  late String chemin;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('omnia_session_');
    chemin = '${dir.path}${Platform.pathSeparator}ep1.mkv';
    File(chemin).writeAsStringSync('film');
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Rien à faire : le dossier temporaire partira avec le système.
    }
  });

  /// Monte l'écran et rend les commandes passées par le bus.
  Future<List<PlayerCommand>> monter(
    WidgetTester tester, {
    String? lastOpenPath,
    AppPreferences prefs = const AppPreferences(),
    String? initialFile,
  }) async {
    final bus = PlayerCommandBus();
    final vues = <PlayerCommand>[];
    final abonnement = bus.commands.listen(vues.add);
    addTearDown(() async {
      await abonnement.cancel();
      await bus.dispose();
    });

    // Le canal natif n'existe pas en test : sans ce faux, ses appels ne
    // rendent jamais la main et la restauration ne se produit pas du tout.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.omnia.mobile/intent'),
      (call) async => null,
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.omnia.mobile/intent'),
        null,
      ),
    );

    final settings = MemorySettingsStore();
    if (lastOpenPath != null) await settings.setLastOpenPath(lastOpenPath);

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          commandBusProvider.overrideWithValue(bus),
          historyStoreProvider.overrideWithValue(MemoryHistoryStore()),
          settingsStoreProvider.overrideWithValue(settings),
          preferencesProvider.overrideWith(() => _Preferences(prefs)),
          playbackStateProvider.overrideWith(_NoPlayback.new),
          playlistStateProvider.overrideWith(_NoPlaylist.new),
          recentFilesProvider.overrideWith(_NoRecents.new),
          videoSurfaceProvider.overrideWithValue(
            (context, {required fit, aspectRatio}) => const ColoredBox(color: Colors.black),
          ),
        ],
        child: MaterialApp(
          theme: buildOmniaTheme(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('fr'),
          home: PlayerScreen(initialFile: initialFile),
        ),
      ),
    );

    // Le canal natif n'existe pas en test : son échec est attendu, et c'est
    // justement après lui que la restauration doit se produire.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    return vues;
  }

  List<String> ouvertures(List<PlayerCommand> vues) =>
      vues.whereType<OpenFile>().map((c) => c.path).toList();

  group('Reprise de la dernière session', () {
    testWidgets('le fichier de la session précédente est rouvert', (tester) async {
      // Le symptôme rapporté : Android tue le lecteur laissé en arrière-plan,
      // et au retour OMNIA repartait de l'écran d'accueil.
      final vues = await monter(tester, lastOpenPath: chemin);
      expect(ouvertures(vues), [chemin]);
    });

    testWidgets('la préférence désactivée ne restaure rien', (tester) async {
      final vues = await monter(
        tester,
        lastOpenPath: chemin,
        prefs: const AppPreferences(restoreLastSession: false),
      );
      expect(ouvertures(vues), isEmpty);
    });

    testWidgets('un fichier disparu depuis la dernière fois est ignoré', (tester) async {
      final vues = await monter(
        tester,
        lastOpenPath: '${dir.path}${Platform.pathSeparator}efface.mkv',
      );
      expect(ouvertures(vues), isEmpty);
    });

    testWidgets("un URI de partage n'est pas rouvert", (tester) async {
      // L'autorisation d'un content:// ne survit pas à la fermeture : le
      // rouvrir échouerait, et la vérification d'existence l'écarte.
      final vues = await monter(
        tester,
        lastOpenPath: 'content://com.android.providers.media.documents/document/video%3A42',
      );
      expect(ouvertures(vues), isEmpty);
    });

    testWidgets('un fichier passé au lancement garde la priorité', (tester) async {
      final vues = await monter(tester, lastOpenPath: chemin, initialFile: '/autre/film.mkv');
      // Un seul fichier ouvert, et c'est celui du lancement : la session
      // précédente ne doit pas se poser par-dessus.
      expect(ouvertures(vues), ['/autre/film.mkv']);
    });

    testWidgets('aucune session enregistrée : rien ne se passe', (tester) async {
      final vues = await monter(tester);
      expect(ouvertures(vues), isEmpty);
    });
  });
}
