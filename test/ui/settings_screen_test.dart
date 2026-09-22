import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/commands/player_command_bus.dart';
import 'package:omnia_mobile/core/models/app_preferences.dart';
import 'package:omnia_mobile/core/providers.dart';
import 'package:omnia_mobile/core/services/history_store.dart';
import 'package:omnia_mobile/core/services/mobile_window_service.dart';
import 'package:omnia_mobile/core/services/settings_store.dart';
import 'package:omnia_mobile/l10n/app_localizations.dart';
import 'package:omnia_mobile/ui/settings/settings_controller.dart';
import 'package:omnia_mobile/ui/settings/settings_screen.dart';
import 'package:omnia_mobile/ui/theme/omnia_theme.dart';

class _CustomPreferencesNotifier extends PreferencesNotifier {
  _CustomPreferencesNotifier(this._initial);
  final AppPreferences _initial;

  @override
  AppPreferences build() => _initial;
}

void main() {
  testWidgets('SettingsOverlay shows Wireless and Network sections', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final bus = PlayerCommandBus();
    final settings = MemorySettingsStore();
    final history = MemoryHistoryStore();
    final window = MobileWindowService();

    final container = ProviderContainer(
      overrides: [
        commandBusProvider.overrideWithValue(bus),
        settingsStoreProvider.overrideWithValue(settings),
        historyStoreProvider.overrideWithValue(history),
        windowServiceProvider.overrideWithValue(window),
        preferencesProvider.overrideWith(
          () => _CustomPreferencesNotifier(const AppPreferences()),
        ),
      ],
    );

    container.read(settingsUiProvider.notifier).show(SettingsSection.connect);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildOmniaTheme(Brightness.dark),
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Material(child: SettingsOverlay()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Section Connexions sans fil
    expect(find.text('Connexions sans fil'), findsWidgets);
    expect(find.text('OMNIA Connect local'), findsOneWidget);
    expect(find.text('Mode de liaison'), findsOneWidget);
    expect(find.text('Contrôle à distance'), findsOneWidget);
    expect(find.text('Diffusion locale (Streaming)'), findsOneWidget);
    expect(find.text('Suggérer la version Bureau (PC)'), findsOneWidget);

    // Section Réseau & Mises à jour
    container.read(settingsUiProvider.notifier).select(SettingsSection.network);
    await tester.pumpAndSettle();

    expect(find.text('Réseau & Mises à jour'), findsWidgets);
    expect(find.text('Version de l\'application'), findsOneWidget);
    expect(find.text('Canal de mise à jour'), findsOneWidget);

    container.dispose();
    await window.dispose();
    await bus.dispose();
  });
}
