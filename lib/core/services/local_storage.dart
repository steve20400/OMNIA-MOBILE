import 'dart:convert';
import 'dart:io';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_preferences.dart';

/// Initialise Hive dans le dossier de données applicatives du système.
///
/// On n'utilise pas `Hive.initFlutter`, qui passe par le dossier « Documents »
/// de l'utilisateur : sous Linux, ce dossier est résolu en lançant le binaire
/// externe `xdg-user-dir`, absent d'un système minimal, et l'échec remonte
/// avant même l'affichage de la fenêtre — OMNIA ne démarrerait pas, sans
/// aucun message. Le dossier de support applicatif, lui, est toujours
/// déterminable :
///
/// - Linux  : `~/.local/share/dev.omnia.omnia/`
/// - Windows: `%APPDATA%\OMNIA\OMNIA\` (société et produit déclarés dans
///   les ressources de l'exécutable, `windows/runner/Runner.rc`)
/// - macOS  : `~/Library/Application Support/dev.omnia.omnia/`
Future<void> initialiseLocalStorage() async {
  if (_initialised) return;
  Hive.init((await localStorageDirectory()).path);
  _initialised = true;
}

/// Dossier de données local d'OMNIA (boîtes Hive, verrou d'instance unique).
Future<Directory> localStorageDirectory() async {
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'data'));
}

bool _initialised = false;

/// Copie des préférences en clair, lisible sans Hive.
///
/// Hive verrouille ses fichiers : quand l'instance unique est désactivée, une
/// seconde fenêtre ne peut pas ouvrir la base tenue par la première. Elle
/// démarre alors avec des réglages en mémoire, relus depuis cette copie, pour
/// garder au moins le thème, la langue et les réglages de lecture.
const String preferencesSnapshotName = 'preferences.json';

Future<void> writePreferencesSnapshot(Directory dir, AppPreferences prefs) async {
  try {
    await dir.create(recursive: true);
    await File(p.join(dir.path, preferencesSnapshotName))
        .writeAsString(jsonEncode(prefs.toJson()), flush: true);
  } on FileSystemException {
    // Copie de secours seulement : son absence n'empêche rien.
  }
}

AppPreferences? readPreferencesSnapshot(Directory dir) {
  try {
    final file = File(p.join(dir.path, preferencesSnapshotName));
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map) return null;
    return AppPreferences.fromJson(Map<String, Object?>.from(json));
  } on Object {
    return null;
  }
}

/// Nom du fichier JSON de secours pour l'historique et les positions.
const String historySnapshotName = 'history.json';

/// Sauvegarde une copie de l'historique en JSON pour les fenêtres secondaires
/// et la persistance lors des fermetures système.
Future<void> writeHistorySnapshot(Directory dir, Map<String, dynamic> entriesJson) async {
  try {
    await dir.create(recursive: true);
    await File(p.join(dir.path, historySnapshotName))
        .writeAsString(jsonEncode(entriesJson), flush: true);
  } on Object {
    // Écriture de secours.
  }
}

/// Lit la copie de l'historique en JSON.
Map<String, dynamic> readHistorySnapshot(Directory dir) {
  try {
    final file = File(p.join(dir.path, historySnapshotName));
    if (!file.existsSync()) return {};
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map) return {};
    return Map<String, dynamic>.from(json);
  } on Object {
    return {};
  }
}
