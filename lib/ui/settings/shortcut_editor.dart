import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../shortcuts/default_keymap.dart';
import '../shortcuts/key_combo.dart';
import '../shortcuts/keymap_provider.dart';
import '../shortcuts/shortcut_labels.dart';
import '../theme/omnia_theme.dart';
import '../widgets/key_cap.dart';
import '../widgets/omnia_button.dart';
import '../widgets/omnia_icon_button.dart';

/// Éditeur de raccourcis (§8) : réaffectation par capture de touche,
/// détection des conflits, retour aux valeurs par défaut.
///
/// Il se déplie quand la place manque ([compactWidth]) : tout reste atteignable
/// dans la fenêtre minimale d'OMNIA, et même en deçà.
class ShortcutEditor extends ConsumerStatefulWidget {
  const ShortcutEditor({super.key});

  /// En deçà de cette largeur, l'éditeur passe en colonnes : « Tout rétablir »
  /// sous l'explication, et les touches sous l'intitulé de chaque action. En
  /// ligne, il ne resterait que quelques pixels au texte.
  static const double compactWidth = 400;

  @override
  ConsumerState<ShortcutEditor> createState() => _ShortcutEditorState();
}

class _ShortcutEditorState extends ConsumerState<ShortcutEditor> {
  /// Action dont on attend la nouvelle combinaison.
  ShortcutAction? _capturing;

  /// Combinaison saisie qui entre en conflit, en attente de confirmation.
  KeyCombo? _pending;
  ShortcutAction? _conflict;

  void _start(ShortcutAction action) => setState(() {
        _capturing = action;
        _pending = null;
        _conflict = null;
      });

  void _stop() => setState(() {
        _capturing = null;
        _pending = null;
        _conflict = null;
      });

  KeyEventResult _onKey(ShortcutAction action, KeyEvent event) {
    // Tout est intercepté pendant la saisie : aucune touche ne doit piloter
    // la lecture, ni déplacer le focus.
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _stop();
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    final combo = KeyCombo.capture(
      key: event.logicalKey,
      control: keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
      meta: keyboard.isMetaPressed,
    );
    if (combo == null) return KeyEventResult.handled; // modificateur seul

    final conflict = ref.read(keymapProvider).conflictFor(combo, except: action);
    if (conflict == null) {
      ref.read(keymapProvider.notifier).bind(action, combo);
      _stop();
    } else {
      setState(() {
        _pending = combo;
        _conflict = conflict;
      });
    }
    return KeyEventResult.handled;
  }

  void _confirmReplace() {
    final action = _capturing;
    final combo = _pending;
    if (action != null && combo != null) {
      ref.read(keymapProvider.notifier).bind(action, combo);
    }
    _stop();
  }

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);
    final keymap = ref.watch(keymapProvider);
    final prefs = ref.preferences;

    final resetAll = OmniaButton(
      label: l10n.shortcutsResetAll,
      icon: Icons.restart_alt_rounded,
      onPressed: keymap.isAllDefault
          ? null
          : () {
              _stop();
              ref.read(keymapProvider.notifier).resetAll();
            },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.hasBoundedWidth &&
            constraints.maxWidth < ShortcutEditor.compactWidth;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (narrow) ...[
              Text(l10n.shortcutsHint, style: type.secondary),
              const SizedBox(height: OmniaMetrics.space2),
              // Aligné à gauche : étiré, le bouton perdrait sa forme.
              Align(alignment: Alignment.centerLeft, child: resetAll),
            ] else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.shortcutsHint,
                      style: type.secondary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: OmniaMetrics.space3),
                  resetAll,
                ],
              ),
            for (final group in ShortcutGroup.values) ...[
              const SizedBox(height: OmniaMetrics.space5),
              Text(
                group.label(l10n).toUpperCase(),
                style: type.caption.copyWith(
                  color: colors.projector,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: OmniaMetrics.space1),
              for (final action in group.actions)
                _ShortcutRow(
                  label: actionLabel(action, l10n, prefs),
                  combos: keymap.combosFor(action),
                  modified: !keymap.isDefault(action),
                  narrow: narrow,
                  capturing: _capturing == action,
                  conflictLabel: _capturing == action && _conflict != null
                      ? actionLabel(_conflict!, l10n, prefs)
                      : null,
                  pending: _capturing == action ? _pending : null,
                  onEdit: () => _start(action),
                  onCancel: _stop,
                  onReplace: _confirmReplace,
                  onReset: () {
                    _stop();
                    ref.read(keymapProvider.notifier).reset(action);
                  },
                  onKey: (event) => _onKey(action, event),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _ShortcutRow extends StatefulWidget {
  const _ShortcutRow({
    required this.label,
    required this.combos,
    required this.modified,
    required this.narrow,
    required this.capturing,
    required this.conflictLabel,
    required this.pending,
    required this.onEdit,
    required this.onCancel,
    required this.onReplace,
    required this.onReset,
    required this.onKey,
  });

  final String label;
  final List<KeyCombo> combos;
  final bool modified;

  /// Place trop courte pour tout aligner : les touches et les actions passent
  /// sous l'intitulé (voir [ShortcutEditor.compactWidth]).
  final bool narrow;

  final bool capturing;
  final String? conflictLabel;
  final KeyCombo? pending;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onReplace;
  final VoidCallback onReset;
  final KeyEventResult Function(KeyEvent event) onKey;

  @override
  State<_ShortcutRow> createState() => _ShortcutRowState();
}

class _ShortcutRowState extends State<_ShortcutRow> {
  bool _hovered = false;
  final FocusNode _captureFocus = FocusNode(debugLabel: 'omnia.shortcut.capture');

  @override
  void initState() {
    super.initState();
    if (widget.capturing) _grabFocus();
  }

  @override
  void didUpdateWidget(_ShortcutRow old) {
    super.didUpdateWidget(old);
    if (widget.capturing && !old.capturing) _grabFocus();
  }

  /// La ligne en saisie prend le focus à la trame suivante, une fois insérée.
  void _grabFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.capturing) _captureFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _captureFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);

    final Widget keys;
    if (widget.capturing && widget.pending != null) {
      // Wrap plutôt qu'une rangée : faute de place, le conflit passe sous la
      // touche saisie au lieu de déborder.
      keys = Wrap(
        spacing: OmniaMetrics.space2,
        runSpacing: OmniaMetrics.space1,
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          KeyCap(comboLabel(widget.pending!, l10n), highlighted: true),
          Text(
            l10n.shortcutsConflict(widget.conflictLabel ?? ''),
            style: type.secondary.copyWith(color: colors.alert),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    } else if (widget.capturing) {
      keys = Text(l10n.shortcutsPress, style: type.body.copyWith(color: colors.projector));
    } else if (widget.combos.isEmpty) {
      keys = KeyCap(l10n.shortcutsNone, muted: true);
    } else {
      keys = Wrap(
        spacing: OmniaMetrics.space1,
        runSpacing: OmniaMetrics.space1,
        alignment: WrapAlignment.end,
        children: [
          for (final combo in widget.combos)
            KeyCap(comboLabel(combo, l10n), highlighted: widget.modified),
        ],
      );
    }

    // Les touches, cliquables : un clic ouvre la saisie.
    final Widget keysTarget = MouseRegion(
      cursor: widget.capturing ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.capturing ? null : widget.onEdit,
        child: widget.capturing
            ? Align(alignment: Alignment.centerRight, child: keys)
            : Tooltip(
                message: l10n.shortcutsChange,
                child: Align(alignment: Alignment.centerRight, child: keys),
              ),
      ),
    );

    // « Remplacer » / « Annuler » pendant la saisie, « Rétablir » sinon.
    final List<Widget> actions = [
      if (widget.capturing && widget.pending != null) ...[
        _TextAction(label: l10n.shortcutsReplace, onTap: widget.onReplace, primary: true),
        _TextAction(label: l10n.shortcutsCancel, onTap: widget.onCancel),
      ] else if (widget.capturing)
        _TextAction(label: l10n.shortcutsCancel, onTap: widget.onCancel)
      else
        Opacity(
          opacity: widget.modified ? 1 : 0,
          child: OmniaIconButton(
            icon: Icons.restart_alt_rounded,
            size: OmniaMetrics.iconButtonSize - 6,
            iconSize: OmniaMetrics.iconSize - 4,
            tooltip: l10n.shortcutsReset,
            onPressed: widget.modified ? widget.onReset : null,
          ),
        ),
    ];

    // Étroite, la ligne se déplie : l'intitulé (et « Rétablir ») au-dessus,
    // les touches en dessous, les actions de saisie sur leur propre ligne.
    final Widget content = widget.narrow
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.label,
                      style: type.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!widget.capturing) ...[
                    const SizedBox(width: OmniaMetrics.space2),
                    ...actions,
                  ],
                ],
              ),
              const SizedBox(height: OmniaMetrics.space1),
              keysTarget,
              if (widget.capturing) ...[
                const SizedBox(height: OmniaMetrics.space1),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
              ],
            ],
          )
        : Row(
            children: [
              Expanded(child: Text(widget.label, style: type.body)),
              const SizedBox(width: OmniaMetrics.space3),
              Flexible(child: keysTarget),
              const SizedBox(width: OmniaMetrics.space2),
              ...actions,
            ],
          );

    Widget row = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: OmniaMotion.hover,
        curve: OmniaMotion.hoverCurve,
        padding: const EdgeInsets.symmetric(
          horizontal: OmniaMetrics.space2,
          vertical: OmniaMetrics.space1 + 2,
        ),
        decoration: BoxDecoration(
          color: widget.capturing
              ? colors.projector.withValues(alpha: 0.10)
              : (_hovered ? colors.hover : Colors.transparent),
          borderRadius: OmniaMetrics.controlRadius,
        ),
        child: content,
      ),
    );

    if (widget.capturing) {
      // La ligne en saisie a le focus et capte toutes les touches.
      row = Focus(
        focusNode: _captureFocus,
        onKeyEvent: (_, event) => widget.onKey(event),
        child: row,
      );
    }
    return row;
  }
}

/// Lien d'action discret (Remplacer, Annuler).
class _TextAction extends StatefulWidget {
  const _TextAction({required this.label, required this.onTap, this.primary = false});

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<_TextAction> createState() => _TextActionState();
}

class _TextActionState extends State<_TextAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: OmniaMetrics.space2,
            vertical: OmniaMetrics.space1,
          ),
          child: Text(
            widget.label,
            style: type.bodyStrong.copyWith(
              color: widget.primary
                  ? colors.projector
                  : (_hovered ? colors.screen : colors.dust),
              decoration: _hovered ? TextDecoration.underline : TextDecoration.none,
              decorationColor: widget.primary ? colors.projector : colors.screen,
            ),
          ),
        ),
      ),
    );
  }
}
