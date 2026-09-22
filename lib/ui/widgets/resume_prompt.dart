import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/resume_offer.dart';
import '../../core/providers.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/app_localizations.dart';
import '../theme/omnia_theme.dart';
import 'floating_surface.dart';
import 'omnia_button.dart';

/// Invite de reprise (politique « demander ») : une pastille discrète au-dessus
/// des contrôles. Sans réponse, elle s'efface d'elle-même et le fichier
/// continue depuis le début.
///
/// Sur une scène étroite, les boutons passent sous la question, et la question
/// s'abrège plutôt que de déborder.
class ResumePrompt extends ConsumerStatefulWidget {
  const ResumePrompt({super.key});

  /// Temps laissé pour répondre.
  static const Duration timeout = Duration(seconds: 10);

  /// Largeur de scène sous laquelle les boutons passent sous la question.
  static const double compactWidth = 480;

  @override
  ConsumerState<ResumePrompt> createState() => _ResumePromptState();
}

class _ResumePromptState extends ConsumerState<ResumePrompt> {
  Timer? _timeout;
  ResumeOffer? _armedFor;

  /// Début de question qui doit rester lisible pour garder tout sur une ligne.
  static const double _minQuestionWidth = 160;

  /// Bordure d'un pixel de [FloatingSurface], de chaque côté.
  static const double _surfaceBorder = 1;

  /// Marges de la pastille sur une ligne.
  static const EdgeInsets _wideInsets = EdgeInsets.fromLTRB(
    OmniaMetrics.space4,
    OmniaMetrics.space2,
    OmniaMetrics.space2,
    OmniaMetrics.space2,
  );

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  void _arm(ResumeOffer? offer) {
    if (offer == _armedFor) return;
    _armedFor = offer;
    _timeout?.cancel();
    if (offer == null) return;
    _timeout = Timer(ResumePrompt.timeout, () {
      if (mounted && ref.read(playbackStateProvider).resumeOffer == offer) {
        ref.dispatch(const DeclineResume());
      }
    });
  }

  /// Largeur d'un texte d'une ligne, mise à l'échelle du texte comprise.
  static double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }

  /// Largeur d'un [OmniaButton] sans icône : marges, texte, et le contour
  /// d'un pixel des boutons secondaires.
  static double _buttonWidth(BuildContext context, String label, {required bool primary}) =>
      2 * OmniaMetrics.space4 +
      _textWidth(context, label, context.type.bodyStrong) +
      (primary ? 0.0 : 2 * _surfaceBorder);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final offer = ref.watch(playbackStateProvider.select((s) => s.resumeOffer));
    _arm(offer);

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        final Widget content;
        if (offer == null) {
          content = const SizedBox.shrink(key: ValueKey('resume-none'));
        } else {
          content = ConstrainedBox(
            key: ValueKey(offer),
            // Une marge de chaque côté de la scène, quelle que soit sa largeur.
            constraints: BoxConstraints(
              maxWidth: math.max(0.0, available - 2 * OmniaMetrics.space4),
            ),
            child: _pill(context, l10n, offer, available),
          );
        }

        return AnimatedSwitcher(
          duration: OmniaMotion.reveal,
          switchInCurve: OmniaMotion.revealCurve,
          switchOutCurve: OmniaMotion.concealCurve,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero)
                  .animate(animation),
              child: child,
            ),
          ),
          child: content,
        );
      },
    );
  }

  Widget _pill(BuildContext context, AppLocalizations l10n, ResumeOffer offer, double available) {
    final type = context.type;
    final colors = context.colors;
    final position = offer.position;
    final page = offer.page;
    final question = position != null
        ? l10n.resumePromptPosition(formatTimecode(position))
        : page != null
            ? l10n.resumePromptPage(page)
            : l10n.resumePromptScroll;

    final icon = Icon(Icons.history_rounded, size: OmniaMetrics.iconSize, color: colors.projector);
    final accept = OmniaButton(
      label: l10n.resumeAccept,
      primary: true,
      onPressed: () => ref.dispatch(const AcceptResume()),
    );
    final decline = OmniaButton(
      label: l10n.resumeDecline,
      onPressed: () => ref.dispatch(const DeclineResume()),
    );

    // Tout sur une ligne : marges, icône, un début de question lisible, les
    // deux boutons. Sinon, les boutons passent dessous.
    final oneLine = _wideInsets.horizontal +
        2 * _surfaceBorder +
        OmniaMetrics.iconSize +
        OmniaMetrics.space3 +
        math.min(_textWidth(context, question, type.osdLabel), _minQuestionWidth) +
        OmniaMetrics.space4 +
        _buttonWidth(context, l10n.resumeAccept, primary: true) +
        OmniaMetrics.space2 +
        _buttonWidth(context, l10n.resumeDecline, primary: false);
    final pillMax = available - 2 * OmniaMetrics.space4;

    if (available >= ResumePrompt.compactWidth && oneLine <= pillMax) {
      return FloatingSurface(
        borderRadius: OmniaMetrics.controlRadius,
        padding: _wideInsets,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: OmniaMetrics.space3),
            Flexible(
              child: Text(
                question,
                style: type.osdLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: OmniaMetrics.space4),
            accept,
            const SizedBox(width: OmniaMetrics.space2),
            decline,
          ],
        ),
      );
    }

    // Étroit : la question en haut (deux lignes au plus), les boutons dessous
    // à droite, l'un sous l'autre s'ils ne tiennent pas côte à côte.
    return FloatingSurface(
      borderRadius: OmniaMetrics.controlRadius,
      padding: const EdgeInsets.all(OmniaMetrics.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              icon,
              const SizedBox(width: OmniaMetrics.space3),
              Expanded(
                child: Text(
                  question,
                  style: type.osdLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: OmniaMetrics.space3),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: OmniaMetrics.space2,
            runSpacing: OmniaMetrics.space2,
            children: [accept, decline],
          ),
        ],
      ),
    );
  }
}
