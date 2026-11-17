import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/ci/test_failures.dart';

/// Rapport JSON minimal, au format de `package:test`.
class _Report {
  _Report(this.root);

  final String root;
  final List<String> lines = [];
  int _next = 1;

  void suite(int id, String relativePath) => lines.add(
        jsonEncode({
          'type': 'suite',
          'suite': {'id': id, 'path': p.join(root, relativePath)},
        }),
      );

  /// Ajoute un test ; retourne son identifiant.
  int test(
    String name, {
    int suiteId = 0,
    String? rootFile,
    int? rootLine,
    String result = 'success',
    bool skipped = false,
    String? error,
  }) {
    final id = _next++;
    lines.add(
      jsonEncode({
        'type': 'testStart',
        'test': {
          'id': id,
          'name': name,
          'suiteID': suiteId,
          // Comme testWidgets : `url` désigne flutter_test, `root_url` le test.
          'url': 'package:flutter_test/src/widget_tester.dart',
          'line': 180,
          if (rootFile != null) 'root_url': Uri.file(p.join(root, rootFile)).toString(),
          'root_line': ?rootLine,
        },
      }),
    );
    if (error != null) {
      lines.add(jsonEncode({'type': 'error', 'testID': id, 'error': error, 'stackTrace': 'pile'}));
    }
    lines.add(
      jsonEncode({'type': 'testDone', 'testID': id, 'result': result, 'skipped': skipped, 'hidden': false}),
    );
    return id;
  }
}

void main() {
  final root = p.join(Directory.systemTemp.path, 'depot');

  test('un test échoué devient une annotation avec fichier, ligne, titre et message', () {
    final report = _Report(root)
      ..test(
        'écran principal',
        rootFile: p.join('test', 'ui', 'ecran_test.dart'),
        rootLine: 42,
        result: 'failure',
        error: 'Expected: 1\n  Actual: 2',
      );

    final annotations = annotationsFor(report.lines, root: root);

    expect(annotations, [
      '::error file=test/ui/ecran_test.dart,line=42,title=Test échoué %3A écran principal'
          '::Expected: 1%0A  Actual: 2%0Apile',
    ]);
  });

  test('les tests réussis et ignorés ne produisent rien', () {
    final report = _Report(root)
      ..test('réussi')
      ..test('ignoré', skipped: true);
    expect(annotationsFor(report.lines, root: root), isEmpty);
  });

  test('sans emplacement dans le test, le fichier de la suite sert de repli', () {
    final report = _Report(root)
      ..suite(7, p.join('test', 'core', 'bus_test.dart'))
      ..test('chargement', suiteId: 7, result: 'error', error: 'Compilation impossible');
    expect(
      annotationsFor(report.lines, root: root).single,
      startsWith('::error file=test/core/bus_test.dart,title=Test échoué %3A chargement::'),
    );
  });

  test('%, deux-points et virgules sont encodés là où GitHub l’exige', () {
    final report = _Report(root)..test('a, b : c', result: 'failure', error: '100 % raté');
    final annotation = annotationsFor(report.lines, root: root).single;
    expect(annotation, contains('title=Test échoué %3A a%2C b %3A c::'));
    expect(annotation, contains('100 %25 raté'));
  });

  test('au-delà de dix échecs, les derniers sont regroupés dans une annotation', () {
    final report = _Report(root);
    for (var i = 1; i <= 14; i++) {
      report.test('test $i', result: 'failure', error: 'raté');
    }
    final annotations = annotationsFor(report.lines, root: root);
    expect(annotations, hasLength(maxAnnotations));
    expect(annotations.last, contains('title=5 autres tests échoués::'));
    expect(annotations.last, contains('test 10%0Atest 11'));
  });

  test('une ligne illisible du rapport est ignorée', () {
    final report = _Report(root)..test('raté', result: 'failure', error: 'x');
    final lines = ['pas du json', '', ...report.lines, '[1, 2]'];
    expect(annotationsFor(lines, root: root), hasLength(1));
  });
}
