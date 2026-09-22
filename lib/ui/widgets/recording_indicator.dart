import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/utils/time_format.dart';
import '../theme/omnia_theme.dart';

/// Témoin d'enregistrement, en haut de la scène : point rouge, « REC » et
/// durée écoulée, comme sur une caméra.
///
/// Il reste visible même quand les contrôles sont masqués : on doit toujours
/// savoir qu'un extrait est en train de s'écrire. Il n'apparaît pas dans
/// l'extrait lui-même, qui recopie le flux du fichier, pas l'écran.
class RecordingIndicator extends ConsumerStatefulWidget {
  const RecordingIndicator({super.key});

  @override
  ConsumerState<RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends ConsumerState<RecordingIndicator> {
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker(bool recording) {
    if (recording) {
      // Une mise à jour par seconde suffit à la durée affichée.
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final startedAt = ref.watch(playbackStateProvider.select((s) => s.recordingStartedAt));
    final recording = ref.watch(playbackStateProvider.select((s) => s.recording));
    _syncTicker(recording);
    if (!recording) return const SizedBox.shrink();

    final colors = context.colors;
    final type = context.type;
    final elapsed = startedAt == null ? Duration.zero : DateTime.now().difference(startedAt);

    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.overlay,
          borderRadius: const BorderRadius.all(Radius.circular(OmniaMetrics.radiusSmall)),
          border: Border.all(color: colors.alert.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: OmniaMetrics.space2,
            vertical: OmniaMetrics.space1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fiber_manual_record_rounded, size: 12, color: colors.alert),
              const SizedBox(width: OmniaMetrics.space1),
              Text('REC', style: type.timecode.copyWith(color: colors.alert, fontSize: 12)),
              const SizedBox(width: OmniaMetrics.space2),
              Text(formatTimecode(elapsed), style: type.timecode.copyWith(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
