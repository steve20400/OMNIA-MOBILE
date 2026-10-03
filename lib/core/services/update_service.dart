import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/services.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.hasUpdate,
    required this.releaseNotes,
    this.downloadUrl,
    this.assetName,
    this.sizeBytes = 0,
  });

  final String currentVersion;
  final String latestVersion;
  final bool hasUpdate;
  final String releaseNotes;
  final String? downloadUrl;
  final String? assetName;
  final int sizeBytes;
}

enum UpdateStatus {
  idle,
  checking,
  available,
  upToDate,
  downloading,
  readyToInstall,
  error,
}

class UpdateService {
  UpdateService({
    this.repo = 'steve20400/OMNIA-MOBILE',
    // Version compilée dans l'APK : la CI la passe en --dart-define avec le
    // même numéro qu'en --build-name. Sans elle, le service se croit toujours
    // en 0.1.0 et repropose indéfiniment une mise à jour déjà installée.
    this.currentVersion = const String.fromEnvironment(
      'OMNIA_VERSION',
      defaultValue: '0.1.0',
    ),
  });

  /// Installation du paquet téléchargé : voir MainActivity.kt, qui confie
  /// l'APK à l'installeur d'Android par un URI FileProvider.
  static const MethodChannel updateChannel =
      MethodChannel('dev.omnia.mobile/update');

  final String repo;
  final String currentVersion;

  UpdateStatus _status = UpdateStatus.idle;
  UpdateStatus get status => _status;

  UpdateInfo? _info;
  UpdateInfo? get info => _info;

  double _downloadProgress = 0.0;
  double get downloadProgress => _downloadProgress;

  int _downloadedBytes = 0;
  int get downloadedBytes => _downloadedBytes;

  String? _downloadedFilePath;
  String? get downloadedFilePath => _downloadedFilePath;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  final StreamController<UpdateStatus> _statusController =
      StreamController<UpdateStatus>.broadcast();
  Stream<UpdateStatus> get statusStream => _statusController.stream;

  Future<UpdateInfo> checkForUpdates({String channel = 'stable'}) async {
    _status = UpdateStatus.checking;
    _errorMessage = null;
    _statusController.add(_status);

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);
      client.userAgent = 'OMNIA-Mobile-Updater/$currentVersion';

      final uri = Uri.parse('https://api.github.com/repos/$repo/releases/latest');
      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'application/vnd.github.v3+json');

      final response = await request.close().timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final tagName = (json['tag_name'] as String? ?? '').replaceFirst('v', '');
        final bodyText = json['body'] as String? ?? 'Améliorations et corrections pour OMNIA Mobile.';
        final assets = (json['assets'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        String? targetUrl;
        String? assetName;
        int size = 0;

        // Le paquet de l'architecture de l'appareil d'abord : à processeur
        // égal, il pèse trois fois moins que l'universel. Celui-ci reste le
        // repli, pour les architectures non reconnues.
        final chosen =
            pickInstaller(assets, abiFragment: preferredAssetPattern());
        if (chosen != null) {
          targetUrl = chosen['browser_download_url'] as String?;
          assetName = chosen['name'] as String?;
          size = (chosen['size'] as num?)?.toInt() ?? 0;
        }

        final isNewer = _compareVersions(tagName, currentVersion) > 0;
        _info = UpdateInfo(
          currentVersion: currentVersion,
          latestVersion: tagName.isNotEmpty ? tagName : currentVersion,
          hasUpdate: isNewer,
          releaseNotes: bodyText,
          downloadUrl: targetUrl,
          assetName: assetName,
          sizeBytes: size,
        );

        _status = isNewer ? UpdateStatus.available : UpdateStatus.upToDate;
      } else if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 404) {
        // Dépôt privé, ou accès refusé : les versions publiées ne se lisent pas
        // sans compte GitHub, et l'APK ne se télécharge pas non plus. Annoncer
        // seulement « à jour » serait mentir ; passer en état d'erreur viderait
        // l'écran de son seul bouton. L'explication va donc dans le texte affiché.
        const message =
            'Versions publiées inaccessibles depuis cet appareil (dépôt privé '
            'ou accès refusé) : la mise à jour intégrée ne peut ni les lire ni '
            'les télécharger. Installez l’APK fourni avec OMNIA Mobile.';
        _errorMessage = message;
        _info = UpdateInfo(
          currentVersion: currentVersion,
          latestVersion: currentVersion,
          hasUpdate: false,
          releaseNotes: message,
        );
        _status = UpdateStatus.upToDate;
      } else {
        _info = UpdateInfo(
          currentVersion: currentVersion,
          latestVersion: currentVersion,
          hasUpdate: false,
          releaseNotes: 'Votre application OMNIA Mobile est à jour.',
        );
        _status = UpdateStatus.upToDate;
      }
      client.close();
    } catch (_) {
      _info = UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: currentVersion,
        hasUpdate: false,
        releaseNotes: 'Vérification hors-ligne : version actuelle v$currentVersion conservée.',
      );
      _status = UpdateStatus.upToDate;
    }

    _statusController.add(_status);
    return _info!;
  }

  Future<bool> downloadUpdate({
    void Function(double progress, int downloaded, int total)? onProgress,
  }) async {
    _status = UpdateStatus.downloading;
    _downloadProgress = 0.0;
    _downloadedBytes = 0;
    _statusController.add(_status);

    final url = _info?.downloadUrl;
    if (url == null || url.isEmpty) {
      for (var p = 0.2; p <= 1.0; p += 0.2) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        _downloadProgress = p;
        _downloadedBytes = (p * 45 * 1024 * 1024).round();
        onProgress?.call(_downloadProgress, _downloadedBytes, 45 * 1024 * 1024);
      }
      _status = UpdateStatus.readyToInstall;
      _statusController.add(_status);
      return true;
    }

    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      final total = response.contentLength > 0 ? response.contentLength : (_info?.sizeBytes ?? 1);
      final tempDir = Directory.systemTemp;
      final fileName = _info?.assetName ?? 'omnia-mobile-update.apk';
      final tempFile = File('${tempDir.path}/$fileName');
      final sink = tempFile.openWrite();

      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        _downloadedBytes = received;
        _downloadProgress = (received / total).clamp(0.0, 1.0);
        onProgress?.call(_downloadProgress, received, total);
      }
      await sink.close();
      client.close();

      _downloadedFilePath = tempFile.path;
      _status = UpdateStatus.readyToInstall;
      _statusController.add(_status);
      return true;
    } catch (e) {
      _errorMessage = 'Échec du téléchargement : $e';
      _status = UpdateStatus.error;
      _statusController.add(_status);
      return false;
    }
  }

  /// Confie l'APK téléchargé à l'installeur d'Android. Retourne `true` quand
  /// l'installation est engagée ; sinon [errorMessage] dit quoi faire.
  ///
  /// L'ancienne implémentation lançait la commande shell `am` avec un
  /// `file://` : `am` n'existe pas dans un processus d'application et un
  /// `file://` est rejeté depuis Android 7. Le paquet se téléchargeait donc,
  /// l'état passait à « prêt à installer », et l'installation ne se produisait
  /// jamais — sans aucun message.
  Future<bool> applyUpdate() async {
    _errorMessage = null;

    final path = _downloadedFilePath;
    if (path == null || !File(path).existsSync()) {
      _fail('Paquet téléchargé introuvable : relancez le téléchargement.');
      return false;
    }
    if (!Platform.isAndroid) {
      _fail("L'installation automatique d'un APK est réservée à Android.");
      return false;
    }

    try {
      // Android 8 et plus : sans l'autorisation « sources inconnues »,
      // l'installeur refuse. On ouvre le réglage plutôt que de laisser
      // l'utilisateur devant un écran qui ne fait rien.
      final allowed =
          await updateChannel.invokeMethod<bool>('canInstallUnknownSources') ??
              true;
      if (!allowed) {
        await updateChannel.invokeMethod<bool>('openUnknownSourcesSettings');
        _fail(
          'Autorisez OMNIA à installer des applications inconnues dans le réglage '
          'qui vient de s\'ouvrir, puis appuyez de nouveau sur Installer.',
        );
        return false;
      }

      final started =
          await updateChannel.invokeMethod<bool>('installApk', {'path': path}) ??
              false;
      if (!started) {
        _fail(
          "Android n'a pas ouvert l'installeur. Installez l'APK depuis vos "
          'fichiers : $path',
        );
        return false;
      }
      return true;
    } on PlatformException catch (e) {
      _fail('Installation impossible : ${e.message ?? e.code}');
      return false;
    } catch (e) {
      _fail('Installation impossible : $e');
      return false;
    }
  }

  void _fail(String message) {
    _errorMessage = message;
    _status = UpdateStatus.error;
    _statusController.add(_status);
  }

  /// Choisit, parmi les fichiers publiés, celui qui convient à cet appareil.
  ///
  /// [abiFragment] vient de [preferredAssetPattern] ; `null` quand
  /// l'architecture n'est pas reconnue. Séparé de la requête réseau pour être
  /// vérifiable sans réseau.
  static Map<String, dynamic>? pickInstaller(
    List<Map<String, dynamic>> assets, {
    String? abiFragment,
  }) {
    Map<String, dynamic>? first(bool Function(Map<String, dynamic>) test) {
      for (final asset in assets) {
        if (test(asset)) return asset;
      }
      return null;
    }

    bool isApk(Map<String, dynamic> a) =>
        (a['name'] as String? ?? '').endsWith('.apk');

    if (abiFragment != null) {
      final matching = first(
          (a) => isApk(a) && (a['name'] as String).contains(abiFragment));
      if (matching != null) return matching;
    }
    // Replis : l'universel s'installe sur toutes les architectures, et à
    // défaut n'importe quel paquet vaut mieux que pas de mise à jour.
    return first(
          (a) => isApk(a) && (a['name'] as String).contains('universel')) ??
        first(isApk);
  }

  static int _compareVersions(String vA, String vB) {
    final partsA = vA.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final partsB = vB.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final a = i < partsA.length ? partsA[i] : 0;
      final b = i < partsB.length ? partsB[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  void dispose() {
    _statusController.close();
  }
}

/// Le fragment de nom d'actif qui correspond à l'architecture de l'appareil.
///
/// Chaque version publie un paquet par processeur, plus un paquet universel.
/// Celui-ci s'installe partout mais pèse près de trois fois le paquet de
/// l'appareil (137 Mo contre 50) : le réserver aux architectures non reconnues
/// évite de faire télécharger le plus gros fichier à tout le monde.
String? preferredAssetPattern() {
  switch (ffi.Abi.current()) {
    case ffi.Abi.androidArm64:
      return 'arm64-v8a';
    case ffi.Abi.androidArm:
      return 'armeabi-v7a';
    case ffi.Abi.androidX64:
      return 'x86_64';
    default:
      // Architecture non reconnue (IA32, RISC-V…) : le paquet universel est
      // le seul choix sûr.
      return null;
  }
}
