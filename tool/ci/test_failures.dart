// Publie chaque test échoué comme annotation GitHub Actions.
//
// `flutter test --file-reporter json:<fichier>` écrit un événement JSON par
// ligne. Ce script en tire, pour chaque test en échec, le fichier, la ligne,
// le nom et le message d'erreur, au format des commandes de workflow
// (`::error file=…,line=…,title=…::…`). GitHub les affiche sur la page de
// l'exécution et dans le code du commit, sans qu'il faille ouvrir les journaux.
//
// Usage : dart run tool/ci/test_failures.dart build/rapport-tests.json
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// GitHub n'affiche qu'une dizaine d'annotations d'erreur par étape.
const int maxAnnotations = 10;

/// Longueur maximale d'un message, pile d'appels comprise.
const int maxMessageLength = 4000;

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage : dart run tool/ci/test_failures.dart <rapport.json>');
    exitCode = 64;
    return;
  }
  final report = File(args.single);
  if (!report.existsSync()) {
    stdout.writeln(
      '::warning title=Rapport de tests absent::${report.path} n’a pas été écrit : '
      'les tests n’ont sans doute pas démarré.',
    );
    return;
  }
  for (final annotation in annotationsFor(report.readAsLinesSync(), root: Directory.current.path)) {
    stdout.writeln(annotation);
  }
}

/// Annotations d'erreur pour les tests échoués décrits par [events], lignes
/// du rapport JSON de `package:test`. [root] rend les chemins relatifs au
/// dépôt, comme GitHub les attend.
List<String> annotationsFor(Iterable<String> events, {required String root}) {
  final tests = <int, Map<Object?, Object?>>{};
  final suites = <int, String>{};
  final errors = <int, List<String>>{};
  final failed = <int>[];

  for (final line in events) {
    final Object? event;
    try {
      event = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (event is! Map) continue;
    switch (event['type']) {
      case 'suite':
        final suite = event['suite'];
        if (suite is Map && suite['id'] is int && suite['path'] is String) {
          suites[suite['id'] as int] = suite['path'] as String;
        }
      case 'testStart':
        final test = event['test'];
        if (test is Map && test['id'] is int) tests[test['id'] as int] = test;
      case 'error':
        final id = event['testID'];
        if (id is int) {
          final text = [event['error'], event['stackTrace']].whereType<String>().join('\n').trim();
          (errors[id] ??= []).add(text);
        }
      case 'testDone':
        final id = event['testID'];
        // Un test ignoré se termine en « success » : seuls les vrais échecs
        // (assertion ou exception) sont retenus.
        if (id is int && event['result'] != 'success') failed.add(id);
    }
  }

  final annotations = <String>[];
  final shown = failed.length > maxAnnotations ? failed.take(maxAnnotations - 1) : failed;
  for (final id in shown) {
    final test = tests[id] ?? const {};
    final name = test['name'] as String? ?? 'test $id';
    final location = _location(test, suites, root);
    final message = _truncate((errors[id] ?? const ['Échec sans message.']).join('\n\n'));
    final properties = [
      if (location != null) 'file=${_property(location.file)}',
      if (location?.line != null) 'line=${location!.line}',
      'title=${_property('Test échoué : $name')}',
    ].join(',');
    annotations.add('::error $properties::${_data(message)}');
  }
  if (failed.length > shown.length) {
    final rest = failed.skip(shown.length).map((id) => tests[id]?['name'] ?? 'test $id');
    annotations.add(
      '::error title=${_property('${rest.length} autres tests échoués')}::${_data(rest.join('\n'))}',
    );
  }
  return annotations;
}

/// Fichier du dépôt et ligne où le test est déclaré, si le rapport les donne.
///
/// `root_url` désigne le code du test lui-même ; `url` peut désigner la
/// fonction qui l'enveloppe (testWidgets). À défaut, le chemin de la suite.
({String file, int? line})? _location(
  Map<Object?, Object?> test,
  Map<int, String> suites,
  String root,
) {
  for (final (urlKey, lineKey) in const [('root_url', 'root_line'), ('url', 'line')]) {
    final url = test[urlKey];
    if (url is! String || !url.startsWith('file:')) continue;
    final path = Uri.parse(url).toFilePath();
    if (!p.isWithin(root, path)) continue;
    return (file: _relative(path, root), line: test[lineKey] as int?);
  }
  final suitePath = suites[test['suiteID']];
  if (suitePath == null) return null;
  return (file: _relative(p.isAbsolute(suitePath) ? suitePath : p.join(root, suitePath), root), line: null);
}

String _relative(String path, String root) => p.relative(path, from: root).replaceAll(r'\', '/');

String _truncate(String text) =>
    text.length <= maxMessageLength ? text : '${text.substring(0, maxMessageLength)}\n…';

/// Encodage du message d'une commande de workflow.
String _data(String text) =>
    text.replaceAll('%', '%25').replaceAll('\r', '%0D').replaceAll('\n', '%0A');

/// Encodage d'une propriété (`file`, `title`) : `:` et `,` y sont réservés.
String _property(String text) => _data(text).replaceAll(':', '%3A').replaceAll(',', '%2C');
