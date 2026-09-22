import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Visibilité du panneau d'aide des raccourcis (`F1`).
final helpVisibleProvider =
    NotifierProvider<HelpVisibleNotifier, bool>(HelpVisibleNotifier.new);

class HelpVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void hide() => state = false;
}
