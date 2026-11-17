import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Bascule l'écran entre portrait et paysage.
///
/// Fixe l'orientation au lieu de suivre le capteur : c'est ce qu'on attend
/// d'un bouton, qui doit avoir un effet même téléphone posé à plat.
Future<void> toggleScreenOrientation(BuildContext context) {
  final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
  return SystemChrome.setPreferredOrientations(
    landscape
        ? const [DeviceOrientation.portraitUp]
        : const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
  );
}
