import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/models/media_file.dart';
import '../../core/models/media_type.dart';
import '../../core/models/playback_status.dart';
import '../../core/models/video_adjust.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../document_search.dart';
import '../document_search_provider.dart';
import '../document_ui_controller.dart';
import '../file_dialogs.dart';
import '../shortcuts/default_keymap.dart';
import '../shortcuts/shortcut_labels.dart';
import '../theme/omnia_theme.dart';
import 'audio_stage.dart';
import 'image_stage.dart';
import 'omnia_button.dart';

import 'pdf_stage.dart';
import 'recent_files_menu.dart';
import 'text_view.dart';

/// La scène : la zone plein cadre où vit le contenu.
///
/// Selon l'état, elle affiche la vidéo, une vue audio, l'état vide ou une
/// erreur, avec un fondu doux entre les transitions.
class Stage extends ConsumerWidget {
  const Stage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackStateProvider);
    final colors = context.colors;

    final textDocument = ref.watch(textDocumentProvider);

    Widget content;
    if (state.status == PlaybackStatus.error) {
      content = _ErrorStage(
        key: const ValueKey('error'),
        error: state.error ?? const PlaybackError(PlaybackErrorCode.unknown),
        file: state.file,
      );
    } else if (!state.hasFile) {
      content = const _EmptyStage(key: ValueKey('empty'));
    } else if ((state.mediaType == MediaType.text || state.mediaType == MediaType.doc) &&
        textDocument != null) {
      content = TextView(
        key: ValueKey('text:${textDocument.path}'),
        document: textDocument,
        search: ref.watch(documentSearchProvider) as PlainTextSearch?,
      );
    } else if (state.mediaType == MediaType.image && state.hasFile) {
      content = ImageStage(
        key: ValueKey('image:${state.file!.path}'),
        file: state.file!,
      );
    } else if (state.mediaType == MediaType.pdf) {
      content = const PdfStage(key: ValueKey('pdf'));
    } else if (state.isDocument) {
      // Document en cours de chargement.
      content = const SizedBox.shrink(key: ValueKey('doc-loading'));
    } else if (state.hasVideo) {
      content = const _VideoStage(key: ValueKey('video'));
    } else {
      content = AudioStage(key: const ValueKey('audio'), file: state.file!);
    }

    if (state.isDocument) {
      content = Listener(
        onPointerDown: (_) => ref.read(documentUiProvider.notifier).setDocumentFocused(true),
        behavior: HitTestBehavior.translucent,
        child: content,
      );
    }

    return ColoredBox(
      color: colors.velvet,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: OmniaMotion.stage,
            switchInCurve: OmniaMotion.stageCurve,
            switchOutCurve: OmniaMotion.concealCurve,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: content,
          ),
          if (state.status == PlaybackStatus.loading)
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fabrique la surface où s'affiche l'image : la scène et le mini-lecteur
/// passent tous deux par là.
typedef VideoSurfaceBuilder = Widget Function(
  BuildContext context, {
  required BoxFit fit,
  double? aspectRatio,
});

/// Surface vidéo, injectable.
///
/// Par défaut, la vraie surface `media_kit` — qui réclame libmpv, donc
/// impossible à construire dans un test d'interface. Les tests remplacent ce
/// fournisseur par un simple aplat et peuvent alors monter la scène et le
/// mini-lecteur en entier.
final videoSurfaceProvider = Provider<VideoSurfaceBuilder>(
  (ref) => (BuildContext context, {required BoxFit fit, double? aspectRatio}) =>
      _MediaKitSurface(fit: fit, aspectRatio: aspectRatio),
);

class _MediaKitSurface extends ConsumerWidget {
  const _MediaKitSurface({required this.fit, required this.aspectRatio});

  final BoxFit fit;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Video(
      controller: ref.watch(videoControllerProvider),
      controls: NoVideoControls,
      // La scène peint déjà le fond velours derrière la vidéo.
      fill: Colors.transparent,
      fit: fit,
      aspectRatio: aspectRatio,
      // Bicubique : l'image est mise à la taille de la fenêtre par Flutter, et
      // le bilinéaire par défaut la rend floue ou crénelée.
      filterQuality: FilterQuality.high,
      // La mise en veille de l'écran est gérée par OMNIA (ScreenWake) : deux
      // gestionnaires se contrediraient.
      wakelock: false,
    );
  }
}

class _VideoStage extends ConsumerWidget {
  const _VideoStage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aspect = ref.watch(playbackStateProvider.select((s) => s.aspectMode));
    final surface = ref.watch(videoSurfaceProvider);
    return surface(
      context,
      fit: videoFitFor(aspect),
      aspectRatio: videoAspectRatioFor(aspect),
    );
  }
}

/// Ajustement de la vidéo dans la scène : « Remplir » couvre toute la scène
/// (en rognant les bords), les autres modes montrent l'image entière.
BoxFit videoFitFor(AspectMode mode) =>
    mode == AspectMode.fill ? BoxFit.cover : BoxFit.contain;

/// Ratio imposé par l'utilisateur, `null` pour celui de la vidéo.
double? videoAspectRatioFor(AspectMode mode) => switch (mode) {
      AspectMode.wide => 16 / 9,
      AspectMode.standard => 4 / 3,
      AspectMode.auto || AspectMode.fill => null,
    };

class _EmptyStage extends ConsumerWidget {
  const _EmptyStage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    // Sur une scène courte, l'accueil défile plutôt que de déborder ; sur une
    // grande, il reste centré (la hauteur minimale remplit la scène).
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
          ),
          child: _emptyContent(ref, type, l10n),
        ),
      ),
    );
  }

  Widget _emptyContent(WidgetRef ref, OmniaTypography type, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(OmniaMetrics.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.appTitle,
              style: type.wordmark.copyWith(fontSize: 16, letterSpacing: 9),
            ),
            const SizedBox(height: OmniaMetrics.space5),
            Text(l10n.emptyStageHint, style: type.viewTitle, textAlign: TextAlign.center),
            const SizedBox(height: OmniaMetrics.space2),
            Text(l10n.emptyStageSubtitle, style: type.secondary, textAlign: TextAlign.center),
            const SizedBox(height: OmniaMetrics.space6),
            Wrap(
              spacing: OmniaMetrics.space3,
              runSpacing: OmniaMetrics.space3,
              alignment: WrapAlignment.center,
              children: [
                OmniaButton(
                  label: l10n.openFile,
                  icon: Icons.insert_drive_file_outlined,
                  shortcut: ref.shortcutOf(ShortcutAction.openFile, l10n),
                  primary: true,
                  onPressed: () => pickAndOpenFile(ref),
                ),
                OmniaButton(
                  label: l10n.openFolder,
                  icon: Icons.folder_outlined,
                  shortcut: ref.shortcutOf(ShortcutAction.openFolder, l10n),
                  onPressed: () => pickAndOpenFolder(ref),
                ),
              ],
            ),
            const SizedBox(height: OmniaMetrics.space8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: const RecentFilesList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorStage extends ConsumerWidget {
  const _ErrorStage({super.key, required this.error, required this.file});

  final PlaybackError error;
  final MediaFile? file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);

    final message = switch (error.code) {
      PlaybackErrorCode.fileNotFound => l10n.errorFileNotFound,
      PlaybackErrorCode.unsupportedFormat => l10n.errorUnsupported,
      PlaybackErrorCode.decodeFailed => l10n.errorDecode,
      PlaybackErrorCode.permissionDenied => l10n.errorPermission,
      PlaybackErrorCode.emptyFolder => l10n.errorEmptyFolder,
      PlaybackErrorCode.protectedDocument => l10n.errorProtectedDocument,
      PlaybackErrorCode.unknown => l10n.errorUnknown,
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(OmniaMetrics.space6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 40, color: colors.alert),
              const SizedBox(height: OmniaMetrics.space4),
              Text(l10n.errorTitle, style: type.viewTitle, textAlign: TextAlign.center),
              const SizedBox(height: OmniaMetrics.space2),
              Text(message, style: type.body, textAlign: TextAlign.center),
              if (file != null) ...[
                const SizedBox(height: OmniaMetrics.space3),
                Text(
                  file!.name,
                  style: type.caption,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: OmniaMetrics.space5),
              Text(l10n.errorHint, style: type.secondary, textAlign: TextAlign.center),
              const SizedBox(height: OmniaMetrics.space4),
              OmniaButton(
                label: l10n.openAnotherFile,
                icon: Icons.folder_open_rounded,
                onPressed: () => pickAndOpenFile(ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
