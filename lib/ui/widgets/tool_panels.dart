import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/equalizer.dart';
import '../../core/models/video_adjust.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../theme/omnia_theme.dart';
import '../tool_panel_controller.dart';
import 'floating_surface.dart';
import 'omnia_button.dart';
import 'omnia_icon_button.dart';
import 'osd_overlay.dart';
import 'slim_slider.dart';

/// Panneau flottant des réglages d'image : luminosité, contraste, saturation.
class ImageAdjustPanel extends ConsumerWidget {
  const ImageAdjustPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final adjust = ref.watch(playbackStateProvider.select((s) => s.videoAdjust));

    void send(VideoAdjust next) => ref.dispatch(SetVideoAdjust(next));

    return _ToolPanelFrame(
      title: l10n.image,
      trailing: OmniaButton(
        label: l10n.resetAdjust,
        icon: Icons.restart_alt_rounded,
        onPressed: adjust.isNeutral ? null : () => ref.dispatch(const ResetVideoAdjust()),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AdjustRow(
            label: l10n.brightness,
            value: adjust.brightness,
            onChanged: (v) => send(adjust.copyWith(brightness: v)),
          ),
          _AdjustRow(
            label: l10n.contrast,
            value: adjust.contrast,
            onChanged: (v) => send(adjust.copyWith(contrast: v)),
          ),
          _AdjustRow(
            label: l10n.saturation,
            value: adjust.saturation,
            onChanged: (v) => send(adjust.copyWith(saturation: v)),
          ),
        ],
      ),
    );
  }
}

class _AdjustRow extends StatelessWidget {
  const _AdjustRow({required this.label, required this.value, required this.onChanged});

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OmniaMetrics.space2),
      child: Row(
        children: [
          SizedBox(width: 92, child: Text(label, style: type.body)),
          Expanded(
            child: SlimSlider(
              value: (value - VideoAdjust.min) / (VideoAdjust.max - VideoAdjust.min),
              muted: false,
              onChanged: (t) => onChanged(
                (VideoAdjust.min + t * (VideoAdjust.max - VideoAdjust.min)).roundToDouble(),
              ),
            ),
          ),
          const SizedBox(width: OmniaMetrics.space3),
          SizedBox(
            width: 40,
            child: Text(
              '${value > 0 ? '+' : ''}${value.round()}',
              style: type.timecode.copyWith(color: value == 0 ? colors.dust : colors.projector),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

/// Panneau flottant de l'égaliseur : préréglages et dix curseurs verticaux.
class EqualizerPanel extends ConsumerWidget {
  const EqualizerPanel({super.key});

  /// Largeur des dix bandes côte à côte.
  static double get bandsWidth =>
      Equalizer.bands.length * _GainSlider.width +
      (Equalizer.bands.length - 1) * OmniaMetrics.space2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final gains = ref.watch(playbackStateProvider.select((s) => s.equalizerGains));
    final enabled = ref.watch(playbackStateProvider.select((s) => s.equalizerEnabled));
    final preset = Equalizer.presetFor(gains);

    return _ToolPanelFrame(
      title: l10n.equalizer,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: preset ?? '_custom',
              dropdownColor: colors.curtain,
              style: type.body,
              iconEnabledColor: colors.dust,
              borderRadius: OmniaMetrics.controlRadius,
              items: [
                for (final name in Equalizer.presets.keys)
                  DropdownMenuItem(value: name, child: Text(presetLabel(l10n, name))),
                if (preset == null)
                  DropdownMenuItem(value: '_custom', child: Text(l10n.presetCustom)),
              ],
              onChanged: (name) {
                if (name != null && name != '_custom') ref.dispatch(SetEqualizerPreset(name));
              },
            ),
          ),
          const SizedBox(width: OmniaMetrics.space2),
          OmniaIconButton(
            icon: enabled ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
            iconSize: OmniaMetrics.iconSizeLarge,
            active: enabled,
            tooltip: enabled ? l10n.equalizerOff : l10n.equalizerOn,
            onPressed: () => ref.dispatch(const ToggleEqualizer()),
          ),
        ],
      ),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: _BandStrip(
          contentWidth: bandsWidth,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < Equalizer.bands.length; i++) ...[
                if (i > 0) const SizedBox(width: OmniaMetrics.space2),
                _GainSlider(
                  label: _bandLabel(Equalizer.bands[i]),
                  gain: gains[i],
                  onChanged: (g) {
                    final next = [...gains];
                    next[i] = g;
                    ref.dispatch(SetEqualizerGains(next));
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _bandLabel(int hz) => hz >= 1000 ? '${hz ~/ 1000}k' : '$hz';
}

/// Les bandes de l'égaliseur. Plus larges que la place, elles défilent de
/// côté, avec une barre de défilement à saisir : la souris ne fait pas
/// glisser une liste, et la molette seule fait défiler le panneau.
class _BandStrip extends StatefulWidget {
  const _BandStrip({required this.contentWidth, required this.child});

  final double contentWidth;
  final Widget child;

  @override
  State<_BandStrip> createState() => _BandStripState();
}

class _BandStripState extends State<_BandStrip> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || constraints.maxWidth >= widget.contentWidth) {
          return widget.child;
        }
        return Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            // Place de la barre de défilement, sous les fréquences.
            padding: const EdgeInsets.only(bottom: OmniaMetrics.space3),
            child: widget.child,
          ),
        );
      },
    );
  }
}

class _GainSlider extends StatelessWidget {
  const _GainSlider({required this.label, required this.gain, required this.onChanged});

  final String label;
  final double gain;
  final ValueChanged<double> onChanged;

  /// Largeur d'une bande : fixe, pour que les dix bandes aient une largeur
  /// connue d'avance ([EqualizerPanel.bandsWidth]).
  static const double width = 28;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final t = (gain - Equalizer.minGain) / (Equalizer.maxGain - Equalizer.minGain);
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${gain > 0 ? '+' : ''}${gain.round()}',
            style: type.timecode.copyWith(fontSize: 10, color: gain == 0 ? colors.dust : colors.projector),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
          ),
          const SizedBox(height: OmniaMetrics.space1),
          SizedBox(
            width: width,
            height: 120,
            child: RotatedBox(
              quarterTurns: 3,
              child: SlimSlider(
                value: t,
                muted: false,
                onChanged: (v) => onChanged(
                  (Equalizer.minGain + v * (Equalizer.maxGain - Equalizer.minGain)).roundToDouble(),
                ),
              ),
            ),
          ),
          const SizedBox(height: OmniaMetrics.space1),
          Text(
            label,
            style: type.caption,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
          ),
        ],
      ),
    );
  }
}

/// Cadre commun : titre, action à droite, bouton de fermeture.
///
/// Étroit, l'action passe sous le titre ; plus haut que la place, le panneau
/// défile.
class _ToolPanelFrame extends ConsumerWidget {
  const _ToolPanelFrame({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  /// Largeur utile sous laquelle l'action quitte la ligne du titre.
  static const double _compactWidth = 380;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final trailing = this.trailing;
    final close = OmniaIconButton(
      icon: Icons.close_rounded,
      size: OmniaMetrics.iconButtonSize - 6,
      iconSize: OmniaMetrics.iconSize - 4,
      tooltip: l10n.closePanel,
      onPressed: () => ref.read(toolPanelProvider.notifier).close(),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: ToolPanelHost.maxWidth),
      child: FloatingSurface(
        // Les marges vivent dans le défilement : le contenu glisse jusqu'au
        // bord arrondi, qui le rogne.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            OmniaMetrics.space4,
            OmniaMetrics.space3,
            OmniaMetrics.space3,
            OmniaMetrics.space4,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < _compactWidth;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: type.sectionTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!compact) ?trailing,
                      const SizedBox(width: OmniaMetrics.space2),
                      close,
                    ],
                  ),
                  if (compact && trailing != null) ...[
                    const SizedBox(height: OmniaMetrics.space2),
                    Align(alignment: Alignment.centerLeft, child: trailing),
                  ],
                  const SizedBox(height: OmniaMetrics.space3),
                  child,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Le panneau ouvert, ou rien.
///
/// Borné par la place qu'on lui donne : jamais plus large que [maxWidth] ni
/// que la scène, et il défile quand il est plus haut que la place.
class ToolPanelHost extends ConsumerWidget {
  const ToolPanelHost({super.key});

  /// Largeur des panneaux quand la place ne manque pas.
  static const double maxWidth = 520;

  /// Posé par un coin de la scène, le panneau ne reçoit souvent aucune
  /// borne : il se règle alors sur la fenêtre, moins la barre de titre, les
  /// marges, et la place gardée sous lui pour la barre de contrôles (celle
  /// que lui laisse l'écran principal).
  static const double _unboundedVerticalInset = OmniaMetrics.titleBarHeight +
      OmniaMetrics.controlBarMargin +
      _controlBarClearance +
      OmniaMetrics.controlBarMargin;
  static const double _controlBarClearance = 96;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.watch(toolPanelProvider);
    final hasVideo = ref.watch(playbackStateProvider.select((s) => s.hasVideo));
    final isAv = ref.watch(playbackStateProvider.select((s) => s.mediaType.isAv));

    final Widget? child = switch (panel) {
      ToolPanel.none => null,
      ToolPanel.image => hasVideo ? const ImageAdjustPanel() : null,
      ToolPanel.equalizer => isAv ? const EqualizerPanel() : null,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = MediaQuery.sizeOf(context);
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : screen.width - 2 * OmniaMetrics.controlBarMargin;
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : screen.height - _unboundedVerticalInset;

        return AnimatedSwitcher(
          duration: OmniaMotion.reveal,
          switchInCurve: OmniaMotion.revealCurve,
          switchOutCurve: OmniaMotion.concealCurve,
          child: child == null
              ? const SizedBox.shrink(key: ValueKey('tool-none'))
              : KeyedSubtree(
                  key: ValueKey(panel),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.max(0.0, math.min(maxWidth, width)),
                      maxHeight: math.max(0.0, height),
                    ),
                    child: child,
                  ),
                ),
        );
      },
    );
  }
}
