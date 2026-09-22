import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/commands/player_command.dart';
import '../core/providers.dart';
import 'theme/omnia_metrics.dart';

/// Largeur de la barre de contrôles choisie par l'utilisateur, en pixels
/// logiques ; 0 = automatique (toute la place, dans la limite du design).
///
/// Comme la largeur du panneau : état visuel, hors du core, mais piloté par
/// le bus ([SetControlBarWidth]) et mémorisé d'une session à l'autre.
final controlBarWidthProvider =
    NotifierProvider<ControlBarWidthController, double>(ControlBarWidthController.new);

class ControlBarWidthController extends Notifier<double> {
  StreamSubscription<PlayerCommand>? _subscription;
  Timer? _saveDebounce;

  @override
  double build() {
    final settings = ref.watch(settingsStoreProvider);
    _subscription = ref.watch(commandBusProvider).commands.listen((command) {
      if (command is SetControlBarWidth) setWidth(command.width);
    });
    ref.onDispose(() {
      _subscription?.cancel();
      _saveDebounce?.cancel();
    });
    final stored = settings.controlBarWidth;
    return stored >= OmniaMetrics.controlBarMinWidth ? stored : 0;
  }

  /// 0 rend la largeur automatique ; sinon, au moins le minimum du design.
  /// Le maximum dépend de la fenêtre : il s'applique à l'affichage. L'écriture
  /// sur disque est temporisée : un glissement produit des dizaines
  /// d'événements.
  void setWidth(double width) {
    final next = width <= 0 ? 0.0 : math.max(width, OmniaMetrics.controlBarMinWidth);
    if (state == next) return;
    state = next;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(
      const Duration(milliseconds: 400),
      () => ref.read(settingsStoreProvider).setControlBarWidth(next),
    );
  }
}
