import 'package:flutter/material.dart';

import '../theme/omnia_theme.dart';
import '../widgets/omnia_icon_button.dart';
import '../widgets/slim_slider.dart';

/// Contrôles de l'écran Paramètres. Dessinés avec les jetons du thème : aucun
/// composant Material brut, pour que l'écran parle la même langue visuelle
/// que le reste d'OMNIA.

/// Une ligne de réglage : intitulé, explication facultative, contrôle à droite.
/// Sous une largeur étroite, le contrôle passe sous le texte.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.title,
    required this.control,
    this.hint,
  });

  final String title;
  final String? hint;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: type.bodyStrong),
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(hint!, style: type.secondary),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OmniaMetrics.space3),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < OmniaMetrics.settingsRowBreakpoint) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [text, const SizedBox(height: OmniaMetrics.space2), control],
            );
          }
          // Le texte garde au moins les deux cinquièmes de la largeur ; le
          // contrôle prend le reste au plus, et un choix trop large (cinq
          // segments) passe à la ligne au lieu de déborder.
          return Row(
            children: [
              Expanded(flex: 2, child: text),
              const SizedBox(width: OmniaMetrics.space5),
              Flexible(
                flex: 3,
                child: Align(alignment: Alignment.centerRight, child: control),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Séparateur fin entre deux lignes.
class SettingDivider extends StatelessWidget {
  const SettingDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: context.colors.seam);
}

/// Interrupteur : piste ambre quand il est actif, pouce qui glisse.
class OmniaSwitch extends StatefulWidget {
  const OmniaSwitch({super.key, required this.value, required this.onChanged, this.label});

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Nom annoncé par les lecteurs d'écran.
  final String? label;

  @override
  State<OmniaSwitch> createState() => _OmniaSwitchState();
}

class _OmniaSwitchState extends State<OmniaSwitch> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = widget.onChanged != null;
    const width = OmniaMetrics.switchWidth;
    const height = OmniaMetrics.switchHeight;
    const thumb = height - 6;

    return Semantics(
      toggled: widget.value,
      label: widget.label,
      button: true,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => widget.onChanged!(!widget.value) : null,
          child: AnimatedContainer(
            duration: OmniaMotion.hover,
            curve: OmniaMotion.hoverCurve,
            width: width,
            height: height,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: widget.value
                  ? colors.projector
                  : (_hovered ? Color.lerp(colors.seam, colors.dust, 0.25) : colors.seam),
              borderRadius: BorderRadius.circular(height / 2),
            ),
            child: AnimatedAlign(
              duration: OmniaMotion.reveal,
              curve: OmniaMotion.revealCurve,
              alignment: widget.value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: thumb,
                height: thumb,
                decoration: BoxDecoration(
                  color: widget.value ? colors.velvet : colors.screen,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Choix exclusif parmi quelques valeurs, présentées côte à côte.
class OmniaSegmented<T> extends StatelessWidget {
  const OmniaSegmented({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.velvet,
        borderRadius: OmniaMetrics.controlRadius,
        border: Border.all(color: colors.seam),
      ),
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        alignment: WrapAlignment.end,
        children: [
          for (final value in values)
            _Segment(
              label: labelOf(value),
              selected: value == selected,
              onTap: () => onChanged(value),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Semantics(
      selected: widget.selected,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: OmniaMotion.hover,
            curve: OmniaMotion.hoverCurve,
            padding: const EdgeInsets.symmetric(
              horizontal: OmniaMetrics.space3,
              vertical: OmniaMetrics.space1 + 2,
            ),
            decoration: BoxDecoration(
              color: widget.selected
                  ? colors.projector
                  : (_hovered ? colors.hover : Colors.transparent),
              borderRadius:
                  const BorderRadius.all(Radius.circular(OmniaMetrics.radiusSmall)),
            ),
            child: Text(
              widget.label,
              style: type.body.copyWith(
                color: widget.selected ? colors.velvet : colors.screen,
                fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Curseur avec sa valeur lisible à droite, en mono.
class LabelledSlider extends StatelessWidget {
  const LabelledSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.format,
    this.divisions,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String Function(double value) format;

  /// Nombre de crans ; `null` pour un réglage continu.
  final int? divisions;

  double _snap(double v) {
    final d = divisions;
    if (d == null || d <= 0) return v;
    final step = (max - min) / d;
    return (min + ((v - min) / step).round() * step).clamp(min, max);
  }

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Souple : dans une ligne étroite, le curseur se raccourcit plutôt
        // que de déborder ; la valeur garde sa place.
        Flexible(
          child: SlimSlider(
            width: OmniaMetrics.settingsSliderWidth,
            value: (value - min) / (max - min),
            onChanged: (t) => onChanged(_snap(min + t * (max - min))),
          ),
        ),
        const SizedBox(width: OmniaMetrics.space3),
        SizedBox(
          width: OmniaMetrics.settingsValueWidth,
          child: Text(format(value), style: type.timecode, textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

/// Valeur réglée par pas, avec − et + de part et d'autre.
class ValueStepper extends StatelessWidget {
  const ValueStepper({
    super.key,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
    required this.decreaseLabel,
    required this.increaseLabel,
  });

  final String value;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;
  final String decreaseLabel;
  final String increaseLabel;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OmniaIconButton(icon: Icons.remove_rounded, tooltip: decreaseLabel, onPressed: onDecrease),
        SizedBox(
          width: OmniaMetrics.settingsValueWidth,
          child: Text(value, style: type.timecode, textAlign: TextAlign.center),
        ),
        OmniaIconButton(icon: Icons.add_rounded, tooltip: increaseLabel, onPressed: onIncrease),
      ],
    );
  }
}
