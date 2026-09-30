import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/decoder_report.dart';
import '../../core/models/playback_status.dart';
import '../../core/providers.dart';
import '../theme/omnia_theme.dart';

/// Ligne de diagnostic du décodage, posée sur l'image.
///
/// Sans téléphone de développement, c'est ce bandeau qui dit ce que le moteur
/// fait réellement : décodeur matériel ou logiciel, définition, cadence
/// annoncée contre cadence rendue, images perdues, avance du démultiplexeur.
/// Une vidéo « au ralenti » se reconnaît d'un coup d'œil — cadence réelle bien
/// au-dessous de la cadence du conteneur.
///
/// Éteinte par défaut ; elle s'allume dans Paramètres → Lecture.
class DecoderInfoOverlay extends ConsumerStatefulWidget {
  const DecoderInfoOverlay({super.key, this.refreshInterval = const Duration(seconds: 1)});

  /// Les compteurs de mpv évoluent en continu : une lecture par seconde suffit
  /// à les suivre sans peser sur le décodage.
  final Duration refreshInterval;

  @override
  ConsumerState<DecoderInfoOverlay> createState() => _DecoderInfoOverlayState();
}

class _DecoderInfoOverlayState extends ConsumerState<DecoderInfoOverlay> {
  Timer? _timer;
  DecoderReport? _report;

  /// Vrai pendant une lecture de propriétés : elles passent par le moteur
  /// natif, et deux relevés ne doivent pas se chevaucher.
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(widget.refreshInterval, (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_reading || !mounted) return;
    _reading = true;
    try {
      final report = await ref.read(avControllerProvider).decoderReport();
      if (!mounted) return;
      setState(() => _report = report);
    } on Object {
      // Moteur libéré entre deux relevés : la ligne garde sa dernière valeur.
    } finally {
      _reading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final playback = ref.watch(playbackStateProvider);
    final report = _report;
    // Rien à dire sans image : le rapport ne porterait que des zéros.
    if (report == null || !playback.hasVideo || playback.status == PlaybackStatus.idle) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.velvet.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.seam, width: 1),
      ),
      child: Text(
        report.summary,
        style: TextStyle(
          fontFamily: OmniaFonts.mono,
          fontSize: 10,
          height: 1.3,
          // Le décodage logiciel est la raison la plus fréquente d'une lecture
          // hachée : il se repère sans lire la ligne entière.
          color: report.hardware ? colors.screen : colors.ember,
        ),
      ),
    );
  }
}
