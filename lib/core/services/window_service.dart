import 'dart:async';
import 'dart:ui';

import '../models/window_sizes.dart';

/// Abstraction de la surface d'affichage.
abstract interface class WindowService {
  Future<bool> isFullscreen();
  Future<void> setFullscreen(bool value);
  Future<bool> isAlwaysOnTop();
  Future<void> setAlwaysOnTop(bool value);
  Future<bool> isMaximized();
  Future<void> minimize();
  Future<void> toggleMaximize();
  Future<void> close();
  Future<void> setTitle(String title);
  Future<Rect> getBounds();
  Future<void> setBounds(Rect bounds);
  Future<void> focus();
  Future<void> setMinimumSize(Size size);
  Future<void> setAspectRatio(double ratio);
  Future<void> setMaximized(bool value);
  Future<void> destroy();
  Stream<void> get geometryChanges;
  Stream<void> get closeRequests;
}

/// Fenêtre factice pour les tests et les environnements de test unitaire.
class FakeWindowService implements WindowService {
  bool fullscreen = false;
  bool alwaysOnTop = false;
  bool maximized = false;
  bool closed = false;
  int focusCount = 0;
  String title = '';
  Rect bounds = const Rect.fromLTWH(0, 0, 390, 844);

  final StreamController<void> _geometry = StreamController<void>.broadcast();
  final StreamController<void> _closeRequests = StreamController<void>.broadcast();

  @override
  Stream<void> get geometryChanges => _geometry.stream;

  @override
  Stream<void> get closeRequests => _closeRequests.stream;

  void emitCloseRequest() => _closeRequests.add(null);

  @override
  Future<bool> isFullscreen() async => fullscreen;

  @override
  Future<void> setFullscreen(bool value) async => fullscreen = value;

  @override
  Future<bool> isAlwaysOnTop() async => alwaysOnTop;

  @override
  Future<void> setAlwaysOnTop(bool value) async => alwaysOnTop = value;

  @override
  Future<bool> isMaximized() async => maximized;

  @override
  Future<void> minimize() async {}

  @override
  Future<void> toggleMaximize() async => maximized = !maximized;

  @override
  Future<void> close() async => closed = true;

  @override
  Future<void> destroy() async => closed = true;

  @override
  Future<void> setTitle(String value) async => title = value;

  @override
  Future<Rect> getBounds() async => bounds;

  @override
  Future<void> setBounds(Rect value) async {
    bounds = value;
    _geometry.add(null);
  }

  @override
  Future<void> focus() async => focusCount++;

  Size minimumSize = WindowSizes.mainMinimum;

  @override
  Future<void> setMinimumSize(Size size) async => minimumSize = size;

  double aspectRatio = 0;

  @override
  Future<void> setAspectRatio(double ratio) async => aspectRatio = ratio > 0 ? ratio : 0;

  @override
  Future<void> setMaximized(bool value) async => maximized = value;
}
