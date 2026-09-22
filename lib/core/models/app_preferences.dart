import 'document_layout.dart';
import 'equalizer.dart';

/// Langue de l'interface.
enum AppLanguage {
  /// Langue du système ; français si elle n'est pas prise en charge.
  system,
  fr,
  en;

  static AppLanguage fromJson(Object? value) =>
      values.firstWhere((e) => e.name == value, orElse: () => AppLanguage.system);
}

/// Thème de l'interface. Le sombre est celui d'OMNIA : un lecteur vit dans le
/// noir.
enum AppThemeMode {
  dark,
  light,
  system;

  static AppThemeMode fromJson(Object? value) =>
      values.firstWhere((e) => e.name == value, orElse: () => AppThemeMode.dark);
}

/// Que faire quand on rouvre un fichier interrompu en cours de route.
enum ResumePolicy {
  /// Reprendre directement à la position mémorisée (défaut).
  auto,

  /// Proposer de reprendre ; sans réponse, le fichier part du début.
  ask,

  /// Toujours repartir du début.
  never;

  static ResumePolicy fromJson(Object? value) =>
      values.firstWhere((e) => e.name == value, orElse: () => ResumePolicy.auto);
}

/// Volume au démarrage de l'application.
enum StartupVolume {
  /// Le dernier volume utilisé (défaut).
  last,

  /// Toujours la même valeur, [AppPreferences.fixedVolume].
  fixed;

  static StartupVolume fromJson(Object? value) =>
      values.firstWhere((e) => e.name == value, orElse: () => StartupVolume.last);
}

/// Cible d'ouverture des fichiers, dossiers et récents depuis l'application.
enum InAppOpenTarget {
  /// Ouvrir dans la fenêtre courante (remplace le média actif).
  currentWindow,

  /// Ouvrir dans une nouvelle fenêtre indépendante.
  newWindow;

  static InAppOpenTarget fromJson(Object? value) =>
      values.firstWhere((e) => e.name == value, orElse: () => InAppOpenTarget.currentWindow);
}

/// Comportement à la fermeture de l'application si un document contient des modifications non enregistrées.
enum UnsavedChangesPolicy {
  /// Demander à l'utilisateur s'il souhaite enregistrer, ignorer ou annuler la fermeture (défaut).
  ask,

  /// Enregistrer automatiquement et fermer sans avertissement.
  save,

  /// Ignorer les modifications et fermer immédiatement.
  discard;

  static UnsavedChangesPolicy fromJson(Object? value) =>
      values.firstWhere((e) => e.name == value, orElse: () => UnsavedChangesPolicy.ask);
}

/// Préférences de l'utilisateur, telles que l'écran Paramètres les présente
/// (§10 du cahier des charges).
///
/// Un seul objet immuable, sérialisé d'un bloc : ajouter un réglage ne demande
/// qu'un champ ici, et une préférence écrite par une version plus ancienne se
/// relit sans erreur (chaque champ a sa valeur de repli).
class AppPreferences {
  const AppPreferences({
    this.language = AppLanguage.system,
    this.themeMode = AppThemeMode.dark,
    this.resumePolicy = ResumePolicy.auto,
    this.restoreLastSession = true,
    this.singleInstance = true,
    this.seekStepSeconds = 5,
    this.defaultSpeed = 1.0,
    this.startupVolume = StartupVolume.last,
    this.fixedVolume = 80,
    this.subtitleScale = 1.0,
    this.subtitleAutoLoad = true,
    this.subtitleDelay = 0,
    this.equalizerEnabled = false,
    this.equalizerGains = Equalizer.flat,
    this.pdfLayout = DocumentLayout.continuous,
    this.readingDark = false,
    this.textScale = 1.0,
    this.screenshotNamePattern = defaultScreenshotPattern,
    this.normalPlayerAlwaysOnTop = false,
    this.miniPlayerAlwaysOnTop = true,
    this.imageEditSuffix = defaultImageEditSuffix,
    this.imageEditQuality = 92,
    this.docAutoSave = true,
    this.docAutoSaveIntervalSeconds = 2,
    this.unsavedChangesPolicy = UnsavedChangesPolicy.ask,
    this.inAppOpenTarget = InAppOpenTarget.currentWindow,
    this.rememberPlaybackState = true,
    this.historyRetentionDays = 30,
  });

  static const AppPreferences defaults = AppPreferences();

  /// Options de rétention de l'historique proposées (en jours, 0 = illimité).
  static const List<int> retentionDaysOptions = [7, 30, 90, 0];

  /// Pas d'avance / recul proposés pour `←` / `→`.
  static const List<int> seekSteps = [5, 10, 30, 60];

  /// Vitesses proposées comme vitesse par défaut.
  static const List<double> speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  /// Intervalles de sauvegarde automatique proposés (en secondes).
  static const List<int> docAutoSaveIntervals = [1, 2, 3, 5, 10];

  /// Motif de nom des captures : `{name}`, `{date}`, `{time}`, `{position}`.
  static const String defaultScreenshotPattern = '{name} {date} {time}';

  /// Suffixe par défaut pour les copies d'images modifiées.
  static const String defaultImageEditSuffix = '_modifié';

  // Général
  final AppLanguage language;
  final AppThemeMode themeMode;
  final ResumePolicy resumePolicy;

  /// Rouvrir automatiquement le dernier fichier ouvert au démarrage.
  final bool restoreLastSession;

  /// Réutiliser la fenêtre ouverte quand on ouvre un fichier depuis le système.
  /// Pris en compte au démarrage suivant.
  final bool singleInstance;

  // Lecture
  final int seekStepSeconds;
  final double defaultSpeed;
  final StartupVolume startupVolume;
  final double fixedVolume;

  // Sous-titres
  final double subtitleScale;

  /// Charger les sous-titres voisins (même nom de base) automatiquement.
  final bool subtitleAutoLoad;

  /// Décalage appliqué à l'ouverture de chaque fichier, en secondes.
  final double subtitleDelay;

  // Audio
  final bool equalizerEnabled;
  final List<double> equalizerGains;

  // Documents
  final DocumentLayout pdfLayout;
  final bool readingDark;

  /// Taille du texte des fichiers `.txt` / `.md` (1.0 = normale).
  final double textScale;

  /// Sauvegarde automatique des documents texte et code modifiés.
  final bool docAutoSave;

  /// Délai d'inactivité avant la sauvegarde automatique (en secondes).
  final int docAutoSaveIntervalSeconds;

  /// Règle appliquée à la fermeture si un document est en cours de modification.
  final UnsavedChangesPolicy unsavedChangesPolicy;

  // Captures
  final String screenshotNamePattern;

  // Premier plan
  final bool normalPlayerAlwaysOnTop;
  final bool miniPlayerAlwaysOnTop;

  // Images
  final String imageEditSuffix;
  final int imageEditQuality;

  /// Cible d'ouverture pour les actions déclenchées au sein de l'application.
  final InAppOpenTarget inAppOpenTarget;

  /// Mémoriser automatiquement la dernière page ou position de lecture.
  final bool rememberPlaybackState;

  /// Durée de conservation de l'historique de lecture en jours (0 = sans limite / indéfini).
  final int historyRetentionDays;

  /// Vrai si les ouvertures depuis l'application doivent créer une nouvelle fenêtre.
  bool get inAppOpenNewWindow => inAppOpenTarget == InAppOpenTarget.newWindow;

  AppPreferences copyWith({
    AppLanguage? language,
    AppThemeMode? themeMode,
    ResumePolicy? resumePolicy,
    bool? restoreLastSession,
    bool? singleInstance,
    int? seekStepSeconds,
    double? defaultSpeed,
    StartupVolume? startupVolume,
    double? fixedVolume,
    double? subtitleScale,
    bool? subtitleAutoLoad,
    double? subtitleDelay,
    bool? equalizerEnabled,
    List<double>? equalizerGains,
    DocumentLayout? pdfLayout,
    bool? readingDark,
    double? textScale,
    bool? docAutoSave,
    int? docAutoSaveIntervalSeconds,
    UnsavedChangesPolicy? unsavedChangesPolicy,
    String? screenshotNamePattern,
    bool? normalPlayerAlwaysOnTop,
    bool? miniPlayerAlwaysOnTop,
    String? imageEditSuffix,
    int? imageEditQuality,
    InAppOpenTarget? inAppOpenTarget,
    bool? rememberPlaybackState,
    int? historyRetentionDays,
  }) {
    return AppPreferences(
      language: language ?? this.language,
      themeMode: themeMode ?? this.themeMode,
      resumePolicy: resumePolicy ?? this.resumePolicy,
      restoreLastSession: restoreLastSession ?? this.restoreLastSession,
      singleInstance: singleInstance ?? this.singleInstance,
      seekStepSeconds: _step(seekStepSeconds ?? this.seekStepSeconds),
      defaultSpeed: _speed(defaultSpeed ?? this.defaultSpeed),
      startupVolume: startupVolume ?? this.startupVolume,
      fixedVolume: (fixedVolume ?? this.fixedVolume).clamp(0.0, 100.0),
      subtitleScale: (subtitleScale ?? this.subtitleScale).clamp(0.5, 2.5),
      subtitleAutoLoad: subtitleAutoLoad ?? this.subtitleAutoLoad,
      subtitleDelay: (subtitleDelay ?? this.subtitleDelay).clamp(-30.0, 30.0),
      equalizerEnabled: equalizerEnabled ?? this.equalizerEnabled,
      equalizerGains: Equalizer.normalise(equalizerGains ?? this.equalizerGains),
      pdfLayout: pdfLayout ?? this.pdfLayout,
      readingDark: readingDark ?? this.readingDark,
      textScale: (textScale ?? this.textScale).clamp(0.6, 3.0),
      docAutoSave: docAutoSave ?? this.docAutoSave,
      docAutoSaveIntervalSeconds: _autoSaveInterval(
          docAutoSaveIntervalSeconds ?? this.docAutoSaveIntervalSeconds),
      unsavedChangesPolicy: unsavedChangesPolicy ?? this.unsavedChangesPolicy,
      screenshotNamePattern: _pattern(screenshotNamePattern ?? this.screenshotNamePattern),
      normalPlayerAlwaysOnTop: normalPlayerAlwaysOnTop ?? this.normalPlayerAlwaysOnTop,
      miniPlayerAlwaysOnTop: miniPlayerAlwaysOnTop ?? this.miniPlayerAlwaysOnTop,
      imageEditSuffix: imageEditSuffix ?? this.imageEditSuffix,
      imageEditQuality: (imageEditQuality ?? this.imageEditQuality).clamp(50, 100),
      inAppOpenTarget: inAppOpenTarget ?? this.inAppOpenTarget,
      rememberPlaybackState: rememberPlaybackState ?? this.rememberPlaybackState,
      historyRetentionDays: _retention(historyRetentionDays ?? this.historyRetentionDays),
    );
  }

  static int _retention(int value) {
    if (retentionDaysOptions.contains(value)) return value;
    var best = retentionDaysOptions.first;
    for (final r in retentionDaysOptions) {
      if ((r - value).abs() < (best - value).abs()) best = r;
    }
    return best;
  }


  /// Un pas inconnu retombe sur le plus proche des pas proposés.
  static int _step(int value) {
    var best = seekSteps.first;
    for (final s in seekSteps) {
      if ((s - value).abs() < (best - value).abs()) best = s;
    }
    return best;
  }

  static int _autoSaveInterval(int value) {
    var best = docAutoSaveIntervals.first;
    for (final s in docAutoSaveIntervals) {
      if ((s - value).abs() < (best - value).abs()) best = s;
    }
    return best;
  }

  static double _speed(double value) {
    final steps = (value / 0.25).round();
    return (steps * 0.25).clamp(0.25, 4.0);
  }

  static String _pattern(String value) {
    final v = value.trim();
    return v.isEmpty ? defaultScreenshotPattern : v;
  }

  Map<String, Object?> toJson() => {
        'language': language.name,
        'themeMode': themeMode.name,
        'resumePolicy': resumePolicy.name,
        'restoreLastSession': restoreLastSession,
        'singleInstance': singleInstance,
        'seekStepSeconds': seekStepSeconds,
        'defaultSpeed': defaultSpeed,
        'startupVolume': startupVolume.name,
        'fixedVolume': fixedVolume,
        'subtitleScale': subtitleScale,
        'subtitleAutoLoad': subtitleAutoLoad,
        'subtitleDelay': subtitleDelay,
        'equalizerEnabled': equalizerEnabled,
        'equalizerGains': equalizerGains,
        'pdfLayout': pdfLayout.name,
        'readingDark': readingDark,
        'textScale': textScale,
        'docAutoSave': docAutoSave,
        'docAutoSaveIntervalSeconds': docAutoSaveIntervalSeconds,
        'unsavedChangesPolicy': unsavedChangesPolicy.name,
        'screenshotNamePattern': screenshotNamePattern,
        'normalPlayerAlwaysOnTop': normalPlayerAlwaysOnTop,
        'miniPlayerAlwaysOnTop': miniPlayerAlwaysOnTop,
        'imageEditSuffix': imageEditSuffix,
        'imageEditQuality': imageEditQuality,
        'inAppOpenTarget': inAppOpenTarget.name,
        'rememberPlaybackState': rememberPlaybackState,
        'historyRetentionDays': historyRetentionDays,
      };

  /// Relecture tolérante : une valeur absente, d'un mauvais type ou hors bornes
  /// prend sa valeur par défaut, ou est ramenée dans les bornes.
  factory AppPreferences.fromJson(Map<String, Object?> json) {
    const d = AppPreferences.defaults;
    double num0(String key, double fallback) =>
        (json[key] is num) ? (json[key]! as num).toDouble() : fallback;
    bool bool0(String key, bool fallback) =>
        json[key] is bool ? json[key]! as bool : fallback;

    final gains = json['equalizerGains'];
    return d.copyWith(
      language: AppLanguage.fromJson(json['language']),
      themeMode: AppThemeMode.fromJson(json['themeMode']),
      resumePolicy: ResumePolicy.fromJson(json['resumePolicy']),
      restoreLastSession: bool0('restoreLastSession', d.restoreLastSession),
      singleInstance: bool0('singleInstance', d.singleInstance),
      seekStepSeconds: (json['seekStepSeconds'] is num)
          ? (json['seekStepSeconds']! as num).round()
          : d.seekStepSeconds,
      defaultSpeed: num0('defaultSpeed', d.defaultSpeed),
      startupVolume: StartupVolume.fromJson(json['startupVolume']),
      fixedVolume: num0('fixedVolume', d.fixedVolume),
      subtitleScale: num0('subtitleScale', d.subtitleScale),
      subtitleAutoLoad: bool0('subtitleAutoLoad', d.subtitleAutoLoad),
      subtitleDelay: num0('subtitleDelay', d.subtitleDelay),
      equalizerEnabled: bool0('equalizerEnabled', d.equalizerEnabled),
      equalizerGains: gains is List
          ? gains.whereType<num>().map((n) => n.toDouble()).toList()
          : d.equalizerGains,
      pdfLayout: DocumentLayout.fromJson(json['pdfLayout']),
      readingDark: bool0('readingDark', d.readingDark),
      textScale: num0('textScale', d.textScale),
      docAutoSave: bool0('docAutoSave', d.docAutoSave),
      docAutoSaveIntervalSeconds: (json['docAutoSaveIntervalSeconds'] is num)
          ? (json['docAutoSaveIntervalSeconds']! as num).round()
          : d.docAutoSaveIntervalSeconds,
      unsavedChangesPolicy: UnsavedChangesPolicy.fromJson(json['unsavedChangesPolicy']),
      screenshotNamePattern: json['screenshotNamePattern'] is String
          ? json['screenshotNamePattern']! as String
          : d.screenshotNamePattern,
      normalPlayerAlwaysOnTop: bool0('normalPlayerAlwaysOnTop', d.normalPlayerAlwaysOnTop),
      miniPlayerAlwaysOnTop: bool0('miniPlayerAlwaysOnTop', d.miniPlayerAlwaysOnTop),
      imageEditSuffix: json['imageEditSuffix'] is String
          ? json['imageEditSuffix']! as String
          : d.imageEditSuffix,
      imageEditQuality: (json['imageEditQuality'] is num)
          ? (json['imageEditQuality']! as num).round()
          : d.imageEditQuality,
      inAppOpenTarget: InAppOpenTarget.fromJson(json['inAppOpenTarget']),
      rememberPlaybackState: bool0('rememberPlaybackState', d.rememberPlaybackState),
      historyRetentionDays: (json['historyRetentionDays'] is num)
          ? (json['historyRetentionDays']! as num).round()
          : d.historyRetentionDays,
    );
  }


  /// Applique des changements partiels (format de [toJson]) ; les clés
  /// inconnues sont ignorées, les valeurs bornées comme à la relecture.
  AppPreferences merge(Map<String, Object?> changes) =>
      AppPreferences.fromJson({...toJson(), ...changes});

  @override
  bool operator ==(Object other) =>
      other is AppPreferences && _mapEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hashAll(toJson().values.map((v) => v is List ? Object.hashAll(v) : v));

  static bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!_valueEquals(a[key], b[key])) return false;
    }
    return true;
  }

  static bool _valueEquals(Object? va, Object? vb) {
    if (va is List && vb is List) {
      if (va.length != vb.length) return false;
      for (var i = 0; i < va.length; i++) {
        if (va[i] != vb[i]) return false;
      }
      return true;
    }
    return va == vb;
  }
}

/// Réglages qui diffèrent entre [before] et [after], au format de
/// [AppPreferences.toJson].
Map<String, Object?> preferencesDiff(AppPreferences before, AppPreferences after) {
  final a = before.toJson();
  final b = after.toJson();
  return {
    for (final key in b.keys)
      if (!AppPreferences._valueEquals(a[key], b[key])) key: b[key],
  };
}
