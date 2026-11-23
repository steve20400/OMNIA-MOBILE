import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/pdf_note.dart';
import '../../core/providers.dart';
import '../../core/services/pdf_notes_engine.dart';
import '../document_search_provider.dart';
import '../theme/omnia_theme.dart';
import 'omnia_button.dart';

/// Le mode « poser une note » : le prochain clic sur une page y pose une
/// note. Un état d'interface, comme le mode modification des textes ; la
/// note elle-même passe par le bus.
final pdfNoteModeProvider = NotifierProvider<PdfNoteMode, bool>(PdfNoteMode.new);

class PdfNoteMode extends Notifier<bool> {
  /// Un autre PDF, ou le même rouvert après une note : le mode s'éteint.
  @override
  bool build() {
    ref.watch(pdfSessionProvider.select((s) => s?.document));
    return false;
  }

  void toggle() => state = !state;

  void stop() => state = false;
}

/// Vrai quand du texte est sélectionné dans le PDF affiché : le bouton des
/// notes propose alors de commenter ce passage.
final pdfTextSelectedProvider = NotifierProvider<PdfTextSelected, bool>(PdfTextSelected.new);

class PdfTextSelected extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(pdfSessionProvider.select((s) => s?.document));
    return false;
  }

  void set(bool selected) => state = selected;
}

/// Commente le passage sélectionné dans [viewer] : il est surligné, et le
/// commentaire s'y attache, par le bus — une commande par page couverte.
Future<void> commentPdfSelection(BuildContext context, WidgetRef ref, PdfViewerController viewer) async {
  final delegate = viewer.textSelectionDelegate;
  if (!delegate.hasSelectedText) return;
  final ranges = await delegate.getSelectedTextRanges();
  final quoted = (await delegate.getSelectedText()).trim();
  if (ranges.isEmpty || !context.mounted) return;
  final decision = await showPdfNoteDialog(
    context,
    page: ranges.first.pageNumber,
    editable: true,
    quote: quoted,
  );
  if (decision is! PdfNoteSaved || decision.text.isEmpty) return;
  for (final range in ranges) {
    final characters = range.pageText.charRects.sublist(range.start, range.end);
    final quads = pdfLineQuads(characters);
    if (quads.isEmpty) continue;
    ref.dispatch(AddPdfHighlight(page: range.pageNumber, quads: quads, text: decision.text));
  }
  await delegate.clearTextSelection();
}

/// Ce que la fenêtre d'une note a décidé.
sealed class PdfNoteDecision {
  const PdfNoteDecision();
}

/// Garder ce texte.
final class PdfNoteSaved extends PdfNoteDecision {
  const PdfNoteSaved(this.text);
  final String text;
}

/// Effacer la note.
final class PdfNoteRemoved extends PdfNoteDecision {
  const PdfNoteRemoved();
}

/// Ouvre la fenêtre d'une note : une note neuve si [note] est `null`, sinon
/// celle-ci, à relire et, si [editable], à modifier ou effacer.
///
/// `null` si l'on referme sans rien décider.
Future<PdfNoteDecision?> showPdfNoteDialog(
  BuildContext context, {
  PdfNote? note,
  required int page,
  required bool editable,
  String? quote,
}) {
  return showDialog<PdfNoteDecision>(
    context: context,
    barrierColor: context.colors.overlayScrim,
    builder: (_) => _PdfNoteDialog(note: note, page: page, editable: editable, quote: quote),
  );
}

class _PdfNoteDialog extends StatefulWidget {
  const _PdfNoteDialog({required this.note, required this.page, required this.editable, this.quote});

  final PdfNote? note;
  final int page;
  final bool editable;

  /// Le passage commenté, rappelé au-dessus du champ.
  final String? quote;

  @override
  State<_PdfNoteDialog> createState() => _PdfNoteDialogState();
}

class _PdfNoteDialogState extends State<_PdfNoteDialog> {
  late final TextEditingController _text = TextEditingController(text: widget.note?.text ?? '');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final text = _text.text.trim();
    // Une note neuve sans texte ne sert à rien : on referme sans rien poser.
    if (text.isEmpty && widget.note == null) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(PdfNoteSaved(text));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final note = widget.note;
    final quote = widget.quote;
    final title = note == null
        ? (quote == null ? 'Nouvelle note' : 'Commenter ce passage')
        : (note.highlight ? 'Commentaire' : 'Note');
    final author = note?.author;

    return Dialog(
      backgroundColor: colors.curtain,
      insetPadding: const EdgeInsets.all(OmniaMetrics.space4),
      shape: RoundedRectangleBorder(
        borderRadius: OmniaMetrics.overlayRadius,
        side: BorderSide(color: colors.seam),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(OmniaMetrics.space5),
          child: CallbackShortcuts(
            // Ctrl+Entrée enregistre, comme dans la plupart des éditeurs ;
            // Entrée seule passe à la ligne.
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
                if (widget.editable) _save();
              },
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.sticky_note_2_outlined, color: colors.projector),
                    const SizedBox(width: OmniaMetrics.space2),
                    Expanded(
                      child: Text(
                        title,
                        style: type.sectionTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text('Page ${widget.page}', style: type.secondary),
                  ],
                ),
                if (author != null && author.isNotEmpty) ...[
                  const SizedBox(height: OmniaMetrics.space1),
                  Text(
                    'Par $author',
                    style: type.secondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (quote != null && quote.isNotEmpty) ...[
                  const SizedBox(height: OmniaMetrics.space3),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0x33FFD600),
                      borderRadius: OmniaMetrics.controlRadius,
                      border: Border(left: BorderSide(color: colors.projector, width: 3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(OmniaMetrics.space2),
                      child: Text(
                        '« $quote »',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: type.secondary.copyWith(color: colors.screen),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: OmniaMetrics.space4),
                TextField(
                  controller: _text,
                  autofocus: widget.editable,
                  readOnly: !widget.editable,
                  minLines: 4,
                  maxLines: 10,
                  style: type.body.copyWith(color: colors.screen),
                  decoration: InputDecoration(
                    hintText: 'Votre remarque sur cette page…',
                    hintStyle: type.body.copyWith(color: colors.dust),
                    filled: true,
                    fillColor: colors.velvet,
                    border: OutlineInputBorder(
                      borderRadius: OmniaMetrics.controlRadius,
                      borderSide: BorderSide(color: colors.seam),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: OmniaMetrics.controlRadius,
                      borderSide: BorderSide(color: colors.seam),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: OmniaMetrics.controlRadius,
                      borderSide: BorderSide(color: colors.projector),
                    ),
                  ),
                ),
                if (widget.editable) ...[
                  const SizedBox(height: OmniaMetrics.space2),
                  Text(
                    'La note est écrite dans le PDF : les autres lecteurs la verront aussi.',
                    style: type.caption.copyWith(color: colors.dust),
                  ),
                ],
                const SizedBox(height: OmniaMetrics.space4),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: OmniaMetrics.space2,
                  runSpacing: OmniaMetrics.space2,
                  children: [
                    if (widget.editable && note != null)
                      OmniaButton(
                        label: 'Supprimer',
                        icon: Icons.delete_outline_rounded,
                        onPressed: () => Navigator.of(context).pop(const PdfNoteRemoved()),
                      ),
                    OmniaButton(
                      label: widget.editable ? 'Annuler' : 'Fermer',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    if (widget.editable)
                      OmniaButton(
                        label: note == null ? 'Poser la note' : 'Enregistrer',
                        icon: Icons.check_rounded,
                        primary: true,
                        onPressed: _save,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ouvre une note posée et applique ce qu'on en décide, par le bus.
Future<void> openPdfNote(BuildContext context, WidgetRef ref, PdfNote note, {required bool editable}) async {
  final decision = await showPdfNoteDialog(context, note: note, page: note.page, editable: editable);
  switch (decision) {
    case PdfNoteSaved(:final text) when text != note.text:
      ref.dispatch(EditPdfNote(page: note.page, index: note.index, text: text));
    case PdfNoteRemoved():
      ref.dispatch(DeletePdfNote(page: note.page, index: note.index));
    default:
      break;
  }
}

/// Demande le texte d'une note neuve et la pose au point ([x], [y]) de la
/// page [page], par le bus.
Future<void> addPdfNoteAt(
  BuildContext context,
  WidgetRef ref, {
  required int page,
  required double x,
  required double y,
}) async {
  final decision = await showPdfNoteDialog(context, page: page, editable: true);
  if (decision is PdfNoteSaved && decision.text.isNotEmpty) {
    ref.dispatch(AddPdfNote(page: page, x: x, y: y, text: decision.text));
  }
}

/// Les marqueurs des notes d'une page, pour [PdfViewerParams.pageOverlaysBuilder].
///
/// Chaque marqueur couvre la zone de l'annotation : par-dessus l'icône que
/// pdfium dessine, il la met en lumière et s'ouvre d'un clic.
List<Widget> pdfNoteMarkers({
  required Rect pageRect,
  required PdfPage page,
  required List<PdfNote> notes,
  required void Function(PdfNote note) onOpen,
}) {
  final size = pageRect.size;
  return [
    for (final note in notes)
      if (note.page == page.pageNumber) _marker(note, page, size, onOpen),
  ];
}

Widget _marker(PdfNote note, PdfPage page, Size scaled, void Function(PdfNote) onOpen) {
  final a = PdfPoint(note.left, note.top).toOffset(page: page, scaledPageSize: scaled);
  final b = PdfPoint(note.right, note.bottom).toOffset(page: page, scaledPageSize: scaled);
  final rect = Rect.fromPoints(a, b);
  // Assez grand pour être visé, même dézoomé. Sur un passage surligné, le
  // marqueur se pose en coin, à cheval sur le bord : il ne cache pas le
  // texte commenté.
  final side = note.highlight ? 20.0 : rect.longestSide.clamp(18.0, 40.0);
  return Positioned(
    left: note.highlight ? rect.left - side * 0.6 : rect.left,
    top: note.highlight ? rect.top - side * 0.6 : rect.top,
    width: side,
    height: side,
    child: PdfOverlayInteractionRegion(
      onTap: (_) {
        onOpen(note);
        return true;
      },
      child: Tooltip(
        message: note.text.isEmpty ? 'Note sans texte' : note.text,
        waitDuration: const Duration(milliseconds: 300),
        child: _NoteMarker(size: side),
      ),
    ),
  );
}

class _NoteMarker extends StatelessWidget {
  const _NoteMarker({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.projector,
          borderRadius: BorderRadius.circular(size * 0.28),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Center(
          child: Icon(
            Icons.sticky_note_2_rounded,
            size: size * 0.62,
            // Sombre sur l'ambre, dans les deux thèmes : le blanc n'y a pas
            // assez de contraste.
            color: const Color(0xFF1A1418),
          ),
        ),
      ),
    );
  }
}
