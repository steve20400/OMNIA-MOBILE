import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/models/media_type.dart';
import 'package:omnia_mobile/core/providers.dart';
import 'package:omnia_mobile/core/services/media_library.dart';
import 'package:omnia_mobile/ui/theme/omnia_theme.dart';
import 'package:omnia_mobile/ui/widgets/media_thumbnail.dart';

/// Une image PNG d'un pixel : de vrais octets d'image.
final Uint8List _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Une médiathèque dont on règle la mémoire, et qui compte les demandes.
class _Library implements MediaLibrary {
  _Library({this.cached});

  final Uint8List? cached;
  int asked = 0;

  @override
  Future<List<LibraryFile>> recentlyAdded({int limit = 60}) async => const [];

  @override
  Future<Uint8List?> thumbnail(String path, MediaType type, {int size = 320}) async {
    asked++;
    return _pixel;
  }

  @override
  Uint8List? cachedThumbnail(String path, {int size = 320}) => cached;
}

Future<void> _mount(WidgetTester tester, MediaLibrary library) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [mediaLibraryProvider.overrideWithValue(library)],
      child: MaterialApp(
        theme: buildOmniaTheme(Brightness.dark),
        home: const Center(
          child: SizedBox(width: 148, height: 96, child: MediaThumbnail(path: '/films/vacances.mp4')),
        ),
      ),
    ),
  );
}

void main() {
  group('Vignette de l’accueil', () {
    testWidgets('déjà en mémoire, elle s’affiche dès la première image, sans attente',
        (tester) async {
      final library = _Library(cached: _pixel);
      await _mount(tester, library);

      // Une seule trame construite : l'image est là, l'aperçu n'a pas été
      // redemandé. C'est ce qui évite le clignotement en défilant.
      expect(find.byType(Image), findsOneWidget);
      expect(library.asked, 0);
    });

    testWidgets('pas encore prête : l’icône du type tient la place, puis l’image arrive',
        (tester) async {
      final library = _Library();
      await _mount(tester, library);

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.movie_rounded), findsOneWidget);
      expect(library.asked, 1);

      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('Mémoire des vignettes d’Android', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('omnia-test/vignettes');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('une vignette rendue une fois est servie ensuite sans attendre', () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls++;
        return _pixel;
      });
      final library = AndroidMediaLibrary(channel: channel);

      expect(library.cachedThumbnail('/films/vacances.mp4'), isNull);
      final first = await library.thumbnail('/films/vacances.mp4', MediaType.video);
      expect(first, isNotNull);

      // La même instance : le cache d'images de Flutter la reconnaît, et
      // l'image décodée est réutilisée telle quelle.
      expect(identical(library.cachedThumbnail('/films/vacances.mp4'), first), isTrue);
      // Une autre taille est une autre vignette.
      expect(library.cachedThumbnail('/films/vacances.mp4', size: 720), isNull);
      expect(calls, 1);
    });
  });
}
