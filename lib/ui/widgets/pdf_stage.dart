import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/commands/player_command.dart';
import '../../core/controllers/pdf_controller.dart';
import '../../core/models/document_layout.dart';
import '../../core/models/playback_state.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../document_search.dart';
import '../document_search_provider.dart';
import '../theme/omnia_theme.dart';
import 'text_view.dart';

/// Vue d'un PDF : défilement continu (pdfrx) ou page par page.
///
/// Le mode sombre de lecture applique une inversion « intelligente » : les
/// couleurs sont inversées puis la teinte tournée d'un demi-tour, ce qui rend
/// le papier noir et l'encre claire tout en gardant aux images des teintes
/// proches des originales.
class PdfStage extends ConsumerStatefulWidget {
  const PdfStage({super.key});

  @override
  ConsumerState<PdfStage> createState() => _PdfStageState();
}

class _PdfStageState extends ConsumerState<PdfStage> {
  PdfDocumentSearch? _search;

  @override
  void dispose() {
    _unregisterSearch();
    super.dispose();
  }

  void _registerSearch(PdfViewerController controller) {
    _unregisterSearch();
    final search = PdfDocumentSearch(controller);
    _search = search;
    // Hors du build : on est dans un rappel de pdfrx.
    ref.read(pdfSearchProvider.notifier).register(search);
  }

  void _unregisterSearch() {
    final current = _search;
    if (current == null) return;
    _search = null;
    current.dispose();
    // Le provider peut déjà être détruit à la fermeture de l'application.
    try {
      ref.read(pdfSearchProvider.notifier).register(null);
    } on Object {
      // Rien à faire.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(pdfSessionProvider);
    final layout = ref.watch(playbackStateProvider.select((s) => s.documentLayout));
    final rotation = ref.watch(playbackStateProvider.select((s) => s.rotation));
    final dark = ref.watch(playbackStateProvider.select((s) => s.readingDark));

    if (session == null) {
      return Center(
        child: Text(l10n.docLoading, style: context.type.secondary),
      );
    }

    final reading = ReadingPalette.of(dark: dark);

    Widget view = switch (layout) {
      DocumentLayout.continuous => _ContinuousView(
          key: ValueKey('pdf:${session.path}'),
          session: session,
          onReady: _registerSearch,
          onDocumentClosed: _unregisterSearch,
          paper: dark ? reading.paper : colors.velvet,
        ),
      DocumentLayout.paged => _PagedView(
          key: ValueKey('pdf-paged:${session.path}'),
          session: session,
          rotation: rotation,
          paper: dark ? reading.paper : colors.velvet,
        ),
    };

    if (layout == DocumentLayout.continuous && rotation != 0) {
      // pdfrx ne pivote pas la vue continue : on pivote la vue entière. Le
      // défilement suit l'axe des pages, ce qui reste cohérent à l'écran.
      view = RotatedBox(quarterTurns: rotation, child: view);
    }

    if (dark) {
      view = ColorFiltered(colorFilter: const ColorFilter.matrix(_smartInvert), child: view);
    }

    return ColoredBox(color: dark ? reading.paper : colors.velvet, child: view);
  }

  /// Inversion puis rotation de teinte de 180° : papier sombre, encre claire,
  /// images aux teintes préservées autant qu'une matrice le permet.
  static const List<double> _smartInvert = [
    0.574, -1.430, -0.144, 0, 255,
    -0.426, -0.430, -0.144, 0, 255,
    -0.426, -1.430, 0.856, 0, 255,
    0, 0, 0, 1, 0,
  ];
}

class _ContinuousView extends ConsumerStatefulWidget {
  const _ContinuousView({
    super.key,
    required this.session,
    required this.onReady,
    required this.onDocumentClosed,
    required this.paper,
  });

  final PdfSession session;
  final void Function(PdfViewerController) onReady;
  final VoidCallback onDocumentClosed;
  final Color paper;

  @override
  ConsumerState<_ContinuousView> createState() => _ContinuousViewState();
}

class _ContinuousViewState extends ConsumerState<_ContinuousView> {
  double? _lastWidth;
  double _accumulatedScroll = 0;
  Timer? _scrollDebounce;
  Timer? _resizeDebounce;

  @override
  void dispose() {
    _scrollDebounce?.cancel();
    _resizeDebounce?.cancel();
    super.dispose();
  }

  void _fitToWidth() {
    final viewer = widget.session.viewer;
    if (!viewer.isReady) return;
    final cover = viewer.coverScale;
    if (cover > 0) {
      viewer.setZoom(viewer.visibleRect.center, cover);
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (HardwareKeyboard.instance.isControlPressed) return; // Ctrl gère le zoom
    final dy = event.scrollDelta.dy;
    if (dy.abs() < 0.5) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final viewer = widget.session.viewer;
      if (!viewer.isReady) return;
      _accumulatedScroll += (dy > 0 ? 150.0 : -150.0);
      _scrollDebounce ??= Timer(const Duration(milliseconds: 16), () {
        if (!mounted || !widget.session.viewer.isReady) {
          _accumulatedScroll = 0;
          _scrollDebounce = null;
          return;
        }
        final delta = _accumulatedScroll;
        _accumulatedScroll = 0;
        _scrollDebounce = null;
        final center = widget.session.viewer.visibleRect.center;
        final targetY = center.dy + delta;
        final safeY = targetY < 0 ? 0.0 : targetY;
        widget.session.viewer.setZoom(Offset(center.dx, safeY), widget.session.viewer.currentZoom);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isMini = ref.watch(playbackStateProvider.select((s) => s.miniPlayer));
    final currentPage = ref.watch(playbackStateProvider.select((s) => s.currentPage));
    final initialPage = currentPage > 0 ? currentPage.clamp(1, widget.session.pageCount) : 1;

    return Listener(
      onPointerSignal: _onPointerSignal,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (_lastWidth != null && (constraints.maxWidth - _lastWidth!).abs() > 2) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _fitToWidth();
            });
            _resizeDebounce?.cancel();
            _resizeDebounce = Timer(const Duration(milliseconds: 50), () {
              if (mounted) _fitToWidth();
            });
          }
          _lastWidth = constraints.maxWidth;

          return PdfViewer(
            // Le document appartient au contrôleur du core : la vue ne doit pas le
            // libérer quand elle se démonte (passage en mode page par page).
            PdfDocumentRefDirect(widget.session.document, autoDispose: false),
            controller: widget.session.viewer,
            initialPageNumber: initialPage,
            params: PdfViewerParams(
              backgroundColor: widget.paper,
              margin: isMini ? 2.0 : OmniaMetrics.space3,
              // Les raccourcis sont ceux d'OMNIA, pas ceux de pdfrx.
              enableKeyboardNavigation: false,
              pageDropShadow: BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
              matchTextColor: colors.projector.withValues(alpha: 0.35),
              activeMatchTextColor: colors.projector.withValues(alpha: 0.7),
              textSelectionParams: const PdfTextSelectionParams(enabled: true),
              onViewerReady: (_, controller) {
                widget.onReady(controller);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && controller.isReady) {
                    final cover = controller.coverScale;
                    if (cover > 0) {
                      controller.setZoom(controller.visibleRect.center, cover);
                    }
                    if (initialPage > 1) {
                      unawaited(controller.goToPage(pageNumber: initialPage, anchor: PdfPageAnchor.top));
                    }
                  }
                });
              },
              onDocumentChanged: (document) {
                if (document == null) widget.onDocumentClosed();
              },
            ),
          );
        },
      ),
    );
  }
}

/// Page par page : une seule page, zoom et déplacement au doigt / à la
/// molette avec Ctrl, changement de page à la molette seule.
class _PagedView extends ConsumerStatefulWidget {
  const _PagedView({
    super.key,
    required this.session,
    required this.rotation,
    required this.paper,
  });

  final PdfSession session;
  final int rotation;
  final Color paper;

  @override
  ConsumerState<_PagedView> createState() => _PagedViewState();
}

class _PagedViewState extends ConsumerState<_PagedView> {
  final TransformationController _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (HardwareKeyboard.instance.isControlPressed) return; // zoom : géré plus haut
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      ref.dispatch(event.scrollDelta.dy > 0 ? const NextPage() : const PreviousPage());
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(playbackStateProvider.select((s) => s.currentPage));
    final zoom = ref.watch(playbackStateProvider.select((s) => s.zoom));

    // Le zoom vient du core (Ctrl+molette, barre) : la vue l'applique.
    final current = _transform.value.getMaxScaleOnAxis();
    if ((current - zoom).abs() > 0.001) {
      _transform.value = Matrix4.diagonal3Values(zoom, zoom, 1);
    }

    final miniPlayer = ref.watch(playbackStateProvider.select((s) => s.miniPlayer));

    return Listener(
      onPointerSignal: _onPointerSignal,
      child: InteractiveViewer(
        transformationController: _transform,
        panEnabled: !miniPlayer,
        minScale: PlaybackState.minZoom,
        maxScale: PlaybackState.maxZoom,
        onInteractionEnd: (_) {
          final scale = _transform.value.getMaxScaleOnAxis();
          if ((scale - zoom).abs() > 0.001) ref.dispatch(SetZoom(scale));
        },
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: miniPlayer ? 2.0 : OmniaMetrics.space4,
              vertical: miniPlayer ? 2.0 : OmniaMetrics.space2,
            ),
            child: FittedBox(
              fit: BoxFit.fitWidth,
              alignment: Alignment.topCenter,
              child: PdfPageView(
                document: widget.session.document,
                pageNumber: page.clamp(1, widget.session.pageCount),
                rotationOverride: PdfPageRotation.values[widget.rotation % 4],
                backgroundColor: widget.paper,
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Recherche dans un PDF, adaptée de `PdfTextSearcher` à l'interface commune.
class PdfDocumentSearch extends DocumentSearch {
  PdfDocumentSearch(PdfViewerController controller) : _searcher = PdfTextSearcher(controller) {
    _searcher.addListener(_sync);
  }

  final PdfTextSearcher _searcher;
  SearchState _state = const SearchState();

  @override
  SearchState get state => _state;

  void _sync() {
    _state = SearchState(
      query: _state.query,
      matches: [
        for (final m in _searcher.matches)
          SearchMatch(page: m.pageText.pageNumber, start: m.start, end: m.end),
      ],
      current: _searcher.currentIndex ?? -1,
      searching: _searcher.isSearching,
    );
    notifyListeners();
  }

  @override
  Future<void> search(String query) async {
    final needle = query.trim();
    if (needle.isEmpty) {
      clear();
      return;
    }
    _state = _state.copyWith(query: needle, searching: true);
    notifyListeners();
    _searcher.startTextSearch(needle, caseInsensitive: true, goToFirstMatch: true);
  }

  @override
  void next() => _searcher.goToNextMatch();

  @override
  void previous() => _searcher.goToPrevMatch();

  @override
  void clear() {
    _searcher.resetTextSearch();
    _state = const SearchState();
    notifyListeners();
  }

  @override
  void dispose() {
    _searcher.removeListener(_sync);
    _searcher.dispose();
    super.dispose();
  }
}
