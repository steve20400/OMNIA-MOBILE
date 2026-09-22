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
  bool _fullscreen = false;
  bool _alwaysOnTop = false;

  final StreamController<void> _geometry = StreamController<void>.broadcast();
  final StreamController<void> _closeRequests = StreamController<void>.broadcast();

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
    _geometry.close();
    _closeRequests.close();
  }
}
