import 'dart:async';

import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'window_service.dart';

/// Implémentation mobile de [WindowService].
///
/// Sur Android et iOS :
/// - Le plein écran contrôle le mode immersif du système (`SystemUiMode.immersiveSticky`).
/// - Le maintien au premier plan / always-on-top maintient l'écran allumé via [WakelockPlus].
/// - Les dimensions et le ratio sont gérés par le layout interne Flutter de l'application.
class MobileWindowService implements WindowService {
  static const MethodChannel _pipChannel = MethodChannel('dev.omnia.mobile/pip');

  bool _fullscreen = false;
  bool _alwaysOnTop = false;

  final StreamController<void> _geometry = StreamController<void>.broadcast();
  final StreamController<void> _closeRequests = StreamController<void>.broadcast();
  final StreamController<bool> _pipMode = StreamController<bool>.broadcast();

  MobileWindowService() {
    // La plateforme prévient quand le système entre ou sort lui-même du mode
    // Picture-in-Picture (retour arrière, plein écran repris…). Sans cette
    // écoute, une sortie décidée par le système laisserait l'application
    // convaincue d'être en mini-lecteur : d'où l'écouteur posé ici.
    // Poser un écouteur exige un messager binaire initialisé ; en test
    // unitaire pur il n'y a pas de binding et l'appel lève une assertion : on
    // ne le pose que lorsqu'un messager existe bel et bien.
    try {
      _pipChannel.setMethodCallHandler((call) async {
        if (call.method == 'onPipModeChanged') {
          _pipMode.add(call.arguments as bool? ?? false);
        }
        return null;
      });
    } on AssertionError {
      // Pas de binding (test unitaire) : pas de messager, pas d'écouteur.
    }
  }

  /// Entrées et sorties du mode Picture-in-Picture décidées par le système.
  Stream<bool> get pipModeChanges => _pipMode.stream;

  /// Déclenche le mode Picture-in-Picture natif du système sous Android.
  Future<bool> enterPip({int width = 16, int height = 9}) async {
    try {
      final res = await _pipChannel.invokeMethod<bool>('enterPip', {
        'aspectRatioWidth': width.clamp(1, 1000),
        'aspectRatioHeight': height.clamp(1, 1000),
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<void> get geometryChanges => _geometry.stream;

  @override
  Stream<void> get closeRequests => _closeRequests.stream;

  @override
  Future<bool> isFullscreen() async => _fullscreen;

  @override
  Future<void> setFullscreen(bool value) async {
    _fullscreen = value;
    if (value) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  Future<bool> isAlwaysOnTop() async => _alwaysOnTop;

  @override
  Future<void> setAlwaysOnTop(bool value) async {
    _alwaysOnTop = value;
    if (value) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
  }

  @override
  Future<bool> isMaximized() async => true;

  @override
  Future<void> minimize() async {}

  @override
  Future<void> toggleMaximize() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> destroy() async {}

  @override
  Future<void> setTitle(String title) async {}

  @override
  Future<Rect> getBounds() async => const Rect.fromLTWH(0, 0, 390, 844);

  @override
  Future<void> setBounds(Rect bounds) async {
    _geometry.add(null);
  }

  @override
  Future<void> focus() async {}

  @override
  Future<void> setMinimumSize(Size size) async {}

  @override
  Future<void> setAspectRatio(double ratio) async {}

  @override
  Future<void> setMaximized(bool value) async {}

  void dispose() {
    try {
      _pipChannel.setMethodCallHandler(null);
    } on AssertionError {
      // Pas de binding (test unitaire) : rien à retirer.
    }
    _geometry.close();
    _closeRequests.close();
    _pipMode.close();
  }
}
