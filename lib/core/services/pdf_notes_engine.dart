import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx/pdfrx.dart';

import '../models/pdf_note.dart';

/// Côté d'une note posée par OMNIA, en points PDF : la taille habituelle de
/// l'icône de bulle dans les lecteurs.
const double pdfNoteSize = 24;

/// Lit et écrit les notes d'un PDF ouvert.
///
/// Injectable : pdfium est une bibliothèque native que les tests de widgets
/// n'ont pas.
abstract class PdfNotesEngine {
  const PdfNotesEngine();

  /// Les notes du document, page par page.
  Future<List<PdfNote>> read(PdfDocument document);

  /// Applique [changes] au document ouvert et rend le PDF complet, prêt à
  /// remplacer le fichier.
  Future<Uint8List> apply(PdfDocument document, List<PdfNoteChange> changes);
}

/// Aucun moteur : pas de notes à lire, aucune à écrire.
class NoPdfNotesEngine extends PdfNotesEngine {
  const NoPdfNotesEngine();

  @override
  Future<List<PdfNote>> read(PdfDocument document) async => const [];

  @override
  Future<Uint8List> apply(PdfDocument document, List<PdfNoteChange> changes) =>
      Future.error(UnsupportedError('Notes indisponibles'));
}

/// Les notes par pdfium, celui que pdfrx embarque.
///
/// pdfium n'est pas réentrant : tout passe par le fil de travail de pdfrx
/// ([PdfrxEntryFunctions.compute]), le même qui rend les pages. Les appels
/// s'y alignent au lieu de se croiser.
class PdfiumNotesEngine extends PdfNotesEngine {
  const PdfiumNotesEngine({this.author = 'OMNIA'});

  /// L'auteur inscrit dans les notes. « OMNIA » plutôt que le nom de la
  /// session : un PDF annoté se partage, et le nom de l'ordinateur n'a pas à
  /// voyager avec lui.
  final String author;

  /// Pages lues par passage : entre deux, le fil reprend le rendu des pages.
  /// Un document de mille pages ne fige pas l'affichage le temps d'en
  /// relever les notes.
  static const int _pagesPerPass = 24;

  @override
  Future<List<PdfNote>> read(PdfDocument document) async {
    final notes = <PdfNote>[];
    final pages = document.pages.length;
    for (var start = 0; start < pages; start += _pagesPerPass) {
      final handle = await document.useNativeDocumentHandle((handle) => handle);
      notes.addAll(
        await PdfrxEntryFunctions.instance.compute(
          _readNotes,
          (document: handle, start: start, end: math.min(start + _pagesPerPass, pages)),
        ),
      );
    }
    return notes;
  }

  @override
  Future<Uint8List> apply(PdfDocument document, List<PdfNoteChange> changes) async {
    final handle = await document.useNativeDocumentHandle((handle) => handle);
    final applied = await PdfrxEntryFunctions.instance.compute(
      _applyChanges,
      (document: handle, changes: changes, author: author, date: pdfDate(DateTime.now())),
    );
    if (!applied) throw StateError('pdfium a refusé la modification');
    // Enregistrement incrémental : les changements s'ajoutent à la fin du
    // fichier sans réécrire le reste. Une signature numérique reste valable
    // pour la partie signée.
    return document.encodePdf(incremental: true);
  }
}

/// Une date au format des PDF : « D:20261119143000+01'00' ».
String pdfDate(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  final offset = time.timeZoneOffset;
  final minutes = offset.inMinutes.abs();
  final sign = offset.isNegative ? '-' : '+';
  return 'D:${time.year.toString().padLeft(4, '0')}${two(time.month)}${two(time.day)}'
      '${two(time.hour)}${two(time.minute)}${two(time.second)}'
      "$sign${two(minutes ~/ 60)}'${two(minutes % 60)}'";
}

// --- Sur le fil de pdfrx -------------------------------------------------------------
//
// Les fonctions qui suivent s'exécutent dans l'isolat de travail de pdfrx :
// elles ne reçoivent que des valeurs simples, et chargent pdfium comme pdfrx
// le charge lui-même.

pdfium_bindings.PDFium? _pdfiumInstance;

pdfium_bindings.PDFium get _pdfium =>
    _pdfiumInstance ??= pdfium_bindings.getPdfium(modulePath: Pdfrx.pdfiumModulePath);

/// FPDF_ANNOT_TEXT : la note « bulle ».
const int _subtypeText = 1;

/// FPDF_ANNOT_HIGHLIGHT : un passage surligné, qui porte son commentaire.
const int _subtypeHighlight = 9;

/// Les lignes d'un passage sélectionné, en rectangles : quatre nombres par
/// ligne (gauche, haut, droite, bas), à partir des rectangles de ses
/// caractères.
///
/// Les caractères d'une même ligne se chevauchent en hauteur ; un caractère
/// qui ne chevauche plus la ligne en cours en ouvre une nouvelle. Les
/// caractères sans surface — espaces, retours à la ligne — ne comptent pas.
List<double> pdfLineQuads(Iterable<PdfRect> characters) {
  final lines = <List<double>>[];
  for (final c in characters) {
    if (c.right - c.left <= 0 || c.top - c.bottom <= 0) continue;
    final middle = (c.top + c.bottom) / 2;
    final last = lines.isEmpty ? null : lines.last;
    if (last != null && middle <= last[1] && middle >= last[3]) {
      last[0] = math.min(last[0], c.left);
      last[1] = math.max(last[1], c.top);
      last[2] = math.max(last[2], c.right);
      last[3] = math.min(last[3], c.bottom);
    } else {
      lines.add([c.left, c.top, c.right, c.bottom]);
    }
  }
  return [for (final line in lines) ...line];
}

/// Imprimée avec la page, et de taille fixe quel que soit le zoom ou la
/// rotation : FPDF_ANNOT_FLAG_PRINT | NOZOOM | NOROTATE.
const int _noteFlags = 4 | 8 | 16;

List<PdfNote> _readNotes(({int document, int start, int end}) message) {
  final lib = _pdfium;
  final document = pdfium_bindings.FPDF_DOCUMENT.fromAddress(message.document);
  final notes = <PdfNote>[];
  using((arena) {
    final rect = arena<pdfium_bindings.FS_RECTF>();
    for (var pageIndex = message.start; pageIndex < message.end; pageIndex++) {
      final page = lib.FPDF_LoadPage(document, pageIndex);
      if (page == nullptr) continue;
      try {
        final count = lib.FPDFPage_GetAnnotCount(page);
        for (var index = 0; index < count; index++) {
          final annot = lib.FPDFPage_GetAnnot(page, index);
          if (annot == nullptr) continue;
          try {
            final subtype = lib.FPDFAnnot_GetSubtype(annot);
            if (subtype != _subtypeText && subtype != _subtypeHighlight) continue;
            final text = _stringValue(lib, annot, 'Contents', arena) ?? '';
            // Un surlignage sans commentaire n'est pas une note : il reste
            // dessiné sur la page, sans marqueur.
            if (subtype == _subtypeHighlight && text.trim().isEmpty) continue;
            if (lib.FPDFAnnot_GetRect(annot, rect) == 0) continue;
            notes.add(
              PdfNote(
                page: pageIndex + 1,
                index: index,
                left: rect.ref.left,
                top: math.max(rect.ref.top, rect.ref.bottom),
                right: rect.ref.right,
                bottom: math.min(rect.ref.top, rect.ref.bottom),
                text: text,
                author: _stringValue(lib, annot, 'T', arena),
                highlight: subtype == _subtypeHighlight,
              ),
            );
          } finally {
            lib.FPDFPage_CloseAnnot(annot);
          }
        }
      } finally {
        lib.FPDF_ClosePage(page);
      }
    }
  });
  return notes;
}

bool _applyChanges(
  ({int document, List<PdfNoteChange> changes, String author, String date}) message,
) {
  final lib = _pdfium;
  final document = pdfium_bindings.FPDF_DOCUMENT.fromAddress(message.document);
  return using((arena) {
    var applied = true;
    for (final change in message.changes) {
      final pageNumber = switch (change) {
        PdfNoteAdded(:final page) => page,
        PdfHighlightAdded(:final page) => page,
        PdfNoteEdited(:final page) => page,
        PdfNoteDeleted(:final page) => page,
      };
      final page = lib.FPDF_LoadPage(document, pageNumber - 1);
      if (page == nullptr) {
        applied = false;
        continue;
      }
      try {
        final done = switch (change) {
          PdfNoteAdded() => _add(lib, page, change, message.author, message.date, arena),
          PdfHighlightAdded() => _addHighlight(lib, page, change, message.author, message.date, arena),
          PdfNoteEdited() => _edit(lib, page, change, message.date, arena),
          PdfNoteDeleted() => _delete(lib, page, change, arena),
        };
        applied = applied && done;
      } finally {
        lib.FPDF_ClosePage(page);
      }
    }
    return applied;
  });
}

bool _add(
  pdfium_bindings.PDFium lib,
  pdfium_bindings.FPDF_PAGE page,
  PdfNoteAdded change,
  String author,
  String date,
  Arena arena,
) {
  final annot = lib.FPDFPage_CreateAnnot(page, _subtypeText);
  if (annot == nullptr) return false;
  try {
    final rect = arena<pdfium_bindings.FS_RECTF>();
    rect.ref
      ..left = change.x
      ..top = change.y
      ..right = change.x + pdfNoteSize
      ..bottom = change.y - pdfNoteSize;
    final written = lib.FPDFAnnot_SetRect(annot, rect) != 0 &&
        _setString(lib, annot, 'Contents', change.text, arena) &&
        _setString(lib, annot, 'T', author, arena) &&
        _setString(lib, annot, 'M', date, arena) &&
        _setString(lib, annot, 'CreationDate', date, arena);
    // L'ambre du projecteur et les drapeaux d'affichage : un plus, que
    // certains lecteurs ignorent. Leur échec n'annule pas la note.
    lib.FPDFAnnot_SetColor(
      annot,
      pdfium_bindings.FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color,
      242,
      180,
      65,
      255,
    );
    lib.FPDFAnnot_SetFlags(annot, _noteFlags);
    return written;
  } finally {
    lib.FPDFPage_CloseAnnot(annot);
  }
}

bool _addHighlight(
  pdfium_bindings.PDFium lib,
  pdfium_bindings.FPDF_PAGE page,
  PdfHighlightAdded change,
  String author,
  String date,
  Arena arena,
) {
  final quads = change.quads;
  if (quads.length < 4 || quads.length % 4 != 0) return false;
  final annot = lib.FPDFPage_CreateAnnot(page, _subtypeHighlight);
  if (annot == nullptr) return false;
  try {
    final point = arena<pdfium_bindings.FS_QUADPOINTSF>();
    var left = double.infinity;
    var top = double.negativeInfinity;
    var right = double.negativeInfinity;
    var bottom = double.infinity;
    var written = true;
    for (var i = 0; i + 3 < quads.length; i += 4) {
      final l = quads[i];
      final t = quads[i + 1];
      final r = quads[i + 2];
      final b = quads[i + 3];
      // L'ordre de la norme : haut gauche, haut droite, bas gauche, bas droite.
      point.ref
        ..x1 = l
        ..y1 = t
        ..x2 = r
        ..y2 = t
        ..x3 = l
        ..y3 = b
        ..x4 = r
        ..y4 = b;
      written = lib.FPDFAnnot_AppendAttachmentPoints(annot, point) != 0 && written;
      left = math.min(left, l);
      top = math.max(top, t);
      right = math.max(right, r);
      bottom = math.min(bottom, b);
    }
    final rect = arena<pdfium_bindings.FS_RECTF>();
    rect.ref
      ..left = left
      ..top = top
      ..right = right
      ..bottom = bottom;
    written = written &&
        lib.FPDFAnnot_SetRect(annot, rect) != 0 &&
        _setString(lib, annot, 'Contents', change.text, arena) &&
        _setString(lib, annot, 'T', author, arena) &&
        _setString(lib, annot, 'M', date, arena) &&
        _setString(lib, annot, 'CreationDate', date, arena);
    // Le jaune des surligneurs ; les lecteurs le dessinent par-dessus le
    // texte, en transparence.
    lib.FPDFAnnot_SetColor(
      annot,
      pdfium_bindings.FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color,
      255,
      214,
      0,
      255,
    );
    lib.FPDFAnnot_SetFlags(annot, 4);
    return written;
  } finally {
    lib.FPDFPage_CloseAnnot(annot);
  }
}

bool _edit(
  pdfium_bindings.PDFium lib,
  pdfium_bindings.FPDF_PAGE page,
  PdfNoteEdited change,
  String date,
  Arena arena,
) {
  final annot = lib.FPDFPage_GetAnnot(page, change.index);
  if (annot == nullptr) return false;
  try {
    if (!_isNote(lib.FPDFAnnot_GetSubtype(annot))) return false;
    return _setString(lib, annot, 'Contents', change.text, arena) &&
        _setString(lib, annot, 'M', date, arena);
  } finally {
    lib.FPDFPage_CloseAnnot(annot);
  }
}

bool _delete(
  pdfium_bindings.PDFium lib,
  pdfium_bindings.FPDF_PAGE page,
  PdfNoteDeleted change,
  Arena arena,
) {
  final annot = lib.FPDFPage_GetAnnot(page, change.index);
  if (annot == nullptr) return false;
  var popupIndex = -1;
  try {
    if (!_isNote(lib.FPDFAnnot_GetSubtype(annot))) return false;
    // La fenêtre surgissante d'une note est une annotation à part : effacée
    // seule, la note laisserait derrière elle un cadre vide.
    final popup = lib.FPDFAnnot_GetLinkedAnnot(annot, 'Popup'.toNativeUtf8(allocator: arena).cast());
    if (popup != nullptr) {
      popupIndex = lib.FPDFPage_GetAnnotIndex(page, popup);
      lib.FPDFPage_CloseAnnot(popup);
    }
  } finally {
    lib.FPDFPage_CloseAnnot(annot);
  }
  // Le rang le plus haut d'abord : effacer l'autre d'abord le décalerait.
  final indices = {change.index, if (popupIndex >= 0) popupIndex}.toList()
    ..sort((a, b) => b.compareTo(a));
  var removed = true;
  for (final index in indices) {
    removed = lib.FPDFPage_RemoveAnnot(page, index) != 0 && removed;
  }
  return removed;
}

/// Une bulle ou un passage surligné : ce qu'OMNIA modifie ou efface, et rien
/// d'autre — un rang périmé ne touche jamais une autre sorte d'annotation.
bool _isNote(int subtype) => subtype == _subtypeText || subtype == _subtypeHighlight;

String? _stringValue(
  pdfium_bindings.PDFium lib,
  pdfium_bindings.FPDF_ANNOTATION annot,
  String key,
  Arena arena,
) {
  final name = key.toNativeUtf8(allocator: arena).cast<Char>();
  // La longueur rendue compte des octets, zéro final compris.
  final length = lib.FPDFAnnot_GetStringValue(annot, name, nullptr, 0);
  if (length <= 2) return null;
  final buffer = arena.allocate<UnsignedShort>(length);
  lib.FPDFAnnot_GetStringValue(annot, name, buffer, length);
  final value = buffer.cast<Utf16>().toDartString();
  return value.isEmpty ? null : value;
}

bool _setString(
  pdfium_bindings.PDFium lib,
  pdfium_bindings.FPDF_ANNOTATION annot,
  String key,
  String value,
  Arena arena,
) {
  return lib.FPDFAnnot_SetStringValue(
        annot,
        key.toNativeUtf8(allocator: arena).cast<Char>(),
        value.toNativeUtf16(allocator: arena).cast<UnsignedShort>(),
      ) !=
      0;
}
