import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'core/providers.dart';
import 'core/services/history_store.dart';
import 'core/services/local_storage.dart';
import 'core/services/settings_store.dart';
import 'l10n/app_localizations.dart';
import 'ui/app_close.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/omnia_theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Mode edge-to-edge moderne sous Android & iOS
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialisation du stockage local persistant (Hive)
  SettingsStore settings;
  HistoryStore history;
  try {
    await initialiseLocalStorage();
    final dataDir = await localStorageDirectory();
    settings = await HiveSettingsStore.open();
    history = await HiveHistoryStore.open(dataDirectory: dataDir);
  } catch (_) {
    settings = MemorySettingsStore();
    history = MemoryHistoryStore();
  }

  runApp(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(settings),
        historyStoreProvider.overrideWithValue(history),
        launchArgumentsProvider.overrideWithValue(args),
      ],
      child: const OmniaMobileApp(),
    ),
  );
}

/// Racine de l'application OMNIA Mobile.
class OmniaMobileApp extends ConsumerWidget {
  const OmniaMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'OMNIA',
      debugShowCheckedModeBanner: false,
      theme: buildOmniaTheme(Brightness.dark),
      darkTheme: buildOmniaTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomeScreen(),
    );
  }
}
