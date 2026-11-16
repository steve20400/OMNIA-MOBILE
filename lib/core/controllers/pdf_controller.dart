import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

import '../commands/player_command.dart';
import '../models/document_layout.dart';
import '../models/media_file.dart';
import '../models/media_type.dart';
import '../models/playback_state.dart';
import '../models/playback_status.dart';
import '../utils/outline_flattener.dart';
import 'media_controller.dart';

/// Un PDF ouvert : le document pdfium, son sommaire aplati et le contrôleur
/// de vue que le widget pdfrx pilote.
class PdfSession {
  const PdfSession({
    required this.path,
    required this.document,
    required this.outline,
    required this.viewer,
  });

  final String path;
  final PdfDocument document;
  final List<OutlineItem> outline;
  final PdfViewerController viewer;

  int get pageCount => document.pages.length;
}

/// Contrôleur des documents PDF (pdfium via pdfrx).
///
/// Il ouvre le document une seule fois (nombre de pages, sommaire, détection
/// de protection) et le confie à la vue. Les commandes de page et de zoom
/// passent par le [PdfViewerController] quand la vue continue est montée ;
/// en mode page par page, seul l'état change et la vue le suit.
class PdfController implements MediaController {
  PdfController() {
    viewer.addListener(_onViewerChanged);
  }

  /// Contrôleur pdfrx, unique pour toute la vie de l'application : la vue le
  /// prend en charge quand elle est montée.
  final PdfViewerController viewer = PdfViewerController();

  final StreamController<PdfSession?> _sessions = StreamController<PdfSession?>.broadcast();

  PdfSession? _session;
  PlaybackStateSink? _sink;
  int? _targetPage;

  PdfSession? get session => _session;

  /// Dessine une page du document en PNG.
  ///
  /// Sert au mini-lecteur flottant, qui vit hors de Flutter et ne sait
  /// afficher qu'une image : un document y restait réduit à son titre. pdfium
  /// dessine la page depuis le fichier, sans dépendre de la vue ni de
  /// l'application au premier plan — c'est ce qui permet de continuer à lire
  /// par-dessus une autre application.
  ///
  /// Rend `null` quand il n'y a pas de document ouvert, ou que la page
  /// demandée n'existe pas : l'appelant retombe alors sur le titre.
  Future<Uint8List?> renderPagePng({required int page, int width = 480}) async {
    final session = _session;
    if (session == null) return null;
    final pages = session.document.pages;
    if (page < 1 || page > pages.length) return null;
    final target = pages[page - 1];
    final height = (width * target.height / target.width).round();
    if (height <= 0) return null;
    final image = await target.render(width: width, height: height);
    if (image == null) return null;
    try {
      // pdfium rend en BGRA ; l'encodeur attend les canaux dans l'autre ordre.
      final pixels = image.pixels;
      final rgba = Uint8List(pixels.length);
      for (var i = 0; i + 3 < pixels.length; i += 4) {
        rgba[i] = pixels[i + 2];
        rgba[i + 1] = pixels[i + 1];
        rgba[i + 2] = pixels[i];
        rgba[i + 3] = pixels[i + 3];
      }
      return Uint8List.fromList(
        img.encodePng(
          img.Image.fromBytes(
            width: image.width,
            height: image.height,
            bytes: rgba.buffer,
            numChannels: 4,
          ),
        ),
      );
    } on Object {
      // Un document protégé ou abîmé ne doit pas emporter le mini-lecteur.
      return null;
    } finally {
      image.dispose();
    }
  }
  Stream<PdfSession?> get sessions => _sessions.stream;

  @override
  Set<MediaType> get supportedTypes => const {MediaType.pdf};

  void _publish(PdfSession? session) {
    _session = session;
    if (!_sessions.isClosed) _sessions.add(session);
  }

  @override
  Future<void> open(MediaFile file, PlaybackStateSink sink) async {
    _sink = sink;
    _targetPage = null;
    final pendingPage = sink.state.currentPage > 0 ? sink.state.currentPage : 1;
    sink.update(
      (st) => st.copyWith(
        file: file,
        status: PlaybackStatus.loading,
        position: Duration.zero,
        duration: Duration.zero,
        hasVideo: false,
        currentPage: pendingPage,
        totalPages: 0,
        rotation: 0,
        zoom: 1.0,
        scrollFraction: 0,
        clearError: true,
      ),
    );

    if (!File(file.path).existsSync()) {
      await _closeSession();
      sink.update(
        (st) => st.copyWith(
          status: PlaybackStatus.error,
          error: const PlaybackError(PlaybackErrorCode.fileNotFound),
        ),
      );
      return;
    }

    try {
      await pdfrxFlutterInitialize();
      // Sans fournisseur de mot de passe, un document protégé lève
      // PdfPasswordException : c'est le comportement voulu, OMNIA ne demande
      // pas de mot de passe (lecture seule, pas de saisie de secret).
      final document = await PdfDocument.openFile(file.path, firstAttemptByEmptyPassword: true);
      final nodes = await document.loadOutline();
      final outline = flattenOutline<PdfOutlineNode>(
        nodes,
        title: (n) => n.title,
        page: (n) => n.dest?.pageNumber,
        children: (n) => n.children,
      );

      await _closeSession();
      _publish(PdfSession(path: file.path, document: document, outline: outline, viewer: viewer));

      final targetPage = pendingPage.clamp(1, document.pages.length);
      _targetPage = targetPage > 1 ? targetPage : null;

      sink.update(
        (st) => st.copyWith(
          status: PlaybackStatus.playing,
          currentPage: targetPage,
          totalPages: document.pages.length,
        ),
      );
    } on PdfPasswordException {
      await _closeSession();
      sink.update(
        (st) => st.copyWith(
          status: PlaybackStatus.error,
          error: const PlaybackError(PlaybackErrorCode.protectedDocument),
        ),
      );
    } on Object catch (e) {
      await _closeSession();
      sink.update(
        (st) => st.copyWith(
          status: PlaybackStatus.error,
          error: PlaybackError(PlaybackErrorCode.decodeFailed, detail: e.toString()),
        ),
      );
    }
  }

  /// La vue a bougé (défilement, zoom) : on reflète page et zoom dans l'état.
  void _onViewerChanged() {
    final sink = _sink;
    if (sink == null || _session == null || !viewer.isReady) return;
    final page = viewer.pageNumber;
    if (_targetPage != null) {
      if (page == _targetPage) {
        _targetPage = null;
      } else {
        // En transition vers la page cible : s'assurer que le visualiseur est bien
        // en train d'y naviguer.
        if (viewer.isReady && page != _targetPage) {
          unawaited(viewer.goToPage(pageNumber: _targetPage!, anchor: PdfPageAnchor.top));
        }
        return;
      }
    } else if (page == 1 && sink.state.currentPage > 1) {
      // Artéfact d'initialisation de pdfrx (montage d'une nouvelle vue lors de la
      // bascule mini-lecteur ⬌ fenêtre normale) : ne jamais écraser la page courante.
      unawaited(viewer.goToPage(pageNumber: sink.state.currentPage, anchor: PdfPageAnchor.top));
      return;
    }
    final cover = viewer.coverScale;
    final zoom = cover > 0 ? viewer.currentZoom / cover : sink.state.zoom;
    _noteScroll();
    final changedPage = page != null && page != sink.state.currentPage;
    final changedZoom = zoom.isFinite && (zoom - sink.state.zoom).abs() > 0.001;
    if (!changedPage && !changedZoom) return;
    sink.update(
      (st) => st.copyWith(
        currentPage: changedPage ? page : null,
        zoom: changedZoom ? zoom.clamp(PlaybackState.minZoom, PlaybackState.maxZoom) : null,
      ),
    );
  }

  @override
  Future<bool> handle(PlayerCommand command) async {
    final sink = _sink;
    final session = _session;
    if (sink == null || session == null) return false;
    final state = sink.state;

    switch (command) {
      case NextPage():
        await _goToPage(state.currentPage + 1);
      case PreviousPage():
        await _goToPage(state.currentPage - 1);
      case GoToPage(:final page):
        await _goToPage(page);
      case ZoomRelative(:final factor):
        await _setZoom(state.zoom * factor);
      case SetZoom(:final zoom):
        await _setZoom(zoom);
      case FitZoom(:final mode):
        await _fit(mode);
      case RotateDocument(:final quarterTurns):
        sink.update((st) => st.copyWith(rotation: (st.rotation + quarterTurns) % 4));
      case ToggleReadingDarkMode():
        sink.update((st) => st.copyWith(readingDark: !st.readingDark));
      case SetDocumentLayout(:final layout):
        sink.update((st) => st.copyWith(documentLayout: layout));
      case ToggleDocumentLayout():
        sink.update((st) => st.copyWith(documentLayout: st.documentLayout.other));
      case ScrollTo(:final fraction):
        // La position dans le document, de 0 à 1 : c'est ce que transmet la
        // lecture miroir, parce que deux fenêtres de formes différentes ne
        // s'accordent ni sur les pixels ni sur la page courante.
        if (viewer.isReady) {
          try {
            final visible = viewer.visibleRect;
            final travel = viewer.documentSize.height - visible.height;
            if (travel > 0) {
              final top = fraction.clamp(0.0, 1.0) * travel;
              await viewer.setZoom(
                Offset(visible.center.dx, top + visible.height / 2),
                viewer.currentZoom,
                duration: Duration.zero,
              );
            }
          } on Object {
            // Vue en cours de mise en page : sa géométrie n'existe pas
            // encore. L'état suivant du miroir rattrapera ce défilement.
          }
        }
      case ScrollDocument(:final delta):
        if (viewer.isReady) {
          final center = viewer.visibleRect.center;
          // Sans durée : pdfrx anime sur 200 ms par défaut, et cette commande
          // est attendue dans la file du service. Chaque cran de molette
          // bloquait donc la file un cinquième de seconde, les crans arrivant
          // bien plus vite que cela — ils s'empilaient, et le document
          // continuait de défiler longtemps après qu'on avait lâché la molette.
          await viewer.setZoom(
            Offset(center.dx, center.dy + delta),
            viewer.currentZoom,
            duration: Duration.zero,
          );
        }
      default:
        return false;
    }
    return true;
  }

  Future<void> _goToPage(int page) async {
    final sink = _sink!;
    final total = sink.state.totalPages;
    if (total <= 0) return;
    final target = page.clamp(1, total);
    _targetPage = target;
    if (viewer.isReady) {
      // Lancée, jamais attendue. pdfrx anime ce déplacement, et une animation
      // Flutter interrompue ne se termine pas : son futur reste en suspens
      // pour toujours. Or n'importe quoi l'interrompt — un redimensionnement
      // de la fenêtre, un geste, la commande suivante. Attendue ici, dans la
      // file strictement ordonnée du service, elle emportait alors toutes les
      // commandes suivantes : le lecteur s'affichait encore, mais n'obéissait
      // plus à rien.
      unawaited(viewer.goToPage(pageNumber: target, anchor: PdfPageAnchor.top));
    }
    // Mode page par page (pas de vue continue montée) ou vue en retard : on
    // écrit l'état, la vue suit.
    if (sink.state.currentPage != target) {
      sink.update((st) => st.copyWith(currentPage: target));
    }
  }

  Future<void> _setZoom(double zoom) async {
    final sink = _sink!;
    final target = zoom.clamp(PlaybackState.minZoom, PlaybackState.maxZoom);
    if (viewer.isReady) {
      // Même raison que pour le changement de page : l'animation du zoom se
      // lance, mais la file ne l'attend pas. Un cran de molette de plus, un
      // redimensionnement, et l'animation en cours était annulée — son futur
      // ne revenait jamais.
      unawaited(
        viewer.setZoom(viewer.visibleRect.center, target * viewer.coverScale),
      );
    }
    sink.update((st) => st.copyWith(zoom: target));
  }

  Future<void> _fit(FitMode mode) async {
    final sink = _sink!;
    if (!viewer.isReady) {
      // Page par page : « largeur » et « page » reviennent à l'échelle 1.
      sink.update((st) => st.copyWith(zoom: 1.0));
      return;
    }
    final cover = viewer.coverScale;
    final scale = switch (mode) {
      FitMode.width => cover,
      FitMode.page => viewer.alternativeFitScale ?? viewer.minScale,
    };
    // Sans animation, et c'est le point le plus important des trois. Cet
    // ajustement est demandé par la vue à chaque image d'un redimensionnement
    // de fenêtre. Animé sur 200 ms et attendu dans la file, il était annulé
    // dès l'image suivante : pdfrx repositionne lui-même la vue à chaque
    // changement de taille, et tout nouveau déplacement remet son animation
    // à zéro. Or une animation annulée ne rend jamais la main. Le premier
    // redimensionnement d'un document suffisait donc à figer le lecteur pour
    // de bon — et tant qu'il durait, la page restait floue, toujours en
    // transition entre deux tailles. Une mise en page suit la fenêtre sans
    // délai ; elle ne s'anime pas.
    await viewer.setZoom(
      viewer.visibleRect.center,
      scale,
      duration: Duration.zero,
    );
    sink.update((st) => st.copyWith(zoom: cover > 0 ? scale / cover : 1.0));
  }

  Timer? _scrollNote;

  /// Publie la position de la vue dans le document, dix fois par seconde au
  /// plus.
  ///
  /// Le lecteur ne publiait que la page courante. Défiler lentement dans une
  /// page ne changeait donc rien à l'état, et la lecture miroir n'avait rien
  /// à transmettre : l'autre appareil ne suivait que les sauts de page.
  ///
  /// Pas à chaque image : la vue bouge soixante fois par seconde pendant un
  /// défilement, et autant de mises à jour de l'état le rendraient saccadé.
  void _noteScroll() {
    _scrollNote ??= Timer(const Duration(milliseconds: 100), () {
      _scrollNote = null;
      final sink = _sink;
      if (sink == null || _session == null || !viewer.isReady) return;
      final double fraction;
      try {
        final visible = viewer.visibleRect;
        final travel = viewer.documentSize.height - visible.height;
        fraction = travel > 0 ? (visible.top / travel).clamp(0.0, 1.0) : 0.0;
      } on Object {
        // Vue en cours de mise en page : rien à publier pour l'instant.
        return;
      }
      if (!fraction.isFinite) return;
      if ((fraction - sink.state.scrollFraction).abs() < 0.0005) return;
      sink.update((st) => st.copyWith(scrollFraction: fraction));
    });
  }

  Future<void> _closeSession() async {
    _scrollNote?.cancel();
    _scrollNote = null;
    _targetPage = null;
    final current = _session;
    if (current == null) return;
    _publish(null);
    try {
      await current.document.dispose();
    } on Object {
      // Document déjà libéré par pdfium : sans conséquence.
    }
  }

  @override
  Future<void> close() async {
    await _closeSession();
    _sink?.update(
      (st) => st.copyWith(
        clearFile: true,
        status: PlaybackStatus.idle,
        currentPage: 0,
        totalPages: 0,
        clearError: true,
      ),
    );
    _sink = null;
  }

  @override
  Future<void> dispose() async {
    viewer.removeListener(_onViewerChanged);
    await _closeSession();
    await _sessions.close();
  }
}
