import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/controllers/text_controller.dart';
import '../../core/providers.dart';
import '../document_search.dart';
import '../document_ui_controller.dart';
import '../theme/omnia_theme.dart';

/// Vue d'un fichier texte ou Markdown, en lecture seule.
///
/// Le thème de lecture est indépendant de celui de l'application : un texte
/// se lit sur fond clair par défaut (comme une page), et bascule en sombre
/// avec `Ctrl+D`. La taille de police suit le zoom (`Ctrl+molette`), la
/// position de défilement est renvoyée au core pour être mémorisée.
class TextView extends ConsumerStatefulWidget {
  const TextView({super.key, required this.document, this.search});

  final TextDocument document;

  /// Recherche courante, pour surligner les occurrences (texte brut).
  final PlainTextSearch? search;

  @override
  ConsumerState<TextView> createState() => _TextViewState();
}

class _TextViewState extends ConsumerState<TextView> {
  final ScrollController _scroll = ScrollController();
  late final TextEditingController _editController;
  Timer? _reportDebounce;
  Timer? _autoSaveTimer;
  double? _pendingRestore;
  int _lastMatch = -1;
  int _seenSaveRequest = 0;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.document.text);
    _scroll.addListener(_onScrolled);
    widget.search?.addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(TextView old) {
    super.didUpdateWidget(old);
    if (old.search != widget.search) {
      old.search?.removeListener(_onSearchChanged);
      widget.search?.addListener(_onSearchChanged);
    }
    if (old.document.path != widget.document.path) {
      if (_hasUnsavedChanges) {
        _autoSaveTimer?.cancel();
        try {
          File(old.document.path).writeAsStringSync(_editController.text);
        } catch (_) {}
      }
      _lastMatch = -1;
      _hasUnsavedChanges = false;
      _editController.text = widget.document.text;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } else {
      final currentFraction = ref.read(playbackStateProvider).scrollFraction;
      if (currentFraction > 0.01) {
        _restoreIfNeeded(currentFraction);
      }
    }
  }

  @override
  void dispose() {
    _reportDebounce?.cancel();
    _autoSaveTimer?.cancel();
    if (_hasUnsavedChanges) {
      try {
        File(widget.document.path).writeAsStringSync(_editController.text, flush: true);
      } catch (_) {}
    }
    _scroll.dispose();
    _editController.dispose();
    widget.search?.removeListener(_onSearchChanged);
    super.dispose();
  }

  Future<void> _saveFile({bool silent = false}) async {
    _autoSaveTimer?.cancel();
    try {
      final file = File(widget.document.path);
      file.writeAsStringSync(_editController.text, flush: true);
      _hasUnsavedChanges = false;
      if (mounted) {
        ref.read(documentUiProvider.notifier).clearDraft();
        ref.read(textControllerProvider).updateText(_editController.text);
        ref.read(documentUiProvider.notifier).setUnsavedChanges(false);
        if (!silent) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('Fichier enregistré avec succès.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l’enregistrement : $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _onTextChanged(String text) {
    _hasUnsavedChanges = true;
    ref.read(documentUiProvider.notifier).setDraft(
          path: widget.document.path,
          text: text,
        );
    _scheduleAutoSave();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    final prefs = ref.read(preferencesProvider);
    if (!prefs.docAutoSave) return;
    _autoSaveTimer = Timer(Duration(seconds: prefs.docAutoSaveIntervalSeconds), () {
      if (mounted && ref.read(documentUiProvider).hasUnsavedChanges) {
        _saveFile(silent: true);
      }
    });
  }

  void _onScrolled() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return;
    final fraction = (_scroll.offset / max).clamp(0.0, 1.0);
    // Éviter qu'une réinitialisation temporaire du viewport à 0 n'écrase
    // la position de lecture sauvegardée.
    if (fraction == 0.0 && ref.read(playbackStateProvider).scrollFraction > 0.01) return;
    _reportDebounce?.cancel();
    _reportDebounce = Timer(const Duration(milliseconds: 100), () {
      if (mounted) ref.dispatch(ScrollTo(fraction));
    });
  }

  /// Amène l'occurrence courante à l'écran, approximativement : la position
  /// est estimée par la proportion de texte qui précède.
  void _onSearchChanged() {
    final search = widget.search;
    if (search == null || !_scroll.hasClients) return;
    final match = search.state.currentMatch;
    if (match == null || search.state.current == _lastMatch) {
      setState(() {});
      return;
    }
    _lastMatch = search.state.current;
    final text = widget.document.text;
    final fraction = text.isEmpty ? 0.0 : match.start / text.length;
    final target = (_scroll.position.maxScrollExtent * fraction - 120)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target, duration: OmniaMotion.panel, curve: OmniaMotion.panelCurve);
    setState(() {});
  }

  void _restoreIfNeeded(double fraction) {
    if (fraction <= 0 || _pendingRestore == fraction) return;
    _pendingRestore = fraction;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (max > 0) {
        _scroll.jumpTo(max * fraction);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scroll.hasClients) return;
          final retryMax = _scroll.position.maxScrollExtent;
          if (retryMax > 0) _scroll.jumpTo(retryMax * fraction);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = ref.watch(playbackStateProvider.select((s) => s.zoom));
    final dark = ref.watch(playbackStateProvider.select((s) => s.readingDark));
    final miniPlayer = ref.watch(playbackStateProvider.select((s) => s.miniPlayer));

    // Le core demande une position (reprise, télécommande) : on s'y rend une
    // fois, sans boucler avec les positions qu'on lui renvoie nous-mêmes.
    ref.listen<double>(playbackStateProvider.select((s) => s.scrollFraction), (prev, next) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (max <= 0) return;
      final currentFraction = _scroll.offset / max;
      if ((currentFraction - next).abs() > 0.02) _scroll.jumpTo(max * next);
    });

    final reading = ReadingPalette.of(dark: dark);
    final baseSize = (miniPlayer ? 12.5 : 15.0) * scale;
    final docPadding = miniPlayer
        ? const EdgeInsets.all(OmniaMetrics.space2)
        : const EdgeInsets.symmetric(
            horizontal: OmniaMetrics.space8,
            vertical: OmniaMetrics.space6,
          );
    final body = TextStyle(
      fontFamily: OmniaFonts.ui,
      fontSize: baseSize,
      height: 1.6,
      color: reading.ink,
    );
    final mono = TextStyle(
      fontFamily: OmniaFonts.mono,
      fontSize: baseSize * 0.92,
      height: 1.55,
      color: reading.ink,
    );

    final doc = widget.document;
    final ui = ref.watch(documentUiProvider);
    _restoreIfNeeded(ref.read(playbackStateProvider).scrollFraction);

    ref.listen<bool>(documentUiProvider.select((u) => u.isEditing), (prev, next) {
      if (prev == true && next == false && ref.read(documentUiProvider).hasUnsavedChanges) {
        _autoSaveTimer?.cancel();
        _saveFile(silent: true);
      }
    });

    ref.listen<bool>(documentUiProvider.select((u) => u.hasUnsavedChanges), (prev, next) {
      if (prev == true && next == false) {
        _hasUnsavedChanges = false;
        _autoSaveTimer?.cancel();
      }
    });

    if (ui.saveRequest != _seenSaveRequest) {
      _seenSaveRequest = ui.saveRequest;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _saveFile();
      });
    }

    final Widget content;
    if (ui.isEditing) {
      content = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveFile,
        },
        child: Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: docPadding,
            child: SizedBox(
              width: double.infinity,
              child: TextField(
                controller: _editController,
                maxLines: null,
                style: doc.isMarkdown ? body : mono,
                cursorColor: reading.accent,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: _onTextChanged,
              ),
            ),
          ),
        ),
      );
    } else if (doc.isMarkdown) {
      content = Markdown(
        data: doc.text,
        controller: _scroll,
        selectable: true,
        padding: docPadding,
        styleSheet: _markdownStyle(reading, body, mono, baseSize),
      );
    } else {
      content = Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: docPadding,
          child: SizedBox(
            width: double.infinity,
            child: SelectableText.rich(
              _highlighted(doc.text, widget.search?.state, mono, reading),
            ),
          ),
        ),
      );
    }

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (metrics) {
        final targetFraction = ref.read(playbackStateProvider).scrollFraction;
        if (targetFraction > 0.01 && metrics.metrics.maxScrollExtent > 0) {
          final currentFraction = metrics.metrics.pixels / metrics.metrics.maxScrollExtent;
          if ((currentFraction - targetFraction).abs() > 0.02) {
            _scroll.jumpTo(metrics.metrics.maxScrollExtent * targetFraction);
          }
        }
        return false;
      },
      child: AnimatedContainer(
        duration: OmniaMotion.stage,
        curve: OmniaMotion.stageCurve,
        color: reading.paper,
        child: content,
      ),
    );
  }

  TextSpan _highlighted(String text, SearchState? search, TextStyle base, ReadingPalette reading) {
    if (search == null || search.matches.isEmpty) return TextSpan(text: text, style: base);

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (var i = 0; i < search.matches.length; i++) {
      final m = search.matches[i];
      if (m.start > cursor) spans.add(TextSpan(text: text.substring(cursor, m.start)));
      spans.add(
        TextSpan(
          text: text.substring(m.start, m.end),
          style: TextStyle(
            backgroundColor: i == search.current ? reading.highlightStrong : reading.highlight,
            color: reading.ink,
          ),
        ),
      );
      cursor = m.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return TextSpan(style: base, children: spans);
  }

  MarkdownStyleSheet _markdownStyle(
    ReadingPalette reading,
    TextStyle body,
    TextStyle mono,
    double base,
  ) {
    TextStyle heading(double factor) => body.copyWith(
          fontSize: base * factor,
          fontWeight: FontWeight.w600,
          height: 1.25,
          letterSpacing: -0.2,
        );
    return MarkdownStyleSheet(
      p: body,
      h1: heading(2.0),
      h2: heading(1.6),
      h3: heading(1.3),
      h4: heading(1.15),
      h5: heading(1.05),
      h6: heading(1.0),
      em: body.copyWith(fontStyle: FontStyle.italic),
      strong: body.copyWith(fontWeight: FontWeight.w600),
      a: body.copyWith(color: reading.accent, decoration: TextDecoration.underline),
      code: mono.copyWith(backgroundColor: reading.codeBackground),
      codeblockDecoration: BoxDecoration(
        color: reading.codeBackground,
        borderRadius: OmniaMetrics.controlRadius,
      ),
      codeblockPadding: const EdgeInsets.all(OmniaMetrics.space3),
      blockquote: body.copyWith(color: reading.inkMuted),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: reading.accent, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.symmetric(
        horizontal: OmniaMetrics.space4,
        vertical: OmniaMetrics.space1,
      ),
      listBullet: body,
      tableHead: body.copyWith(fontWeight: FontWeight.w600),
      tableBody: body,
      tableBorder: TableBorder.all(color: reading.rule),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: reading.rule)),
      ),
      blockSpacing: base * 0.9,
      listIndent: base * 1.6,
      h1Padding: EdgeInsets.only(top: base * 0.8),
      h2Padding: EdgeInsets.only(top: base * 0.6),
      h3Padding: EdgeInsets.only(top: base * 0.4),
    );
  }
}

/// Palette de lecture des documents, indépendante du thème de l'application.
///
/// Clair : papier chaud, encre presque noire. Sombre : même velours que la
/// salle, encre douce pour ne pas éblouir. L'accent reste le projecteur.
class ReadingPalette {
  const ReadingPalette({
    required this.paper,
    required this.ink,
    required this.inkMuted,
    required this.rule,
    required this.codeBackground,
    required this.highlight,
    required this.highlightStrong,
    required this.accent,
  });

  final Color paper;
  final Color ink;
  final Color inkMuted;
  final Color rule;
  final Color codeBackground;
  final Color highlight;
  final Color highlightStrong;
  final Color accent;

  static ReadingPalette of({required bool dark}) => dark ? _dark : _light;

  static const _light = ReadingPalette(
    paper: Color(0xFFF7F3EB),
    ink: Color(0xFF1B1720),
    inkMuted: Color(0xFF6B6472),
    rule: Color(0xFFDDD6CA),
    codeBackground: Color(0xFFEDE7DC),
    highlight: Color(0x66F2B441),
    highlightStrong: Color(0xFFF2B441),
    accent: Color(0xFFB07A17),
  );

  static const _dark = ReadingPalette(
    paper: Color(0xFF15121A),
    ink: Color(0xFFD9D3C7),
    inkMuted: Color(0xFF8B8494),
    rule: Color(0xFF2E2734),
    codeBackground: Color(0xFF1E1A25),
    highlight: Color(0x55F2B441),
    highlightStrong: Color(0xCCF2B441),
    accent: Color(0xFFF2B441),
  );
}
