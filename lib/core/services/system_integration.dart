import 'dart:io';

import 'package:path/path.dart' as p;

/// Petites intégrations avec le système d'exploitation.
///
/// Isolées derrière une interface pour deux raisons : les tests du core ne
/// doivent lancer aucun processus, et chaque système a sa propre commande.
abstract interface class SystemIntegration {
  /// Ouvre le gestionnaire de fichiers sur l'emplacement de [path], en
  /// sélectionnant le fichier quand le système le permet.
  Future<void> revealInFileManager(String path);
}

/// Implémentation réelle : Windows, Linux et macOS.
class DesktopSystemIntegration implements SystemIntegration {
  const DesktopSystemIntegration();

  @override
  Future<void> revealInFileManager(String path) async {
    try {
      if (Platform.isWindows) {
        // L'explorateur attend des antislashs et sélectionne le fichier.
        await Process.run('explorer.exe', ['/select,', path.replaceAll('/', r'\')]);
        return;
      }
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
        return;
      }
      // Linux : les gestionnaires compatibles freedesktop savent sélectionner
      // un fichier via D-Bus ; sinon on ouvre simplement le dossier parent.
      final dbus = await Process.run('dbus-send', [
        '--session',
        '--dest=org.freedesktop.FileManager1',
        '--type=method_call',
        '/org/freedesktop/FileManager1',
        'org.freedesktop.FileManager1.ShowItems',
        'array:string:file://$path',
        'string:',
      ]);
      if (dbus.exitCode != 0) {
        await Process.run('xdg-open', [p.dirname(path)]);
      }
    } on ProcessException {
      // Aucun gestionnaire de fichiers disponible : l'action est sans effet,
      // ce n'est pas une raison de faire échouer la lecture.
    }
  }
}

/// Implémentation neutre : ne fait rien. Valeur par défaut dans les tests.
class NoopSystemIntegration implements SystemIntegration {
  const NoopSystemIntegration();

  @override
  Future<void> revealInFileManager(String path) async {}
}

/// Implémentation d'enregistrement, pour vérifier les appels dans les tests.
class RecordingSystemIntegration implements SystemIntegration {
  final List<String> revealed = [];

  @override
  Future<void> revealInFileManager(String path) async => revealed.add(path);
}
