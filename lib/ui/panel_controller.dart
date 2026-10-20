import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/commands/player_command.dart';
import '../core/providers.dart';
import 'theme/omnia_metrics.dart';

/// État d'affichage du panneau de dossier : déployé ou non, sa largeur quand
/// il est à côté de la scène, sa hauteur quand il est en tiroir dessous.
///
/// Purement visuel, donc hors du core — mais piloté par le même bus de
/// commandes que le reste, pour qu'une télécommande puisse un jour replier le
/// panneau à distance.
class PanelState {
  const PanelState({
    required this.visible,
    required this.width,
    required this.drawerFraction,
  });

  final bool visible;
  final double width;

  /// Part de la hauteur disponible prise par le tiroir de liste de lecture
  /// (mobile, sous la scène). Exprimée en pixels, elle ne voudrait rien dire
  /// d'un appareil à l'autre ni d'une orientation à l'autre.
  final double drawerFraction;

  PanelState copyWith({bool? visible, double? width, double? drawerFraction}) =>
      PanelState(
        visible: visible ?? this.visible,
        width: width ?? this.width,
        drawerFraction: drawerFraction ?? this.drawerFraction,
      );
}

final panelStateProvider =
    NotifierProvider<PanelController, PanelState>(PanelController.new);

class PanelController extends Notifier<PanelState> {
  StreamSubscription<PlayerCommand>? _subscription;
  Timer? _saveDebounce;
  Timer? _drawerSaveDebounce;

  @override
  PanelState build() {
    final settings = ref.watch(settingsStoreProvider);
    final stored = settings.sidePanelWidth;
    final storedDrawer = settings.playlistDrawerFraction;

    _subscription = ref.watch(commandBusProvider).commands.listen(_onCommand);
    ref.onDispose(() {
      _subscription?.cancel();
      _saveDebounce?.cancel();
      _drawerSaveDebounce?.cancel();
    });

    return PanelState(
      visible: settings.sidePanelVisible,
      width: stored >= OmniaMetrics.panelMinWidth
          ? stored.clamp(OmniaMetrics.panelMinWidth, OmniaMetrics.panelMaxWidth)
          : OmniaMetrics.panelDefaultWidth,
      // 0 — ou une valeur hors bornes écrite par une version précédente — vaut
      // « jamais réglé » : le tiroir reprend sa hauteur par défaut.
      drawerFraction: _clampDrawer(
        storedDrawer >= OmniaMetrics.playlistDrawerMinFraction
            ? storedDrawer
            : OmniaMetrics.playlistDrawerDefaultFraction,
      ),
    );
  }

  static double _clampDrawer(double fraction) => fraction.clamp(
        OmniaMetrics.playlistDrawerMinFraction,
        OmniaMetrics.playlistDrawerMaxFraction,
      );

  void _onCommand(PlayerCommand command) {
    switch (command) {
      case ToggleSidePanel():
        setVisible(!state.visible);
      case SetSidePanelVisible(:final visible):
        setVisible(visible);
      case SetSidePanelWidth(:final width):
        setWidth(width);
      case SetPlaylistDrawerHeight(:final fraction):
        setDrawerFraction(fraction);
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

  /// Hauteur du tiroir, bornée aux limites du design. Même temporisation que
  /// la largeur : un glissement du doigt produit un événement par image.
  void setDrawerFraction(double fraction) {
    final clamped = _clampDrawer(fraction);
    if (state.drawerFraction == clamped) return;
    state = state.copyWith(drawerFraction: clamped);

    _drawerSaveDebounce?.cancel();
    _drawerSaveDebounce = Timer(
      const Duration(milliseconds: 400),
      () => ref.read(settingsStoreProvider).setPlaylistDrawerFraction(clamped),
    );
  }
}
