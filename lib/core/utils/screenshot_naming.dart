import 'package:path/path.dart' as p;

/// Nom de fichier d'une capture d'écran, d'après un motif.
///
/// Jetons reconnus :
/// - `{name}` : nom du média sans extension (« capture » s'il est vide) ;
/// - `{date}` : `2026-09-07` ;
/// - `{time}` : `21-14-05` (heure de la capture) ;
/// - `{position}` : `01-02-03` (position dans le média).
///
/// Le motif par défaut, `{name} {date} {time}`, donne
/// `<média> 2026-09-07 21-14-05.png`. Les caractères interdits par Windows
/// (`\ / : * ? " < > |`) sont remplacés, pour que le même nom fonctionne sur
/// les trois systèmes.
String screenshotFileName(
  String mediaPath,
  DateTime when, {
  String pattern = '{name} {date} {time}',
  Duration position = Duration.zero,
  String extension = 'png',
}) {
  final base = sanitiseFileName(p.basenameWithoutExtension(mediaPath));
  final date = '${when.year.toString().padLeft(4, '0')}-${_two(when.month)}-${_two(when.day)}';
  final time = '${_two(when.hour)}-${_two(when.minute)}-${_two(when.second)}';
  final pos = '${_two(position.inHours)}-${_two(position.inMinutes % 60)}-'
      '${_two(position.inSeconds % 60)}';

  final name = pattern
      .replaceAll('{name}', base.isEmpty ? 'capture' : base)
      .replaceAll('{date}', date)
      .replaceAll('{time}', time)
      .replaceAll('{position}', pos);

  final cleaned = sanitiseFileName(name);
  return '${cleaned.isEmpty ? 'capture $date $time' : cleaned}.$extension';
}

String _two(int value) => value.toString().padLeft(2, '0');

/// Retire ce qu'un système de fichiers refuse dans un nom.
String sanitiseFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  // Windows refuse aussi un nom finissant par un point ou un espace.
  return cleaned.replaceAll(RegExp(r'[. ]+$'), '');
}
