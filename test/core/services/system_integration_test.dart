import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/services/system_integration.dart';

/// « Ouvrir l'emplacement du fichier » est la seule action d'OMNIA qui dépende
/// du système hôte. Sous Android il n'existe ni `explorer /select,` ni
/// `open -R` ni `xdg-open` : le dossier passe par un canal natif. Ce test
/// verrouille ce câblage — le nom de la méthode et son argument — car une
/// divergence entre les deux côtés du canal ne se voit qu'à l'exécution, par
/// une entrée de menu qui ne fait rien.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(AndroidSystemIntegration.channel, null);
  });

  test("demande le dossier du fichier à la plateforme", () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(
        AndroidSystemIntegration.channel, (call) async {
      calls.add(call);
      return true;
    });

    await const AndroidSystemIntegration()
        .revealInFileManager('/storage/emulated/0/Movies/film.mkv');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'revealInFileManager');
    expect(calls.single.arguments,
        {'path': '/storage/emulated/0/Movies/film.mkv'});
  });

  test("un URI de fournisseur est transmis tel quel", () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(
        AndroidSystemIntegration.channel, (call) async {
      calls.add(call);
      return true;
    });

    const uri = 'content://media/external/video/media/42';
    await const AndroidSystemIntegration().revealInFileManager(uri);

    // La plateforme décide : un tel URI n'a pas d'emplacement à révéler.
    expect(calls.single.arguments, {'path': uri});
  });

  test("un refus de la plateforme ne fait pas échouer l'appel", () async {
    messenger.setMockMethodCallHandler(AndroidSystemIntegration.channel,
        (call) async {
      throw const PlatformException(
          code: 'aucune_application', message: 'aucun gestionnaire');
    });

    // Aucune application capable d'ouvrir le dossier : sans effet, ce n'est
    // pas une raison d'interrompre la lecture en cours.
    await expectLater(
      const AndroidSystemIntegration().revealInFileManager('/inconnu'),
      completes,
    );
  });

  test("l'intégration neutre n'appelle rien", () async {
    var called = false;
    messenger.setMockMethodCallHandler(
        AndroidSystemIntegration.channel, (call) async {
      called = true;
      return true;
    });

    await const NoopSystemIntegration().revealInFileManager('/quelconque');

    expect(called, isFalse);
  });
}
