import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/models/app_preferences.dart';
import 'package:omnia_mobile/core/models/playback_state.dart';
import 'package:omnia_mobile/core/models/playlist_state.dart';
import 'package:omnia_mobile/core/providers.dart';
import 'package:omnia_mobile/core/services/history_store.dart';
import 'package:omnia_mobile/core/services/settings_store.dart';
import 'package:omnia_mobile/l10n/app_localizations.dart';
import 'package:omnia_mobile/ui/osd/osd_controller.dart';
import 'package:omnia_mobile/ui/osd/osd_message.dart';
import 'package:omnia_mobile/ui/recent_files.dart';
import 'package:omnia_mobile/ui/screens/player_screen.dart';
import 'package:omnia_mobile/ui/theme/omnia_theme.dart';
import 'package:omnia_mobile/ui/widgets/stage.dart';

/// Un contrôleur d'affichage qu'on pilote à la main : le vrai observe le bus
/// et le service, dont ce test n'a pas besoin.
class _Osd extends OsdController {
  @override
  OsdMessage? build() => null;

  void pousser(OsdMessage message) => state = message;
}

class _Preferences extends PreferencesNotifier {
  @override
  AppPreferences build() => const AppPreferences();
}

class _NoPlayback extends PlaybackStateNotifier {
  @override
  PlaybackState build() => const PlaybackState();
}

class _NoPlaylist extends PlaylistStateNotifier {
  @override
  PlaylistState build() => PlaylistState();
}

class _NoRecents extends RecentFilesNotifier {
  @override
  List<RecentFile> build() => const [];
}

/// Monte l'écran du lecteur et y annonce un mini-lecteur refusé.
///
/// [pip] décide ce que l'appareil répond : c'est toute la différence entre un
/// refus qu'on peut lever et un refus qu'on ne peut que dire.
Future<void> _refuser(WidgetTester tester, {required bool pip}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dev.omnia.mobile/pip'),
    (call) async {
      if (call.method == 'windowCapabilities') {
        return <String, Object?>{'pip': pip, 'overlay': false};
      }
      return null;
    },
  );
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.omnia.mobile/pip'),
      null,
    ),
  );

  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      historyStoreProvider.overrideWithValue(MemoryHistoryStore()),
      settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
      preferencesProvider.overrideWith(_Preferences.new),
      playbackStateProvider.overrideWith(_NoPlayback.new),
      playlistStateProvider.overrideWith(_NoPlaylist.new),
      recentFilesProvider.overrideWith(_NoRecents.new),
      osdProvider.overrideWith(_Osd.new),
      videoSurfaceProvider.overrideWithValue(
        (context, {required fit, aspectRatio}) => const ColoredBox(color: Colors.black),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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

  (container.read(osdProvider.notifier) as _Osd)
      .pousser(const OsdMiniPlayerUnavailable());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('Mini-lecteur refusé', () {
    testWidgets("l'appareil a l'image dans l'image : le refus est annoncé",
        (tester) async {
      // Le défaut corrigé à l'origine : l'affichage à l'écran partagé n'est
      // pas monté sur mobile, et le refus se taisait. L'utilisateur voyait un
      // bouton mort. Ici l'autorisation se donne ailleurs, dans une page que
      // seul le système peut ouvrir : il n'y a rien à proposer, juste à dire.
      await _refuser(tester, pip: true);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets("l'appareil n'a que la fenêtre superposée : elle est proposée",
        (tester) async {
      // Le défaut corrigé ici : sur un appareil sans image dans l'image, le
      // mini-lecteur passe par une fenêtre superposée, dont l'autorisation
      // est désactivée par défaut. Un message disait ce qui manquait sans
      // dire où l'accorder — il fallait le deviner et fouiller les réglages.
      await _refuser(tester, pip: false);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Autoriser'), findsOneWidget);
    });
  });
}
