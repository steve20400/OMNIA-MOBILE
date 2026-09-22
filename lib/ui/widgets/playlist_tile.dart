import 'package:flutter/material.dart';

import '../../core/models/media_type.dart';
import '../../core/models/playlist_entry.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/app_localizations.dart';
import '../theme/omnia_theme.dart';

/// Une ligne du panneau de dossier.
///
/// Sobre par défaut, elle s'éclaire au survol et passe en ambre quand c'est le
/// fichier en cours. La pastille de progression tient en un seul repère à
/// droite : coche pleine si le fichier est terminé, arc partiel sinon.
class PlaylistTile extends StatefulWidget {
  const PlaylistTile({
    super.key,
    required this.entry,
    required this.current,
    required this.onTap,
    required this.onSecondaryTap,
    this.height = tileHeight,
  });

  static const double tileHeight = 52;

  final PlaylistEntry entry;
  final bool current;
  final VoidCallback onTap;
  final void Function(Offset globalPosition) onSecondaryTap;
  final double height;

  @override
  State<PlaylistTile> createState() => _PlaylistTileState();
}

class _PlaylistTileState extends State<PlaylistTile> {
  bool _hovered = false;

  IconData get _icon => switch (widget.entry.file.type) {
        MediaType.video => Icons.movie_outlined,
        MediaType.audio => Icons.music_note_outlined,
        MediaType.pdf => Icons.picture_as_pdf_outlined,
        MediaType.doc => Icons.description_outlined,
        MediaType.text => Icons.article_outlined,
        MediaType.image => Icons.image_outlined,
        MediaType.unknown => Icons.insert_drive_file_outlined,
      };


  /// Ligne secondaire : durée si connue, sinon nombre de pages, sinon taille.
  String? _subtitle() {
    final entry = widget.entry;
    if (entry.duration != null && entry.duration! > Duration.zero) {
      return formatTimecode(entry.duration!);
    }
    if (entry.pageCount != null && entry.pageCount! > 0) {
      return '${entry.pageCount} p.';
    }
    final size = entry.file.size;
    if (size != null && size > 0) return _formatSize(size);
    return null;
  }

  static String _formatSize(int bytes) {
    const units = ['o', 'Ko', 'Mo', 'Go', 'To'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value < 10 && unit > 0 ? value.toStringAsFixed(1) : value.round()} ${units[unit]}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final entry = widget.entry;

    final foreground = widget.current
        ? colors.projector
        : (_hovered ? colors.screen : colors.screen.withValues(alpha: 0.86));
    final iconColor = widget.current ? colors.projector : colors.dust;
    final subtitle = _subtitle();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTapUp: (d) => widget.onSecondaryTap(d.globalPosition),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: _hovered ? 1 : 0),
          duration: OmniaMotion.hover,
          curve: OmniaMotion.hoverCurve,
          builder: (context, t, child) => Container(
            height: widget.height,
            padding: const EdgeInsets.symmetric(horizontal: OmniaMetrics.space3),
            decoration: BoxDecoration(
              color: widget.current
                  ? colors.projector.withValues(alpha: 0.10 + 0.04 * t)
                  : Color.lerp(Colors.transparent, colors.hover, t),
              border: Border(
                left: BorderSide(
                  color: widget.current ? colors.projector : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: child,
          ),
          child: Row(
            children: [
              Icon(_icon, size: OmniaMetrics.iconSize - 2, color: iconColor),
              const SizedBox(width: OmniaMetrics.space3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.body.copyWith(
                        color: foreground,
                        fontWeight:
                            widget.current ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle, style: type.caption),
                    ],
                  ],
                ),
              ),
              if (entry.hasProgressBadge) ...[
                const SizedBox(width: OmniaMetrics.space2),
                _ProgressBadge(entry: entry),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Repère « déjà lu / position mémorisée ».
class _ProgressBadge extends StatelessWidget {
  const _ProgressBadge({required this.entry});

  final PlaylistEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);

    if (entry.completed) {
      return Tooltip(
        message: l10n.badgeWatched,
        child: Icon(Icons.check_circle_rounded, size: 14, color: colors.dust),
      );
    }

    final resume = entry.resumePosition;
    final page = entry.resumePage;
    final label = resume != null
        ? formatTimecode(resume)
        : page != null
            ? 'p. $page'
            : '${((entry.resumeScroll ?? 0) * 100).round()} %';
    return Tooltip(
      message: l10n.badgeResume(label),
      child: SizedBox(
        width: 14,
        height: 14,
        child: CustomPaint(
          painter: _ArcPainter(
            progress: entry.progress ?? 0.5,
            color: colors.projector,
            track: colors.seam,
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.shortestSide / 2 - 1.5;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, paint..color = track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5707963, // midi
      6.2831853 * progress.clamp(0.0, 1.0),
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}
