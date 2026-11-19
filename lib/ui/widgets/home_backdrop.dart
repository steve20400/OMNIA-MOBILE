import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/controllers/media_router.dart';
import '../../core/models/app_preferences.dart';
import '../../core/providers.dart';
import '../theme/omnia_theme.dart';
import 'media_thumbnail.dart';

/// La teinte d'un média, tirée de son aperçu : elle colore le fond de
/// l'accueil. `null` sans aperçu.
///
/// L'aperçu demandé est celui des vignettes de l'accueil, déjà en cache : la
/// teinte ne coûte qu'un décodage en tout petit.
final homeTintProvider = FutureProvider.autoDispose.family<Color?, String>((ref, path) async {
  final bytes =
      await ref.read(mediaLibraryProvider).thumbnail(path, MediaRouter.typeForPath(path));
  if (bytes == null || bytes.isEmpty) return null;
  return tintFromEncoded(bytes);
});

/// La teinte d'une image encodée (JPEG, PNG…), décodée en tout petit.
Future<Color?> tintFromEncoded(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 32);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    codec.dispose();
    if (data == null) return null;
    return tintFromPixels(data.buffer.asUint8List());
  } on Object {
    return null;
  }
}

/// La couleur dominante de [pixels] (RGBA), où les teintes vives pèsent plus
/// que les gris : un ciel bleu l'emporte sur le bitume, une pochette rouge
/// sur son fond noir.
Color? tintFromPixels(Uint8List pixels) {
  var red = 0.0;
  var green = 0.0;
  var blue = 0.0;
  var weight = 0.0;
  for (var i = 0; i + 3 < pixels.length; i += 4) {
    final r = pixels[i];
    final g = pixels[i + 1];
    final b = pixels[i + 2];
    final hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
    final w = 0.05 + hsv.saturation * hsv.value;
    red += r * w;
    green += g * w;
    blue += b * w;
    weight += w;
  }
  if (weight == 0) return null;
  return Color.fromARGB(
    255,
    (red / weight).round().clamp(0, 255),
    (green / weight).round().clamp(0, 255),
    (blue / weight).round().clamp(0, 255),
  );
}

/// La couleur d'ambiance de l'accueil, tirée de la teinte d'un média et
/// réglée pour le thème : profonde en sombre, claire et douce en clair.
///
/// Une image sans couleur franche — une page blanche, un film en noir et
/// blanc — prend celle du projecteur : un fond gris ne dirait rien.
Color homeAmbient(Color? tint, OmniaColors colors, {required bool dark}) {
  final source = HSLColor.fromColor(tint ?? colors.projector);
  final base = source.saturation < 0.12 ? HSLColor.fromColor(colors.projector) : source;
  return dark
      ? base.withSaturation(base.saturation.clamp(0.35, 0.8)).withLightness(0.3).toColor()
      : base.withSaturation(base.saturation.clamp(0.3, 0.7)).withLightness(0.83).toColor();
}

/// Garde l'image de fond choisie dans les fichiers d'OMNIA et rend son
/// chemin.
///
/// Le sélecteur d'Android rend une copie posée dans le cache, que le système
/// peut vider à tout moment : le fond disparaîtrait un beau matin. Chaque
/// image reçoit un nom neuf — un même nom resterait affiché depuis le cache
/// des images — et les précédentes sont effacées.
Future<String> keepHallWallpaper(String source, {Directory? directory}) async {
  try {
    final folder = directory ??
        Directory(p.join((await getApplicationSupportDirectory()).path, 'fond-accueil'));
    await folder.create(recursive: true);
    final target = p.join(
      folder.path,
      'fond-${DateTime.now().millisecondsSinceEpoch}${p.extension(source).toLowerCase()}',
    );
    await File(source).copy(target);
    await for (final old in folder.list()) {
      if (old is File && old.path != target) {
        try {
          await old.delete();
        } on FileSystemException {
          // Une ancienne image qui résiste : elle ne gêne personne.
        }
      }
    }
    return target;
  } on Object {
    // Copie impossible : l'image d'origine fera l'affaire tant qu'elle dure.
    return source;
  }
}

/// Le fond de l'accueil, fixe derrière la page qui défile.
///
/// - **Aperçu** : un dégradé tiré des couleurs de la séance ; son image nette
///   est portée par la tête de page, qui défile avec elle.
/// - **Affiche** : l'image de la séance, floutée, sur tout l'écran.
/// - **Image** : une image choisie, sur tout l'écran.
/// - **Uni** : le fond du thème seul.
///
/// Sans séance, Aperçu et Affiche montrent un dégradé de la couleur du
/// projecteur : l'accueil n'est jamais un aplat terne.
class HomeBackdrop extends ConsumerWidget {
  const HomeBackdrop({
    super.key,
    required this.mode,
    required this.wallpaper,
    required this.path,
  });

  final HallBackground mode;
  final String wallpaper;

  /// Le média mis en avant, `null` sans séance.
  final String? path;

  /// Les couches qui se remplacent remplissent tout l'écran, et non leur
  /// taille naturelle.
  static Widget _fill(Widget? current, List<Widget> previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, ?current],
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final featured = path;
    final tinted = mode == HallBackground.preview || mode == HallBackground.artwork;
    final tint = tinted && featured != null
        ? ref.watch(homeTintProvider(featured)).valueOrNull
        : null;
    final ambient = homeAmbient(tint, colors, dark: dark);
    final covering = mode == HallBackground.artwork || mode == HallBackground.wallpaper;

    final Widget? image = switch (mode) {
      HallBackground.plain || HallBackground.preview => null,
      HallBackground.wallpaper => wallpaper.isEmpty
          ? null
          : Image.file(
              File(wallpaper),
              key: ValueKey('fond:$wallpaper'),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
      HallBackground.artwork => featured == null
          ? null
          : Opacity(
              key: ValueKey('affiche:$featured'),
              opacity: dark ? 0.85 : 0.65,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26, tileMode: TileMode.decal),
                child: Transform.scale(
                  scale: 1.1,
                  child: MediaThumbnail(path: featured),
                ),
              ),
            ),
    };

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: colors.velvet),
          if (tinted)
            // La couleur glisse d'une séance à l'autre au lieu de sauter.
            TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: ambient),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, color, _) => _AmbientGradient(
                color: color ?? ambient,
                velvet: colors.velvet,
                dark: dark,
              ),
            ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            layoutBuilder: _fill,
            child: image ?? const SizedBox.shrink(key: ValueKey('sans-image')),
          ),
          // Le voile de lisibilité : léger en haut, où se tient la séance,
          // presque uni plus bas, où se lisent les listes. En clair, il est
          // plus léger : un voile de papier épais effaçait l'image.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.velvet.withValues(alpha: covering ? (dark ? 0.3 : 0.2) : 0),
                  colors.velvet.withValues(alpha: covering ? (dark ? 0.62 : 0.5) : 0.35),
                  colors.velvet.withValues(alpha: dark ? 0.9 : 0.82),
                ],
                stops: const [0, 0.42, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Le dégradé d'ambiance : la couleur du média, forte en haut où se tient
/// la séance, qui s'éteint vers le fond du thème, avec un second foyer plus
/// discret en bas à gauche pour la profondeur.
class _AmbientGradient extends StatelessWidget {
  const _AmbientGradient({required this.color, required this.velvet, required this.dark});

  final Color color;
  final Color velvet;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.35, -0.85),
              radius: 1.25,
              colors: [
                color.withValues(alpha: dark ? 0.95 : 0.9),
                color.withValues(alpha: dark ? 0.4 : 0.45),
                velvet.withValues(alpha: 0),
              ],
              stops: const [0, 0.5, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-1, 0.9),
              radius: 1.1,
              colors: [
                color.withValues(alpha: dark ? 0.32 : 0.28),
                velvet.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
