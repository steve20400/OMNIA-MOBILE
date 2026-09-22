import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/utils/doc_reader.dart';

void main() {
  group('DocReader', () {
    test('RTF parsing extrait le texte sans les balises ni mots de contrôle', () async {
      const rtf = r'''{\rtf1\ansi\deff0
{\fonttbl{\f0\fnil\fcharset0 Arial;}}
\viewkind4\uc1\pard\lang1036\b Titre du document\b0\par
Ceci est un paragraphe avec du texte standard.\par
}''';
      final file = File('${Directory.systemTemp.path}/test_doc.rtf');
      await file.writeAsString(rtf);
      try {
        final text = await DocReader.read(file.path);
        expect(text, contains('Titre du document'));
        expect(text, contains('Ceci est un paragraphe avec du texte standard.'));
        expect(text, isNot(contains(r'\rtf1')));
        expect(text, isNot(contains(r'\fonttbl')));
      } finally {
        if (await file.exists()) await file.delete();
      }
    });

    test('DOCX parsing extrait le texte XML depuis le zip', () async {
      const xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r><w:t>Premier paragraphe &amp; titre</w:t></w:r>
    </w:p>
    <w:p>
      <w:r><w:t>Deuxième paragraphe avec du contenu.</w:t></w:r>
    </w:p>
  </w:body>
</w:document>''';

      final archive = Archive();
      final xmlBytes = utf8.encode(xml);
      archive.addFile(ArchiveFile('word/document.xml', xmlBytes.length, xmlBytes));
      final zipEncoder = ZipEncoder();
      final zipBytes = zipEncoder.encode(archive);

      final file = File('${Directory.systemTemp.path}/test_doc.docx');
      await file.writeAsBytes(zipBytes);
      try {
        final text = await DocReader.read(file.path);
        expect(text, contains('Premier paragraphe & titre'));
        expect(text, contains('Deuxième paragraphe avec du contenu.'));
      } finally {
        if (await file.exists()) await file.delete();
      }
    });

    test('ODT parsing extrait le texte XML depuis content.xml', () async {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
                         xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
  <office:body>
    <office:text>
      <text:h>Grand Titre ODT</text:h>
      <text:p>Texte dans le paragraphe libre &lt;important&gt;.</text:p>
    </office:text>
  </office:body>
</office:document-content>''';

      final archive = Archive();
      final xmlBytes = utf8.encode(xml);
      archive.addFile(ArchiveFile('content.xml', xmlBytes.length, xmlBytes));
      final zipEncoder = ZipEncoder();
      final zipBytes = zipEncoder.encode(archive);

      final file = File('${Directory.systemTemp.path}/test_doc.odt');
      await file.writeAsBytes(zipBytes);
      try {
        final text = await DocReader.read(file.path);
        expect(text, contains('Grand Titre ODT'));
        expect(text, contains('Texte dans le paragraphe libre <important>.'));
      } finally {
        if (await file.exists()) await file.delete();
      }
    });

    test('DOC binaire ancien extrait les portions lisibles', () async {
      // Simule un flux binaire contenant du texte ASCII/latin
      final bytes = Uint8List.fromList([
        0xD0, 0xCF, 0x11, 0xE0, // Signature OLE2
        0x00, 0x01, 0x02,
        ...utf8.encode('Contenu texte présent dans le fichier doc legacy.'),
        0x00, 0x04, 0x05,
      ]);
      final file = File('${Directory.systemTemp.path}/test_doc.doc');
      await file.writeAsBytes(bytes);
      try {
        final text = await DocReader.read(file.path);
        expect(text, contains('Contenu texte présent dans le fichier doc legacy.'));
      } finally {
        if (await file.exists()) await file.delete();
      }
    });

    test('PPTX parsing extrait le texte des diapos', () async {
      const slide1 = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
       xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:sp>
        <p:txBody>
          <a:p><a:r><a:t>Titre Diapositive 1</a:t></a:r></a:p>
          <a:p><a:r><a:t>Sous-titre explicatif</a:t></a:r></a:p>
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:sld>''';

      const slide2 = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
       xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:sp>
        <p:txBody>
          <a:p><a:r><a:t>Deuxième diapositive</a:t></a:r></a:p>
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:sld>''';

      final archive = Archive();
      final s1Bytes = utf8.encode(slide1);
      final s2Bytes = utf8.encode(slide2);
      archive.addFile(ArchiveFile('ppt/slides/slide1.xml', s1Bytes.length, s1Bytes));
      archive.addFile(ArchiveFile('ppt/slides/slide2.xml', s2Bytes.length, s2Bytes));
      final zipEncoder = ZipEncoder();
      final zipBytes = zipEncoder.encode(archive);

      final file = File('${Directory.systemTemp.path}/test_pres.pptx');
      await file.writeAsBytes(zipBytes);
      try {
        final text = await DocReader.read(file.path);
        expect(text, contains('Titre Diapositive 1'));
        expect(text, contains('Sous-titre explicatif'));
        expect(text, contains('Deuxième diapositive'));
      } finally {
        if (await file.exists()) await file.delete();
      }
    });

    test('FODT / FODP XML plat extrait les paragraphes sans zip', () async {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<office:document xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
                 xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
  <office:body>
    <office:drawing>
      <draw:page draw:name="Slide 1">
        <text:p>Présentation plate FODP</text:p>
        <text:p>Deuxième point important</text:p>
      </draw:page>
    </office:drawing>
  </office:body>
</office:document>''';

      final file = File('${Directory.systemTemp.path}/test_pres.fodp');
      await file.writeAsString(xml);
      try {
        final text = await DocReader.read(file.path);
        expect(text, contains('Présentation plate FODP'));
        expect(text, contains('Deuxième point important'));
      } finally {
        if (await file.exists()) await file.delete();
      }
    });

    test('document bureautique modifié et réenregistré en texte est relu directement', () async {
      final file = File('${Directory.systemTemp.path}/saved_pres.pptx');
      await file.writeAsString('### Diapositive 1 Modifiée\n\nNouveau contenu texte.');
      try {
        final text = await DocReader.read(file.path);
        expect(text, '### Diapositive 1 Modifiée\n\nNouveau contenu texte.');
      } finally {
        if (await file.exists()) await file.delete();
      }
    });
  });
}
