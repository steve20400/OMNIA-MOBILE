import 'package:wakelock_plus/wakelock_plus.dart';

/// Empêche l'écran de se mettre en veille.
///
/// Derrière une interface pour que le core reste testable sans plugin, et
/// pour qu'une plateforme sans support (ou un échec du plugin) n'interrompe
/// jamais la lecture.
abstract interface class ScreenWake {
  Future<void> setKeepAwake(bool keepAwake);
}

/// Implémentation réelle, via `wakelock_plus` (Windows, Linux, macOS).
class WakelockScreenWake implements ScreenWake {
  const WakelockScreenWake();

  @override
  Future<void> setKeepAwake(bool keepAwake) async {
    try {
      await WakelockPlus.toggle(enable: keepAwake);
    } on Object {
      // Pas de service de veille disponible (session sans D-Bus, par exemple) :
      // l'écran s'éteindra peut-être, la lecture continue.
    }
  }
}

/// Implémentation d'enregistrement, pour les tests.
class RecordingScreenWake implements ScreenWake {
  final List<bool> calls = [];

  @override
  Future<void> setKeepAwake(bool keepAwake) async => calls.add(keepAwake);
}

/// Règle unique : l'écran reste allumé pendant la lecture d'une vidéo.
/// Un fichier audio, une pause, une erreur : l'écran peut s'éteindre.
bool shouldKeepScreenAwake({required bool playing, required bool hasVideo}) =>
    playing && hasVideo;
