import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/commands/player_command.dart';
import '../../core/controllers/media_router.dart';
import '../../core/models/history_entry.dart';
import '../../core/models/media_type.dart';
import '../../core/providers.dart';
import '../recent_files.dart';
import '../theme/omnia_theme.dart';
import 'media_thumbnail.dart';

/// Ce qui s'écrit sur le projecteur : sombre dans les deux thèmes, car
/// l'ambre — vif en sombre, plus dense en clair — n'offre pas assez de
/// contraste au blanc.
const _onProjector = Color(0xFF1A1418);

/// La séance à reprendre : le média le plus récent qu'on a laissé en cours
/// de route, s'il existe encore. `null` s'il n'y en a pas.
RecentFile? resumeHeroOf(List<RecentFile> recents) {
  for (final recent in recents) {
    if (!recent.exists) continue;
    final entry = recent.entry;
    if (entry.resumePosition != null || entry.resumePage != null || entry.resumeScroll != null) {
      return recent;
    }
  }
  return null;
}

/// Le titre d'une séance : sans extension, et sans les points ou soulignés
/// qui tiennent lieu d'espaces dans les noms de fichiers de films.
String resumeTitleFor(String path) {
  final name = p.basenameWithoutExtension(path);
  if (name.contains(' ')) return name;
  return name.replaceAll(RegExp(r'[._]+'), ' ').trim();
}

/// Où l'on en est, sous le mot « Reprendre » : « À 12:05 sur 40:00 »,
/// « Page 12 sur 140 », « Lu à 40 % ».
String? resumeLabelFor(HistoryEntry entry, MediaType type) {
  final position = entry.resumePosition;
  if (type.isAv && position != null) {
    return entry.duration > Duration.zero
        ? 'À ${_clock(position)} sur ${_clock(entry.duration)}'
        : 'À ${_clock(position)}';
  }
  final page = entry.resumePage;
  if (page != null) {
    return entry.pageCount > 0 ? 'Page $page sur ${entry.pageCount}' : 'Page $page';
  }
  final scroll = entry.resumeScroll;
  if (scroll != null) return 'Lu à ${(scroll * 100).round()} %';
  return null;
}

double _fraction(HistoryEntry entry, MediaType type) {
  if (type.isAv && entry.duration > Duration.zero) {
    return (entry.position.inMilliseconds / entry.duration.inMilliseconds).clamp(0.0, 1.0);
  }
  if (entry.pageCount > 0 && entry.page > 0) {
    return (entry.page / entry.pageCount).clamp(0.0, 1.0);
  }
  return entry.scrollFraction.clamp(0.0, 1.0);
}

String _clock(Duration d) {
  final hours = d.inHours;
  final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '${d.inMinutes}:$seconds';
}

/// En tête de l'accueil, comme sur une console : la dernière séance
/// entamée, en grand, éclairée par le projecteur, et reprise d'un toucher.
class ResumeHero extends ConsumerWidget {
  const ResumeHero({super.key, required this.recent});

  final RecentFile recent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final entry = recent.entry;
    final mediaType = MediaRouter.typeForPath(recent.path);
    final label = resumeLabelFor(entry, mediaType);
    final fraction = _fraction(entry, mediaType);
    final title = resumeTitleFor(recent.path);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OmniaMetrics.space4,
        OmniaMetrics.space4,
        OmniaMetrics.space4,
        OmniaMetrics.space2,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Format d'un écran large, borné : sur une tablette à plat, la
          // carte ne mange pas toute la page.
          final height = (constraints.maxWidth * 9 / 16).clamp(160.0, 300.0);
          return Semantics(
            button: true,
            label: 'Reprendre $title',
            child: GestureDetector(
              onTap: () => ref.dispatch(OpenFile(recent.path)),
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  borderRadius: OmniaMetrics.overlayRadius,
                  border: Border.all(color: colors.projector, width: 1.5),
                  boxShadow: [
                    BoxShadow(color: colors.projector.withValues(alpha: 0.28), blurRadius: 22),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(OmniaMetrics.radiusLarge - 1)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MediaThumbnail(path: recent.path),
                      // Voile de lisibilité, sous le texte seulement.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.85),
                              Colors.black.withValues(alpha: 0),
                            ],
                            stops: const [0, 0.7],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          OmniaMetrics.space4,
                          OmniaMetrics.space3,
                          OmniaMetrics.space3,
                          OmniaMetrics.space3,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'REPRENDRE',
                                    style: type.caption.copyWith(
                                      color: colors.projector,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: OmniaMetrics.space1),
                                  // Souple : avec un grand texte, le titre se
                                  // coupe plutôt que de pousser hors de la carte.
                                  Flexible(
                                    child: Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      // Blanc dans les deux thèmes : le texte
                                      // est posé sur le voile noir de l'image.
                                      style: type.viewTitle.copyWith(
                                        color: Colors.white,
                                        height: 1.15,
                                      ),
                                    ),
                                  ),
                                  if (label != null) ...[
                                    const SizedBox(height: OmniaMetrics.space1),
                                    Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: type.timecode.copyWith(
                                        color: Colors.white.withValues(alpha: 0.9),
                                      ),
                                    ),
                                  ],
                                  if (fraction > 0) ...[
                                    const SizedBox(height: OmniaMetrics.space2),
                                    _Beam(fraction: fraction, track: Colors.white.withValues(alpha: 0.18)),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: OmniaMetrics.space3),
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: colors.projector,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.play_arrow_rounded, color: _onProjector, size: 30),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// En mode Aperçu, la tête de l'accueil devient une scène, comme l'accueil
/// d'une console : l'aperçu net de la séance en grand, fondu vers le bas dans
/// le dégradé de ses couleurs, et par-dessus son titre, où l'on en est, et de
/// quoi la reprendre.
///
/// L'image défile avec la page : les listes, plus bas, se lisent sur le fond
/// apaisé et non sur l'image.
class ResumeStage extends ConsumerWidget {
  const ResumeStage({super.key, required this.recent, required this.height});

  final RecentFile recent;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final entry = recent.entry;
    final mediaType = MediaRouter.typeForPath(recent.path);
    final label = resumeLabelFor(entry, mediaType);
    final fraction = _fraction(entry, mediaType);
    final title = resumeTitleFor(recent.path);
    // Une ombre douce détache le titre de l'image en sombre ; en clair, le
    // texte foncé se lit déjà sur le fond pâle.
    final shadows = dark
        ? const [Shadow(color: Color(0x99000000), blurRadius: 14)]
        : const <Shadow>[];

    return Semantics(
      button: true,
      label: 'Reprendre $title',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.dispatch(OpenFile(recent.path)),
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black, Colors.black, Colors.transparent],
                  stops: [0, 0.42, 0.97],
                ).createShader(bounds),
                child: _StageImage(path: recent.path),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  OmniaMetrics.space4,
                  OmniaMetrics.space4,
                  OmniaMetrics.space4,
                  OmniaMetrics.space3,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'REPRENDRE',
                      style: type.caption.copyWith(
                        color: colors.projector,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                        shadows: shadows,
                      ),
                    ),
                    const SizedBox(height: OmniaMetrics.space1),
                    // Souple : avec un grand texte, le titre se coupe plutôt
                    // que de déborder de la scène.
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: type.viewTitle.copyWith(
                          color: colors.screen,
                          fontSize: (type.viewTitle.fontSize ?? 22) * 1.3,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          shadows: shadows,
                        ),
                      ),
                    ),
                    if (label != null) ...[
                      const SizedBox(height: OmniaMetrics.space1),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.timecode.copyWith(color: colors.screen, shadows: shadows),
                      ),
                    ],
                    const SizedBox(height: OmniaMetrics.space3),
                    Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.projector,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color: colors.projector.withValues(alpha: 0.35),
                                blurRadius: 18,
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              OmniaMetrics.space3,
                              OmniaMetrics.space2,
                              OmniaMetrics.space4,
                              OmniaMetrics.space2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.play_arrow_rounded, color: _onProjector, size: 22),
                                const SizedBox(width: OmniaMetrics.space1),
                                Text(
                                  'Reprendre',
                                  style: type.bodyStrong.copyWith(color: _onProjector),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (fraction > 0) ...[
                          const SizedBox(width: OmniaMetrics.space4),
                          Expanded(
                            child: _Beam(
                              fraction: fraction,
                              track: colors.screen.withValues(alpha: 0.16),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// L'aperçu net de la scène, en grand. Sans aperçu — un fichier texte, une
/// vignette refusée —, rien : le dégradé du fond tient la place, plutôt
/// qu'une icône étirée sur la moitié de l'écran.
class _StageImage extends ConsumerStatefulWidget {
  const _StageImage({required this.path});

  final String path;

  @override
  ConsumerState<_StageImage> createState() => _StageImageState();
}

class _StageImageState extends ConsumerState<_StageImage> {
  // Assez grand pour la largeur d'un téléphone sans flou.
  static const int _size = 720;

  late Uint8List? _cached = _cachedNow();
  late Future<Uint8List?> _bytes = _load();

  @override
  void didUpdateWidget(_StageImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _cached = _cachedNow();
      _bytes = _load();
    }
  }

  /// L'aperçu déjà en mémoire : la scène s'affiche d'emblée, sans repasser
  /// par le fondu d'entrée à chaque reconstruction de l'accueil.
  Uint8List? _cachedNow() =>
      ref.read(mediaLibraryProvider).cachedThumbnail(widget.path, size: _size);

  Future<Uint8List?> _load() => ref.read(mediaLibraryProvider).thumbnail(
        widget.path,
        MediaRouter.typeForPath(widget.path),
        size: _size,
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      initialData: _cached,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.expand,
            children: [...previous, ?current],
          ),
          child: bytes == null || bytes.isEmpty
              ? const SizedBox.shrink(key: ValueKey('sans-aperçu'))
              : Image.memory(
                  bytes,
                  key: ValueKey(widget.path),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
        );
      },
    );
  }
}

/// Le faisceau : la part déjà vue, en lumière ambre.
class _Beam extends StatelessWidget {
  const _Beam({required this.fraction, required this.track});

  final double fraction;

  /// La part qui reste à voir.
  final Color track;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: track),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction,
              child: ColoredBox(color: colors.projector),
            ),
          ],
        ),
      ),
    );
  }
}
