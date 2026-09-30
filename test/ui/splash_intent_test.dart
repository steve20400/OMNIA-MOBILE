import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/utils/content_uri.dart';
import 'package:omnia_mobile/ui/screens/splash_screen.dart';
import 'package:omnia_mobile/ui/theme/omnia_theme.dart';

const MethodChannel _channel = MethodChannel('dev.omnia.mobile/intent');

Widget _splash() => MaterialApp(
      theme: buildOmniaTheme(Brightness.dark),
      home: const SplashScreen(
        duration: Duration(milliseconds: 100),
        targetWidget: Scaffold(body: Text('Lecteur')),
      ),
    );

/// Laisse tourner l'écran de démarrage assez longtemps pour que la boucle
/// d'interrogation de la plateforme fasse ses tours.
Future<void> _letPolling(WidgetTester tester, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 130));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(forgetContentUriNames);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    forgetContentUriNames();
  });

  void mockPlatform(Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, handler);
  }

  testWidgets('la préparation d un fichier retient l écran de démarrage',
      (tester) async {
    var calls = 0;
    mockPlatform((call) async {
      if (call.method != 'getInitialFile') return null;
      calls++;
      if (calls <= 2) {
        return <Object?, Object?>{'status': 'pending', 'progress': 0.42};
      }
      return <Object?, Object?>{
        'status': 'ready',
        'path': 'content://test/documents/1',
        'name': 'Le Voyage.avi',
      };
    });

    await tester.pumpWidget(_splash());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // L'avancement est visible : une copie de secours ne doit jamais ressembler
    // à un écran figé.
    expect(find.textContaining('42 %'), findsOneWidget);
    // Le délai du splash est écoulé, mais on ne part pas sans le fichier.
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Lecteur'), findsNothing);

    await _letPolling(tester);
    await tester.pumpAndSettle();

    expect(find.text('Lecteur'), findsOneWidget);
    // Le nom réel est retenu : c'est lui qui donnera son type au média.
    expect(contentUriDisplayName('content://test/documents/1'), 'Le Voyage.avi');
  });

  testWidgets('sans fichier transmis, le démarrage suit son cours',
      (tester) async {
    mockPlatform((call) async => null);

    await tester.pumpWidget(_splash());
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(find.text('Lecteur'), findsOneWidget);
  });

  testWidgets('un canal absent ne bloque pas le démarrage', (tester) async {
    // Aucune plateforme n'est branchée : l'appel lève, et l'écran doit malgré
    // tout laisser la place au lecteur.
    await tester.pumpWidget(_splash());
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    expect(find.text('Lecteur'), findsOneWidget);
  });

  testWidgets('toucher l écran n abrège pas une préparation en cours',
      (tester) async {
    mockPlatform((call) async {
      if (call.method != 'getInitialFile') return null;
      return <Object?, Object?>{'status': 'pending', 'progress': 0.1};
    });

    await tester.pumpWidget(_splash());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    await tester.tap(find.byType(SplashScreen));
    await tester.pump(const Duration(milliseconds: 150));

    // Entrer dans un lecteur vide pour y voir surgir le média une seconde plus
    // tard serait pire que d'attendre.
    expect(find.text('Lecteur'), findsNothing);
    expect(find.textContaining('10 %'), findsOneWidget);

    // La plateforme renonce : la boucle s'arrête et l'écran laisse la place,
    // sans laisser d'attente en suspens derrière le test.
    mockPlatform((call) async => null);
    await _letPolling(tester, rounds: 3);
    await tester.pumpAndSettle();
    expect(find.text('Lecteur'), findsOneWidget);
  });
}
