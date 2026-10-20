import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/models/media_file.dart';
import 'package:omnia_mobile/core/models/media_type.dart';
import 'package:omnia_mobile/core/models/playback_state.dart';
import 'package:omnia_mobile/core/models/playback_status.dart';
import 'package:omnia_mobile/core/models/playlist_entry.dart';
import 'package:omnia_mobile/core/models/playlist_state.dart';
import 'package:omnia_mobile/core/providers.dart';
import 'package:omnia_mobile/core/services/settings_store.dart';
import 'package:omnia_mobile/l10n/app_localizations.dart';
import 'package:omnia_mobile/ui/theme/omnia_theme.dart';
import 'package:omnia_mobile/ui/widgets/mobile_bottom_playlist.dart';

/// Un écran de téléphone en portrait : ce que la scène et le tiroir se
/// partagent dans la plupart des tests.
const double _available = 800;

/// Une fenêtre de mini-lecteur en paysage — le seul cas où le tiroir du bas
/// apparaît hors du portrait, l'écran du lecteur posant sinon le panneau à
/// gauche.
const Size _miniWindow = Size(800, 450);

/// Un Picture-in-Picture : le cas le plus serré que la disposition rencontre.
const Size _pipWindow = Size(300, 170);

class _PlaybackNotifier extends PlaybackStateNotifier {
  @override
  PlaybackState build() => const PlaybackState(
        file: MediaFile(path: '/Films/ep02.mkv', type: MediaType.video),
        status: PlaybackStatus.playing,
      );
}

/// Un dossier ordinaire, scanné : le tiroir affiche la file d'attente.
class _FolderPlaylistNotifier extends PlaylistStateNotifier {
  @override
  PlaylistState build() => PlaylistState(
        folder: '/Films',
        entries: const [
          PlaylistEntry(file: MediaFile(path: '/Films/ep01.mkv', type: MediaType.video)),
          PlaylistEntry(file: MediaFile(path: '/Films/ep02.mkv', type: MediaType.video)),
          PlaylistEntry(file: MediaFile(path: '/Films/ep03.mkv', type: MediaType.video)),
        ],
        currentPath: '/Films/ep02.mkv',
      );
}

/// Un fichier reçu d'« Ouvrir avec » dont MediaStore ignore le dossier.
class _LoneSharePlaylistNotifier extends PlaylistStateNotifier {
  @override
  PlaylistState build() => PlaylistState(
        entries: const [
          PlaylistEntry(
            file: MediaFile(
              path: 'content://media/external/video/media/12',
              type: MediaType.video,
            ),
          ),
        ],
        currentPath: 'content://media/external/video/media/12',
        shared: true,
      );
}

Future<void> _pumpDrawer(
  WidgetTester tester, {
  required SettingsStore settings,
  Size window = const Size(400, _available),
  bool loneShare = false,
}) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final available = window.height;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(settings),
        playbackStateProvider.overrideWith(_PlaybackNotifier.new),
        playlistStateProvider.overrideWith(
          loneShare ? _LoneSharePlaylistNotifier.new : _FolderPlaylistNotifier.new,
        ),
      ],
      child: MaterialApp(
        theme: buildOmniaTheme(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('fr'),
        home: Scaffold(
          // Même disposition que l'écran du lecteur : la scène prend ce qui
          // reste au-dessus du tiroir.
          body: Column(
            children: [
              const Expanded(child: ColoredBox(color: Colors.black)),
              MobileBottomPlaylist(available: available),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

double _drawerHeight(WidgetTester tester) =>
    tester.getSize(find.byType(MobileBottomPlaylist)).height;

/// Saisit la poignée et la fait glisser de [dy] pixels (négatif = vers le haut).
Future<void> _dragGrip(WidgetTester tester, double dy) async {
  final gesture =
      await tester.startGesture(tester.getCenter(find.byKey(MobileBottomPlaylist.gripKey)));
  // Deux temps : le premier passe le seuil de reconnaissance du geste, le
  // second porte le déplacement utile.
  await gesture.moveBy(Offset(0, dy.sign * 40));
  await tester.pump();
  await gesture.moveBy(Offset(0, dy));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

void main() {
  group('Hauteur par défaut', () {
    testWidgets('le tiroir s’ouvre sur la moitié de l’écran, sans rien demander',
        (tester) async {
      await _pumpDrawer(tester, settings: MemorySettingsStore());

      // L'exigence de l'utilisateur, tenue dès l'installation : il ne doit pas
      // avoir à découvrir la poignée pour obtenir la moitié de l'écran.
      expect(_drawerHeight(tester), greaterThanOrEqualTo(_available / 2));
      expect(
        _drawerHeight(tester),
        _available * OmniaMetrics.playlistDrawerDefaultFraction,
      );
    });

    test('la moitié de l’écran est tenue sur toutes les tailles courantes', () {
      // Garde-fou : abaisser le défaut ferait réapparaître le tiroir d'un tiers
      // d'écran dont l'utilisateur se plaignait.
      for (final screen in <double>[640, 740, 800, 900, 1000, 1280]) {
        expect(
          OmniaMetrics.playlistDrawerHeight(
            screen,
            OmniaMetrics.playlistDrawerDefaultFraction,
          ),
          greaterThanOrEqualTo(screen / 2),
          reason: 'écran de $screen pixels',
        );
      }
    });

    testWidgets('une hauteur déjà mémorisée prime sur le nouveau défaut',
        (tester) async {
      // Personne ne doit voir son réglage écrasé par la mise à jour, même s'il
      // avait choisi plus petit que le défaut.
      final settings = MemorySettingsStore();
      await settings.setPlaylistDrawerFraction(0.25);

      await _pumpDrawer(tester, settings: settings);

      expect(_drawerHeight(tester), _available * 0.25);
    });

    testWidgets('une hauteur jamais réglée retombe sur le défaut', (tester) async {
      final settings = MemorySettingsStore();
      // 0 et les valeurs hors bornes d'une version précédente valent « jamais
      // réglé » : le tiroir ne doit pas s'ouvrir plaqué contre la scène.
      await settings.setPlaylistDrawerFraction(0.02);

      await _pumpDrawer(tester, settings: settings);

      expect(
        _drawerHeight(tester),
        _available * OmniaMetrics.playlistDrawerDefaultFraction,
      );
    });
  });

  group('Redimensionnement au doigt', () {
    testWidgets('glisser vers le haut agrandit le tiroir et retient la hauteur',
        (tester) async {
      final settings = MemorySettingsStore();
      await _pumpDrawer(tester, settings: settings);
      final before = _drawerHeight(tester);

      await _dragGrip(tester, -150);

      final after = _drawerHeight(tester);
      expect(after, greaterThan(before));

      // Écriture temporisée : un glissement produit un événement par image.
      await tester.pump(const Duration(milliseconds: 500));
      expect(settings.playlistDrawerFraction, closeTo(after / _available, 0.001));
    });

    testWidgets('glisser vers le bas réduit le tiroir', (tester) async {
      await _pumpDrawer(tester, settings: MemorySettingsStore());
      final before = _drawerHeight(tester);

      await _dragGrip(tester, 150);

      expect(_drawerHeight(tester), lessThan(before));
    });

    testWidgets('la hauteur reste bornée des deux côtés', (tester) async {
      final settings = MemorySettingsStore();
      await _pumpDrawer(tester, settings: settings);

      // Très loin vers le haut : la scène doit garder de quoi montrer le média.
      await _dragGrip(tester, -4000);
      expect(_drawerHeight(tester), OmniaMetrics.playlistDrawerHighest(_available));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        settings.playlistDrawerFraction,
        OmniaMetrics.playlistDrawerMaxFraction,
      );

      // Très loin vers le bas : le tiroir garde de quoi se manipuler.
      await _dragGrip(tester, 4000);
      expect(_drawerHeight(tester), OmniaMetrics.playlistDrawerLowest(_available));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        settings.playlistDrawerFraction,
        OmniaMetrics.playlistDrawerMinFraction,
      );
    });
  });

  group('Fenêtres basses : la scène garde sa place', () {
    test('la réserve de la scène est respectée à toute hauteur d’écran', () {
      // La moitié d'un écran en portrait est confortable ; la moitié d'un
      // Picture-in-Picture ne laisserait ni image ni bouton de lecture.
      for (final screen in <double>[170, 240, 320, 450, 600, 800, 1280]) {
        final height = OmniaMetrics.playlistDrawerHeight(
          screen,
          OmniaMetrics.playlistDrawerDefaultFraction,
        );
        expect(
          screen - height,
          greaterThanOrEqualTo(OmniaMetrics.playlistDrawerStageReserve),
          reason: 'écran de $screen pixels',
        );
        expect(height, greaterThan(0), reason: 'écran de $screen pixels');
      }
    });

    test('le plancher ne dépasse jamais le plafond', () {
      // Sinon « clamp » lèverait, et le tiroir prendrait une hauteur négative.
      for (final screen in <double>[0, 50, 120, 170, 450, 800]) {
        expect(
          OmniaMetrics.playlistDrawerLowest(screen),
          lessThanOrEqualTo(OmniaMetrics.playlistDrawerHighest(screen)),
          reason: 'écran de $screen pixels',
        );
      }
    });

    testWidgets('en mini-lecteur paysage, le tiroir reste utilisable',
        (tester) async {
      await _pumpDrawer(
        tester,
        settings: MemorySettingsStore(),
        window: _miniWindow,
      );

      final height = _drawerHeight(tester);
      expect(
        _miniWindow.height - height,
        greaterThanOrEqualTo(OmniaMetrics.playlistDrawerStageReserve),
      );
      // Assez haut pour garder ses filtres et montrer des fichiers.
      expect(height, greaterThanOrEqualTo(OmniaMetrics.playlistDrawerUsableHeight));
      expect(find.text('Vidéo'), findsOneWidget);
      expect(find.text('ep01.mkv'), findsOneWidget);
    });

    testWidgets('en Picture-in-Picture, les filtres cèdent la place à la liste',
        (tester) async {
      // Cas le plus serré : la réserve de la scène écrase le tiroir sous sa
      // hauteur utile. Rien ne doit déborder, et le média garde son image.
      await _pumpDrawer(
        tester,
        settings: MemorySettingsStore(),
        window: _pipWindow,
      );

      final height = _drawerHeight(tester);
      expect(
        _pipWindow.height - height,
        greaterThanOrEqualTo(OmniaMetrics.playlistDrawerStageReserve),
      );
      expect(height, lessThan(OmniaMetrics.playlistDrawerUsableHeight));
      // Le filtre « Vidéo » est bien présent quand le tiroir est haut (voir le
      // cas du mini-lecteur) : son absence ici dit que la rangée s'est effacée.
      expect(find.text('Vidéo'), findsNothing);
      // La poignée reste saisissable : le tiroir se rouvre au doigt.
      expect(find.byKey(MobileBottomPlaylist.gripKey), findsOneWidget);
    });
  });

  group('En-tête du tiroir', () {
    testWidgets('un fichier partagé sans dossier le dit au lieu de paraître vide',
        (tester) async {
      await _pumpDrawer(tester, settings: MemorySettingsStore(), loneShare: true);

      expect(find.text('Fichier partagé seul • dossier introuvable'), findsOneWidget);
    });

    testWidgets('un dossier ordinaire annonce la file d’attente', (tester) async {
      await _pumpDrawer(tester, settings: MemorySettingsStore());

      expect(find.textContaining('2 / 3'), findsOneWidget);
      expect(find.text('Fichier partagé seul • dossier introuvable'), findsNothing);
    });
  });
}
