import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/controllers/pdf_controller.dart';
import '../core/controllers/text_controller.dart';
import '../core/providers.dart';
import 'document_search.dart';

/// Session PDF courante (document ouvert, sommaire, contrôleur de vue), `null`
/// si ce n'est pas un PDF qui est affiché.
final pdfSessionProvider =
    NotifierProvider<PdfSessionNotifier, PdfSession?>(PdfSessionNotifier.new);

class PdfSessionNotifier extends Notifier<PdfSession?> {
  StreamSubscription<PdfSession?>? _subscription;

  @override
  PdfSession? build() {
    final controller = ref.watch(pdfControllerProvider);
    _subscription = controller.sessions.listen((s) => state = s);
    ref.onDispose(() => _subscription?.cancel());
    return controller.session;
  }
}

/// Document texte courant, `null` si ce n'est pas un texte qui est affiché.
final textDocumentProvider =
    NotifierProvider<TextDocumentNotifier, TextDocument?>(TextDocumentNotifier.new);

class TextDocumentNotifier extends Notifier<TextDocument?> {
  StreamSubscription<TextDocument?>? _subscription;

  @override
  TextDocument? build() {
    final controller = ref.watch(textControllerProvider);
    _subscription = controller.documents.listen((doc) => state = doc);
    ref.onDispose(() => _subscription?.cancel());
    return controller.document;
  }
}

/// Recherche pour le document courant. Recréée à chaque changement de document
/// pour que la barre de recherche reparte de zéro.
final documentSearchProvider = Provider<DocumentSearch?>((ref) {
  final text = ref.watch(textDocumentProvider);
  if (text != null) {
    final search = PlainTextSearch(text.text);
    ref.onDispose(search.dispose);
    return search;
  }
  // PDF : la recherche est fournie par la vue PDF via [pdfSearchProvider].
  return ref.watch(pdfSearchProvider);
});

/// Recherche PDF, enregistrée par la vue PDF quand un document est ouvert.
/// `null` tant qu'aucun PDF n'est affiché.
final pdfSearchProvider =
    NotifierProvider<PdfSearchRegistry, DocumentSearch?>(PdfSearchRegistry.new);

class PdfSearchRegistry extends Notifier<DocumentSearch?> {
  @override
  DocumentSearch? build() => null;

  void register(DocumentSearch? search) => state = search;
}
