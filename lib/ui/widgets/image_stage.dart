import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/document_layout.dart';
import '../../core/models/media_file.dart';
import '../../core/providers.dart';

import '../shortcuts/shortcut_handler.dart';
import '../theme/omnia_theme.dart';

import 'stage_context_menu.dart';

/// La scène d'affichage d'une image fixe (`.png`, `.jpg`, `.webp`, `.svg`, etc.).
///
/// Prise en charge du zoom fluide (molette, raccourcis, double-clic pour réajuster),
/// du déplacement (pan/drag) et de la rotation à 90°.
class ImageStage extends ConsumerStatefulWidget {
  const ImageStage({super.key, required this.file});

  final MediaFile file;

  @override
  ConsumerState<ImageStage> createState() => _ImageStageState();
}

class _ImageStageState extends ConsumerState<ImageStage> {
  final TransformationController _transform = TransformationController();
  final FocusNode _focus = FocusNode(debugLabel: 'omnia.image');

  @override
  void dispose() {
    _transform.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // Zoom à la molette avec Ctrl enfoncé, ou zoom direct
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;
    final factor = dy < 0 ? 1.15 : 0.85;
    ref.dispatch(ZoomRelative(factor));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(playbackStateProvider);
    final quarterTurns = state.rotation;

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, event) => handleShortcut(event, ref),
      child: StageContextMenu(
        child: Listener(
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () => ref.dispatch(const FitZoom(FitMode.page)),
            child: Container(


              color: colors.velvet,
              alignment: Alignment.center,
              child: AnimatedRotation(
                turns: quarterTurns / 4,
                duration: OmniaMotion.stage,
                curve: OmniaMotion.stageCurve,
                child: InteractiveViewer(
                  transformationController: _transform,
                  panEnabled: !state.miniPlayer,
                  minScale: 0.1,
                  maxScale: 10.0,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  child: Center(
                    child: Transform.scale(
                      scale: state.zoom,
                      child: Image.file(
                        File(widget.file.path),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (context, error, stackTrace) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image_outlined, size: 64, color: colors.alert),
                            const SizedBox(height: OmniaMetrics.space3),
                            Text(
                              'Format d’image non supporté ou fichier illisible.',
                              style: context.type.body.copyWith(color: colors.dust),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
