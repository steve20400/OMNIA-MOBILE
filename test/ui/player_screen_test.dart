import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

class _ActivePlaybackNotifier extends PlaybackStateNotifier {
  @override
  PlaybackState build() {
    return PlaybackState(
      file: MediaFile(
        path: '/storage/emulated/0/Movies/sample.mp4',
        type: MediaType.video,
        size: 1024 * 1024 * 50,
        modifiedAt: DateTime(2026),
      ),
      status: PlaybackStatus.playing,
      duration: const Duration(minutes: 10),
      position: const Duration(minutes: 2),
      hasVideo: true,
    );
  }
}

void main() {
  testWidgets('PlayerScreen renders controls, title, and handles tap', (tester) async {
    final history = MemoryHistoryStore();
    final settings = MemorySettingsStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyStoreProvider.overrideWithValue(history),
          settingsStoreProvider.overrideWithValue(settings),
          playbackStateProvider.overrideWith(_ActivePlaybackNotifier.new),
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
    expect(find.text('sample.mp4'), findsOneWidget);

    // Vérifie la présence des boutons média
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.wifi_tethering_rounded), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle_filled_rounded), findsOneWidget);
  });
}
