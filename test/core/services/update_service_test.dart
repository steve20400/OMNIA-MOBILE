import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/services/update_service.dart';

/// Choix du paquet à télécharger, sans réseau.
///
/// Chaque version publie un paquet par processeur plus un paquet universel.
/// Par prudence, le service prenait toujours l'universel : il s'installe sur
/// toutes les architectures, mais pèse près de trois fois le paquet de
/// l'appareil (137 Mo contre 50). Défaut sans conséquence tant que le dépôt
/// était privé et que rien ne se téléchargeait ; réel depuis qu'il est public.
void main() {
  /// Les quatre fichiers réellement publiés, dans l'ordre où l'API les rend.
  List<Map<String, dynamic>> published() => [
        {'name': 'app-arm64-v8a-release.apk', 'size': 52428800},
        {'name': 'app-armeabi-v7a-release.apk', 'size': 46039040},
        {'name': 'app-x86_64-release.apk', 'size': 58654720},
        {'name': 'omnia-mobile-universel.apk', 'size': 144284057},
      ];

  String? nameOf(Map<String, dynamic>? asset) => asset?['name'] as String?;

  test('prend le paquet de l’architecture demandée', () {
    // La liste commence par de l'arm64 : réclamer du 32 bits prouve qu'on ne
    // se contente pas du premier venu.
    final chosen = UpdateService.pickInstaller(
      published(),
      abiFragment: 'armeabi-v7a',
    );
    expect(nameOf(chosen), 'app-armeabi-v7a-release.apk');
  });

  test('un téléphone 64 bits évite le paquet universel, trois fois plus lourd',
      () {
    final chosen = UpdateService.pickInstaller(
      published(),
      abiFragment: 'arm64-v8a',
    );
    expect(nameOf(chosen), 'app-arm64-v8a-release.apk');
    expect(chosen!['size'], lessThan(60000000));
  });

  test('architecture absente : repli sur l’universel', () {
    final chosen = UpdateService.pickInstaller(
      published(),
      abiFragment: 'mips-introuvable',
    );
    expect(nameOf(chosen), 'omnia-mobile-universel.apk');
  });

  test('architecture inconnue de l’appareil : repli sur l’universel', () {
    final chosen = UpdateService.pickInstaller(published());
    expect(nameOf(chosen), 'omnia-mobile-universel.apk');
  });

  test('sans universel ni correspondance, un paquet quand même', () {
    final chosen = UpdateService.pickInstaller(
      [
        {'name': 'app-arm64-v8a-release.apk'},
        {'name': 'app-x86_64-release.apk'},
      ],
      abiFragment: 'armeabi-v7a',
    );
    // Mieux vaut un paquet qui ne convient peut-être pas que pas de mise à
    // jour : le repli ne rend jamais null quand un paquet existe.
    expect(nameOf(chosen), 'app-arm64-v8a-release.apk');
  });

  test('les fichiers qui ne sont pas des paquets sont ignorés', () {
    final chosen = UpdateService.pickInstaller(
      [
        {'name': 'notes-de-version.txt'},
        {'name': 'app-arm64-v8a-release.apk'},
      ],
      abiFragment: 'arm64-v8a',
    );
    expect(nameOf(chosen), 'app-arm64-v8a-release.apk');
  });

  test('aucun paquet publié : rien à proposer', () {
    expect(
      UpdateService.pickInstaller([
        {'name': 'notes-de-version.txt'},
      ], abiFragment: 'arm64-v8a'),
      isNull,
    );
  });

  test('la détection d’architecture rend une valeur connue ou null', () {
    // L'appareil de test n'est pas un téléphone : la fonction doit se
    // replier proprement au lieu de lever.
    final pattern = preferredAssetPattern();
    expect(
      pattern,
      anyOf(isNull, 'arm64-v8a', 'armeabi-v7a', 'x86_64'),
    );
  });
}
