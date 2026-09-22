import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/commands/player_command.dart';
import '../core/providers.dart';
import 'theme/omnia_metrics.dart';

/// État d'affichage du panneau de dossier : déployé ou non, et largeur.
///
/// Purement visuel, donc hors du core — mais piloté par le même bus de
/// commandes que le reste, pour qu'une télécommande puisse un jour replier le
/// panneau à distance.
class PanelState {
  const PanelState({required this.visible, required this.width});

  final bool visible;
  final double width;

  PanelState copyWith({bool? visible, double? width}) =>
      PanelState(visible: visible ?? this.visible, width: width ?? this.width);
}

final panelStateProvider =
    NotifierProvider<PanelController, PanelState>(PanelController.new);

class PanelController extends Notifier<PanelState> {
  StreamSubscription<PlayerCommand>? _subscription;
  Timer? _saveDebounce;

  @override
  PanelState build() {
    final settings = ref.watch(settingsStoreProvider);
    final stored = settings.sidePanelWidth;

    _subscription = ref.watch(commandBusProvider).commands.listen(_onCommand);
    ref.onDispose(() {
      _subscription?.cancel();
      _saveDebounce?.cancel();
    });

    return PanelState(
      visible: settings.sidePanelVisible,
      width: stored >= OmniaMetrics.panelMinWidth
          ? stored.clamp(OmniaMetrics.panelMinWidth, OmniaMetrics.panelMaxWidth)
          : OmniaMetrics.panelDefaultWidth,
    );
  }

  void _onCommand(PlayerCommand command) {
    switch (command) {
      case ToggleSidePanel():
        setVisible(!state.visible);
      case SetSidePanelVisible(:final visible):
        setVisible(visible);
      case SetSidePanelWidth(:final width):
        setWidth(width);
      default:
        break;
    }
  }

  void setVisible(bool visible) {
    if (state.visible == visible) return;
    state = state.copyWith(visible: visible);
    unawaited(ref.read(settingsStoreProvider).setSidePanelVisible(visible));
  }

  /// Largeur bornée aux limites du design. L'écriture sur disque est
  /// temporisée : un glissement produit des dizaines d'événements.
  void setWidth(double width) {
    final clamped =
        width.clamp(OmniaMetrics.panelMinWidth, OmniaMetrics.panelMaxWidth);
    if (state.width == clamped) return;
    state = state.copyWith(width: clamped);

    _saveDebounce?.cancel();
    _saveDebounce = Timer(
      const Duration(milliseconds: 400),
      () => ref.read(settingsStoreProvider).setSidePanelWidth(clamped),
    );
  }
}
