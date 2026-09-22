import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Résultat de l'extraction d'un document Word / bureautique.
class ExtractedDocument {
  const ExtractedDocument({
    required this.text,
    required this.isMarkdown,
    required this.formatDescription,
  });

  /// Contenu extrait, formaté en Markdown si possible, sinon en texte brut.
  final String text;

  /// Vrai si le contenu est prêt pour le parseur Markdown.
  final bool isMarkdown;

  /// Description lisible du format (ex. `Word (DOCX)`).
  final String formatDescription;
}

/// Extrait le texte ou le Markdown d'un fichier de la famille Word / bureautique
/// (`.docx`, `.doc`, `.odt`, `.rtf`).
abstract final class DocReader {
  /// Lit un fichier bureautique depuis [path] et retourne son texte extrait.
  static Future<String> read(String path) async {
    final bytes = await File(path).readAsBytes();
    return extract(bytes, path).text;
  }

  /// Extrait le contenu de [bytes] selon l'extension de [path].
  static ExtractedDocument extract(Uint8List bytes, String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');

    // Si le document a été enregistré en texte brut ou Markdown (ex. modification et sauvegarde)
    if (!_isBinaryPackage(bytes)) {
      try {
        final text = utf8.decode(bytes);
        if (text.trim().isNotEmpty) {
          return ExtractedDocument(
            text: text,
            isMarkdown: ext == 'md' || ext == 'markdown' || text.trimLeft().startsWith('#'),
            formatDescription: ext.toUpperCase(),
          );
        }
      } catch (_) {}
    }

    switch (ext) {
      case 'docx' || 'dotx' || 'docm' || 'dotm':
        return _extractDocx(bytes);
      case 'pptx' || 'ppsx':
        return _extractPptx(bytes);
      case 'odt' || 'ott':
        return _extractOdt(bytes);
      case 'odp' || 'otp':
        return _extractOdp(bytes);
      case 'fodt' || 'fodp':
        return _extractFod(bytes, ext);
      case 'rtf':
        return _extractRtf(bytes);
      case 'doc' || 'ppt':
        return _extractDocBinary(bytes, format: ext == 'ppt' ? 'PowerPoint (PPT)' : 'Word (DOC)');
      default:
        // Essai de décodage standard si extension méconnue
        return _extractDocx(bytes);
    }
  }

  static bool _isBinaryPackage(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      return true; // En-tête ZIP standard (PK..)
    }
    if (bytes.length >= 4 && bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0) {
      return true; // En-tête OLE2 binaire (Word 97-2003, PPT legacy)
    }
    if (bytes.length >= 5 && bytes[0] == 0x7B && bytes[1] == 0x5C && bytes[2] == 0x72 && bytes[3] == 0x74 && bytes[4] == 0x66) {
      return true; // {\rtf
    }
    return false;
  }

  /// Décodage d'une présentation PowerPoint moderne (.pptx / OOXML).
  static ExtractedDocument _extractPptx(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final buffer = StringBuffer();
      var slideIndex = 1;

      // Parcourir les diapositives ppt/slides/slide1.xml, slide2.xml...
      final slideFiles = archive.where((f) => RegExp(r'ppt/slides/slide\d+\.xml$').hasMatch(f.name)).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      for (final slide in slideFiles) {
        final content = slide.content as List<int>;
        final xml = utf8.decode(content, allowMalformed: true);
        final tMatches = RegExp(r'<a:t(?:\s+[^>]*)?>([^<]*)</a:t>').allMatches(xml);
        final slideTexts = tMatches.map((m) => _unescapeXml(m.group(1) ?? '').trim()).where((t) => t.isNotEmpty).toList();

        if (slideTexts.isNotEmpty) {
          buffer.writeln('### Diapositive $slideIndex\n');
          for (final t in slideTexts) {
            buffer.writeln('- $t');
          }
          buffer.writeln();
          slideIndex++;
        }
      }

      final res = buffer.toString().trim();
      return ExtractedDocument(
        text: res.isNotEmpty ? res : '*(Présentation PowerPoint vide)*',
        isMarkdown: true,
        formatDescription: 'PowerPoint (PPTX)',
      );
    } on Object catch (_) {
      return _extractDocBinary(bytes, format: 'PowerPoint (PPTX)');
    }
  }

  /// Décodage d'une présentation OpenDocument (.odp).
  static ExtractedDocument _extractOdp(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? contentXml;
      for (final file in archive) {
        if (file.name == 'content.xml') {
          contentXml = file;
          break;
        }
      }

      if (contentXml == null) {
        return const ExtractedDocument(
          text: '# Présentation LibreOffice / OpenOffice\n\n*(content.xml introuvable)*',
          isMarkdown: true,
          formatDescription: 'OpenDocument Presentation (ODP)',
        );
      }

      final content = contentXml.content as List<int>;
      final xml = utf8.decode(content, allowMalformed: true);
      return _parseOdfXml(xml, 'OpenDocument Presentation (ODP)');
    } on Object catch (_) {
      return _extractDocBinary(bytes, format: 'OpenDocument (ODP)');
    }
  }

  /// Décodage d'un document Flat XML ODF (.fodt / .fodp).
  static ExtractedDocument _extractFod(Uint8List bytes, String ext) {
    try {
      final xml = utf8.decode(bytes, allowMalformed: true);
      return _parseOdfXml(xml, ext.toUpperCase());
    } on Object catch (_) {
      return _extractDocBinary(bytes, format: ext.toUpperCase());
    }
  }

  static ExtractedDocument _parseOdfXml(String xml, String format) {
    final buffer = StringBuffer();
    final blockRegex = RegExp(r'<text:(h|p)[^>]*>(.*?)</text:\1>', dotAll: true);
    for (final m in blockRegex.allMatches(xml)) {
      final tag = m.group(1);
      final body = m.group(2) ?? '';
      final text = _cleanXmlTags(body).trim();
      if (text.isEmpty) continue;

      if (tag == 'h') {
        buffer.writeln('## $text\n');
      } else {
        buffer.writeln('$text\n');
      }
    }
    final res = buffer.toString().trim();
    return ExtractedDocument(
      text: res.isNotEmpty ? res : '*(Document sans contenu texte)*',
      isMarkdown: true,
      formatDescription: format,
    );
  }

  /// Décodage d'un document Word moderne (.docx / OOXML).
  static ExtractedDocument _extractDocx(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? docXml;
      for (final file in archive) {
        if (file.name == 'word/document.xml') {
          docXml = file;
          break;
        }
      }

      if (docXml == null) {
        return const ExtractedDocument(
          text: '# Document Word\n\n*(Contenu principal non trouvé dans l’archive DOCX)*',
          isMarkdown: true,
          formatDescription: 'Word (DOCX)',
        );
      }

      final content = docXml.content as List<int>;
      final xmlString = utf8.decode(content, allowMalformed: true);
      final markdown = _parseWordDocumentXml(xmlString);

      return ExtractedDocument(
        text: markdown.isNotEmpty ? markdown : '*(Document vide)*',
        isMarkdown: true,
        formatDescription: 'Word (DOCX)',
      );
    } on Object catch (_) {
      // Repli sur l'extraction de texte binaire brut si le zip est corrompu
      return _extractDocBinary(bytes, format: 'Word (DOCX)');
    }
  }

  /// Transforme le XML de `word/document.xml` en Markdown structuré.
  static String _parseWordDocumentXml(String xml) {
    final buffer = StringBuffer();

    // Découpage par paragraphes (<w:p>...</w:p>)
    final pRegex = RegExp(r'<w:p(?:\s+[^>]*)?>(.*?)</w:p>', dotAll: true);
    final pMatches = pRegex.allMatches(xml);

    for (final pMatch in pMatches) {
      final pBody = pMatch.group(1) ?? '';

      // Style de paragraphe (ex: Heading1, Heading2, Title...)
      final styleMatch = RegExp(r'<w:pStyle\s+w:val="([^"]+)"').firstMatch(pBody);
      final style = styleMatch?.group(1)?.toLowerCase() ?? '';

      String prefix = '';
      if (style.contains('heading1') || style == 'title') {
        prefix = '# ';
      } else if (style.contains('heading2') || style == 'subtitle') {
        prefix = '## ';
      } else if (style.contains('heading3')) {
        prefix = '### ';
      } else if (style.contains('heading4')) {
        prefix = '#### ';
      }

      // Est-ce un élément de liste à puces ?
      final isList = pBody.contains('<w:numPr>');
      if (isList && prefix.isEmpty) {
        prefix = '- ';
      }

      final pText = StringBuffer();

      // Parcours des runs (<w:r>...</w:r>)
      final rRegex = RegExp(r'<w:r(?:\s+[^>]*)?>(.*?)</w:r>', dotAll: true);
      final rMatches = rRegex.allMatches(pBody);

      for (final rMatch in rMatches) {
        final rBody = rMatch.group(1) ?? '';

        final isBold = rBody.contains('<w:b/>') || rBody.contains('<w:b ');
        final isItalic = rBody.contains('<w:i/>') || rBody.contains('<w:i ');
        final isStrike = rBody.contains('<w:strike/>') || rBody.contains('<w:strike ');

        // Texte contenu dans <w:t>...</w:t>
        final tRegex = RegExp(r'<w:t(?:\s+[^>]*)?>([^<]*)</w:t>');
        final tMatches = tRegex.allMatches(rBody);

        var runText = tMatches.map((m) => m.group(1) ?? '').join();
        if (runText.isEmpty) {
          if (rBody.contains('<w:br/>') || rBody.contains('<w:br>')) {
            pText.write('\n');
          } else if (rBody.contains('<w:tab/>')) {
            pText.write('    ');
          }
          continue;
        }

        // Décodage des entités XML courantes
        runText = _unescapeXml(runText);

        // Application du formatage Markdown inline
        if (isBold && isItalic) {
          runText = '***$runText***';
        } else if (isBold) {
          runText = '**$runText**';
        } else if (isItalic) {
          runText = '*$runText*';
        } else if (isStrike) {
          runText = '~~$runText~~';
        }

        pText.write(runText);
      }

      final line = pText.toString().trim();
      if (line.isNotEmpty) {
        buffer.writeln('$prefix$line\n');
      }
    }

    return buffer.toString().trim();
  }

  /// Décodage d'un document OpenDocument Text (.odt).
  static ExtractedDocument _extractOdt(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? contentXml;
      for (final file in archive) {
        if (file.name == 'content.xml') {
          contentXml = file;
          break;
        }
      }

      if (contentXml == null) {
        return const ExtractedDocument(
          text: '# Document LibreOffice / OpenOffice\n\n*(content.xml introuvable)*',
          isMarkdown: true,
          formatDescription: 'OpenDocument (ODT)',
        );
      }

      final content = contentXml.content as List<int>;
      final xml = utf8.decode(content, allowMalformed: true);
      final buffer = StringBuffer();

      // Extraction des titres et paragraphes ODT
      final blockRegex = RegExp(r'<text:(h|p)[^>]*>(.*?)</text:\1>', dotAll: true);
      for (final m in blockRegex.allMatches(xml)) {
        final tag = m.group(1);
        final body = m.group(2) ?? '';
        final text = _cleanXmlTags(body).trim();
        if (text.isEmpty) continue;

        if (tag == 'h') {
          buffer.writeln('## $text\n');
        } else {
          buffer.writeln('$text\n');
        }
      }

      return ExtractedDocument(
        text: buffer.toString().trim(),
        isMarkdown: true,
        formatDescription: 'OpenDocument (ODT)',
      );
    } on Object catch (_) {
      return _extractDocBinary(bytes, format: 'OpenDocument (ODT)');
    }
  }

  /// Décodage d'un document Rich Text Format (.rtf).
  static ExtractedDocument _extractRtf(Uint8List bytes) {
    try {
      final raw = utf8.decode(bytes, allowMalformed: true);
      final buffer = StringBuffer();

      // Suppression des groupes d'en-tête RTF non textuels
      var text = raw.replaceAll(RegExp(r'\{\\\*?\w+[^}]*\}'), '');

      // Décodage des caractères hexadécimaux \'xx
      text = text.replaceAllMapped(RegExp(r"\\'([0-9a-fA-F]{2})"), (m) {
        final hex = m.group(1)!;
        final code = int.tryParse(hex, radix: 16);
        return code != null ? String.fromCharCode(code) : '';
      });

      // Remplacement des sauts de ligne RTF
      text = text.replaceAll(RegExp(r'\\par\b'), '\n');
      text = text.replaceAll(RegExp(r'\\line\b'), '\n');
      text = text.replaceAll(RegExp(r'\\tab\b'), '\t');

      // Suppression de tous les mots de contrôle \mot
      text = text.replaceAll(RegExp(r'\\[a-zA-Z]+-?\d*\s?'), '');

      // Suppression des accolades ouvrantes et fermantes
      text = text.replaceAll(RegExp(r'[{}]'), '');

      for (final line in text.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          buffer.writeln(trimmed);
        }
      }

      return ExtractedDocument(
        text: buffer.toString().trim(),
        isMarkdown: false,
        formatDescription: 'Rich Text Format (RTF)',
      );
    } on Object catch (_) {
      return _extractDocBinary(bytes, format: 'RTF');
    }
  }

  /// Extraction de texte brut pour les formats binaires Word legacy (.doc).
  static ExtractedDocument _extractDocBinary(Uint8List bytes, {String format = 'Word (DOC)'}) {
    final buffer = StringBuffer();
    final words = <String>[];
    var currentBytes = <int>[];

    void flush() {
      if (currentBytes.length >= 3) {
        String decoded;
        try {
          decoded = utf8.decode(currentBytes);
        } on FormatException {
          decoded = latin1.decode(currentBytes);
        }
        words.add(decoded);
      }
      currentBytes = [];
    }

    // Recherche de séquences de caractères imprimables (UTF-8, Latin, ASCII)
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if ((b >= 32 && b <= 126) || b == 10 || b == 13 || b == 9 || (b >= 128 && b <= 255)) {
        currentBytes.add(b);
      } else {
        flush();
      }
    }
    flush();

    var paragraph = <String>[];
    for (final w in words) {
      if (w.contains('\n') || w.contains('\r')) {
        if (paragraph.isNotEmpty) {
          buffer.writeln(paragraph.join(' '));
          paragraph = [];
        }
      } else {
        paragraph.add(w);
      }
    }
    if (paragraph.isNotEmpty) buffer.writeln(paragraph.join(' '));

    final res = buffer.toString().trim();
    return ExtractedDocument(
      text: res.isNotEmpty ? res : '*(Fichier Word binaire sans texte lisible en clair)*',
      isMarkdown: false,
      formatDescription: format,
    );
  }

  static String _unescapeXml(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  static String _cleanXmlTags(String xml) {
    return _unescapeXml(xml.replaceAll(RegExp(r'<[^>]+>'), ''));
  }
}
