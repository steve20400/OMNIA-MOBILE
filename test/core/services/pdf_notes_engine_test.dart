import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/services/pdf_notes_engine.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  group('Passage surligné', () {
    test('les caractères d’une ligne font un rectangle, la ligne suivante un autre', () {
      final quads = pdfLineQuads(const [
        PdfRect(10, 700, 16, 690),
        PdfRect(16, 701, 22, 689),
        // Une espace sans surface ne compte pas.
        PdfRect(22, 695, 22, 695),
        PdfRect(10, 680, 15, 670),
        PdfRect(15, 680, 40, 669),
      ]);
      expect(quads, [10, 701, 22, 689, 10, 680, 40, 669]);
    });

    test('rien de sélectionné, rien à surligner', () {
      expect(pdfLineQuads(const []), isEmpty);
    });
  });

  test('les dates au format des PDF', () {
    expect(
      pdfDate(DateTime(2026, 11, 23, 9, 5, 7)),
      matches(RegExp(r"^D:20261123090507[+-]\d\d'\d\d'$")),
    );
  });
}
