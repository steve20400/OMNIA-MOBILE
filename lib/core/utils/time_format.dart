/// Formate une durée en timecode `mm:ss` ou `h:mm:ss`.
///
/// [reference] permet d'aligner l'écoulé sur la durée totale : si la référence
/// dépasse une heure, l'écoulé affiche aussi les heures (`0:04:12`), pour que
/// les deux timecodes gardent la même largeur.
String formatTimecode(Duration value, {Duration? reference}) {
  final d = value.isNegative ? Duration.zero : value;
  final showHours = (reference ?? d).inHours > 0;
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return showHours ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// Formate une vitesse : `1×`, `1.5×`, `0.75×`.
String formatSpeed(double speed) {
  final rounded = (speed * 100).round() / 100;
  if (rounded == rounded.roundToDouble()) return '${rounded.toInt()}';
  return rounded.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}
