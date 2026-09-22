import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/commands/player_command.dart';
import '../../core/controllers/pdf_controller.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../theme/omnia_theme.dart';

/// Onglets du panneau latéral propres aux PDF : sommaire et vignettes.
enum PanelTab { folder, outline, pages }

/// Sommaire du document (table des matières), cliquable.
class OutlinePanel extends ConsumerWidget {
  const OutlinePanel({super.key, required this.session});

  final PdfSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final currentPage = ref.watch(playbackStateProvider.select((s) => s.currentPage));
    final items = session.outline;

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(OmniaMetrics.space5),
          child: Text(l10n.docNoOutline, style: type.secondary, textAlign: TextAlign.center),
        ),
      );
    }

    // L'entrée « courante » est la dernière dont la page est ≤ la page lue.
    var activeIndex = -1;
    for (var i = 0; i < items.length; i++) {
      final page = items[i].page;
      if (page != null && page <= currentPage) activeIndex = i;
    }

    return ListView.builder(
      itemCount: items.length,
      itemExtent: 34,
      itemBuilder: (context, i) {
        final item = items[i];
        final active = i == activeIndex;
        return _OutlineRow(
          title: item.title,
          page: item.page,
          depth: item.depth,
          active: active,
          onTap: item.page == null ? null : () => ref.dispatch(GoToPage(item.page!)),
          colors: colors,
          type: type,
        );
      },
    );
  }
}

class _OutlineRow extends StatefulWidget {
  const _OutlineRow({
    required this.title,
    required this.page,
    required this.depth,
    required this.active,
    required this.onTap,
    required this.colors,
    required this.type,
  });

  final String title;
  final int? page;
  final int depth;
  final bool active;
  final VoidCallback? onTap;
  final OmniaColors colors;
  final OmniaTypography type;

  @override
  State<_OutlineRow> createState() => _OutlineRowState();
}

class _OutlineRowState extends State<_OutlineRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final type = widget.type;
    final foreground = widget.active ? colors.projector : colors.screen.withValues(alpha: 0.86);

    return MouseRegion(
      cursor: widget.onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: OmniaMotion.hover,
          curve: OmniaMotion.hoverCurve,
          padding: EdgeInsets.only(
            left: OmniaMetrics.space3 + widget.depth * OmniaMetrics.space4,
            right: OmniaMetrics.space3,
          ),
          decoration: BoxDecoration(
            color: widget.active
                ? colors.projector.withValues(alpha: 0.10)
                : (_hovered ? colors.hover : Colors.transparent),
            border: Border(
              left: BorderSide(color: widget.active ? colors.projector : Colors.transparent, width: 2),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: type.body.copyWith(
                    color: foreground,
                    fontWeight: widget.depth == 0 ? FontWeight.w600 : FontWeight.w400,
                    fontSize: widget.depth == 0 ? 14 : 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.page != null) ...[
                const SizedBox(width: OmniaMetrics.space2),
                Text('${widget.page}', style: type.timecode.copyWith(color: colors.dust, fontSize: 11)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Vignettes des pages, rendues à la demande par pdfium.
class ThumbnailsPanel extends ConsumerStatefulWidget {
  const ThumbnailsPanel({super.key, required this.session});

  final PdfSession session;

  @override
  ConsumerState<ThumbnailsPanel> createState() => _ThumbnailsPanelState();
}

class _ThumbnailsPanelState extends ConsumerState<ThumbnailsPanel> {
  final ScrollController _scroll = ScrollController();
  int _followed = -1;

  static const double _extent = 200;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _follow(int page) {
    if (page <= 0 || !_scroll.hasClients) return;
    final target = ((page - 1) * _extent - _scroll.position.viewportDimension / 2 + _extent / 2)
        .clamp(_scroll.position.minScrollExtent, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target, duration: OmniaMotion.panel, curve: OmniaMotion.panelCurve);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final currentPage = ref.watch(playbackStateProvider.select((s) => s.currentPage));
    final count = widget.session.pageCount;

    if (currentPage != _followed) {
      _followed = currentPage;
      WidgetsBinding.instance.addPostFrameCallback((_) => _follow(currentPage));
    }

    return ListView.builder(
      controller: _scroll,
      itemCount: count,
      itemExtent: _extent,
      padding: const EdgeInsets.symmetric(vertical: OmniaMetrics.space2),
      itemBuilder: (context, i) {
        final page = i + 1;
        final active = page == currentPage;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.dispatch(GoToPage(page)),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: OmniaMetrics.space4,
              vertical: OmniaMetrics.space2,
            ),
            child: Column(
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: OmniaMotion.hover,
                    curve: OmniaMotion.hoverCurve,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.all(Radius.circular(OmniaMetrics.radiusSmall)),
                      border: Border.all(
                        color: active ? colors.projector : colors.seam,
                        width: active ? 2 : 1,
                      ),
                    ),
                    child: PdfPageView(
                      document: widget.session.document,
                      pageNumber: page,
                      maximumDpi: 48,
                      backgroundColor: colors.velvet,
                    ),
                  ),
                ),
                const SizedBox(height: OmniaMetrics.space1),
                Text(
                  '$page',
                  style: type.timecode.copyWith(color: active ? colors.projector : colors.dust, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Sélecteur d'onglet du panneau, affiché seulement quand un PDF est ouvert.
class PanelTabBar extends StatelessWidget {
  const PanelTabBar({super.key, required this.selected, required this.onSelected});

  final PanelTab selected;
  final ValueChanged<PanelTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final type = context.type;

    String label(PanelTab tab) => switch (tab) {
          PanelTab.folder => l10n.panelTabFolder,
          PanelTab.outline => l10n.panelTabOutline,
          PanelTab.pages => l10n.panelTabPages,
        };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OmniaMetrics.space3,
        0,
        OmniaMetrics.space3,
        OmniaMetrics.space2,
      ),
      child: Row(
        children: [
          for (final tab in PanelTab.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(tab),
                child: AnimatedContainer(
                  duration: OmniaMotion.hover,
                  curve: OmniaMotion.hoverCurve,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: tab == selected ? colors.projector : colors.seam,
                        width: tab == selected ? 2 : 1,
                      ),
                    ),
                  ),
                  child: Text(
                    label(tab),
                    textAlign: TextAlign.center,
                    style: type.caption.copyWith(
                      color: tab == selected ? colors.projector : colors.dust,
                      fontWeight: tab == selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
