import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../document_search.dart';
import '../document_ui_controller.dart';
import '../player_focus.dart';
import '../theme/omnia_theme.dart';
import 'floating_surface.dart';
import 'omnia_icon_button.dart';

/// Barre de recherche plein texte (`Ctrl+F`), flottante en haut à droite de
/// la scène. `Entrée` : occurrence suivante ; `Maj+Entrée` : précédente ;
/// `Échap` : fermer.
///
/// Sur une scène étroite, le champ de saisie se resserre ; plus étroite
/// encore, le compteur s'efface. Les boutons gardent leur taille, et rien ne
/// déborde.
class FindBar extends ConsumerStatefulWidget {
  const FindBar({super.key, required this.search});

  final DocumentSearch search;

  /// Largeur du champ quand la place ne manque pas.
  static const double fieldMaxWidth = 240;

  @override
  ConsumerState<FindBar> createState() => _FindBarState();
}

class _FindBarState extends ConsumerState<FindBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'omnia.find');

  /// Champ le plus étroit accepté : en deçà, on ne lirait plus la saisie.
  static const double _fieldMinWidth = 48;

  static const double _iconSize = 16;
  static const double _counterWidth = 64;
  static const double _buttonSize = OmniaMetrics.iconButtonSize - 6;

  /// Tout ce qui n'est pas le champ : loupe, espaces, compteur, trois
  /// boutons, marges et bordure d'un pixel de la surface.
  static const double _chromeWidth = _iconSize +
      2 * OmniaMetrics.space2 +
      _counterWidth +
      3 * _buttonSize +
      2 * OmniaMetrics.space2 +
      2;

  /// Le même, sans le compteur ni son espace.
  static const double _compactChromeWidth = _chromeWidth - _counterWidth - OmniaMetrics.space2;

  @override
  void initState() {
    super.initState();
    widget.search.addListener(_onSearchChanged);
    _controller.text = widget.search.state.query;
    // La barre apparaît à la demande : le focus va droit au champ.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(FindBar old) {
    super.didUpdateWidget(old);
    if (old.search != widget.search) {
      old.search.removeListener(_onSearchChanged);
      widget.search.addListener(_onSearchChanged);
    }
  }

  @override
  void dispose() {
    widget.search.removeListener(_onSearchChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _close() {
    widget.search.clear();
    ref.read(documentUiProvider.notifier).hideFind();
    // La barre emporte son champ, et le focus avec : on le rend au lecteur.
    ref.read(playerFocusProvider).restore();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        widget.search.previous();
      } else if (widget.search.state.query != _controller.text.trim()) {
        widget.search.search(_controller.text);
      } else {
        widget.search.next();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.search.state;
    final hasQuery = state.query.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Posée par un seul coin (en haut à droite de la scène), la barre ne
        // reçoit en général aucune borne : elle se règle alors sur la
        // fenêtre, moins une marge de chaque côté.
        final available = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 2 * OmniaMetrics.space4;
        // Trop étroit même pour le champ le plus court : le compteur cède sa
        // place, et la loupe dit à sa place qu'il n'y a aucun résultat.
        final compact = available < _chromeWidth + _fieldMinWidth;
        final chrome = compact ? _compactChromeWidth : _chromeWidth;
        final fieldWidth = (available - chrome)
            .clamp(_fieldMinWidth, FindBar.fieldMaxWidth)
            .toDouble();
        return _bar(context, state, hasQuery, fieldWidth, compact: compact);
      },
    );
  }

  Widget _bar(
    BuildContext context,
    SearchState state,
    bool hasQuery,
    double fieldWidth, {
    required bool compact,
  }) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final noMatch = hasQuery && state.count == 0;

    return FloatingSurface(
      borderRadius: OmniaMetrics.controlRadius,
      padding: const EdgeInsets.symmetric(
        horizontal: OmniaMetrics.space2,
        vertical: OmniaMetrics.space1,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_rounded,
            size: _iconSize,
            color: compact && noMatch ? colors.alert : colors.dust,
          ),
          const SizedBox(width: OmniaMetrics.space2),
          // Souple : dans une place bornée plus étroite que prévu, c'est le
          // champ qui se resserre, jamais les boutons qui débordent.
          Flexible(
            child: SizedBox(
              width: fieldWidth,
              child: Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  style: type.body,
                  cursorColor: colors.projector,
                  cursorWidth: 1.5,
                  onChanged: widget.search.search,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: l10n.findPlaceholder,
                    hintStyle: type.secondary,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: OmniaMetrics.space2),
            SizedBox(
              width: _counterWidth,
              child: Text(
                !hasQuery
                    ? ''
                    : state.count == 0
                        ? l10n.findNoMatch
                        : l10n.findMatches(state.current + 1, state.count),
                style: type.timecode.copyWith(
                  color: noMatch ? colors.alert : colors.dust,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          OmniaIconButton(
            icon: Icons.keyboard_arrow_up_rounded,
            size: _buttonSize,
            iconSize: OmniaMetrics.iconSize - 2,
            tooltip: '${l10n.findPrevious}  ·  ${l10n.keyShift}+${l10n.keyEnter}',
            onPressed: state.count > 0 ? widget.search.previous : null,
          ),
          OmniaIconButton(
            icon: Icons.keyboard_arrow_down_rounded,
            size: _buttonSize,
            iconSize: OmniaMetrics.iconSize - 2,
            tooltip: '${l10n.findNext}  ·  ${l10n.keyEnter}',
            onPressed: state.count > 0 ? widget.search.next : null,
          ),
          OmniaIconButton(
            icon: Icons.close_rounded,
            size: _buttonSize,
            iconSize: OmniaMetrics.iconSize - 4,
            tooltip: '${l10n.findClose}  ·  ${l10n.keyEscape}',
            onPressed: _close,
          ),
        ],
      ),
    );
  }
}
