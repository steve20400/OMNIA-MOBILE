import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chrome_controller.dart';
import '../player_focus.dart';
import '../theme/omnia_theme.dart';

/// Menu déroulant des contrôles de lecture (vitesse, sous-titres, pistes,
/// menu « ⋯ »).
///
/// Tant qu'il est ouvert, les contrôles restent affichés : le menu vit dans
/// une surcouche, hors de la barre, et le masquage automatique la ferait
/// disparaître sous lui. Sa retenue est levée à la fermeture, et aussi si le
/// bouton disparaît menu ouvert (changement de fichier, barre réduite). À la
/// fermeture, le clavier revient au lecteur.
class ChromeMenuAnchor extends ConsumerStatefulWidget {
  const ChromeMenuAnchor({
    super.key,
    required this.menuChildren,
    required this.builder,
  });

  final List<Widget> menuChildren;
  final MenuAnchorChildBuilder builder;

  @override
  ConsumerState<ChromeMenuAnchor> createState() => _ChromeMenuAnchorState();
}

class _ChromeMenuAnchorState extends ConsumerState<ChromeMenuAnchor> {
  late final ChromeController _chrome;
  late final PlayerFocus _focus;

  @override
  void initState() {
    super.initState();
    _chrome = ref.read(chromeProvider.notifier);
    _focus = ref.read(playerFocusProvider);
  }

  @override
  void dispose() {
    _chrome.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      consumeOutsideTap: true,
      alignmentOffset: const Offset(0, -OmniaMetrics.space2),
      onOpen: () => _chrome.hold(this),
      onClose: () {
        _chrome.release(this);
        _focus.restore();
      },
      menuChildren: widget.menuChildren,
      builder: widget.builder,
    );
  }
}
