import 'dart:ui' show ImageFilter;

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
                                      style: type.viewTitle.copyWith(
                                        color: colors.screen,
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
                                      style: type.timecode.copyWith(color: colors.screen),
                                    ),
                                  ],
                                  if (fraction > 0) ...[
                                    const SizedBox(height: OmniaMetrics.space2),
                                    _Beam(fraction: fraction),
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
                              child: Icon(Icons.play_arrow_rounded, color: colors.velvet, size: 30),
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

/// Le faisceau : la part déjà vue, en lumière ambre.
class _Beam extends StatelessWidget {
  const _Beam({required this.fraction});

  final double fraction;

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
            ColoredBox(color: Colors.white.withValues(alpha: 0.18)),
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

/// Le fond de l'accueil sous la carte « Reprendre » : son image, très
/// floutée, qui s'efface vers le velours — la lumière de l'écran dans la
/// salle.
class ResumeBackdrop extends StatelessWidget {
  const ResumeBackdrop({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: 0.5,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32, tileMode: TileMode.decal),
              child: MediaThumbnail(path: path),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [colors.velvet.withValues(alpha: 0.2), colors.velvet],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
