/// Comparaison « naturelle » de noms de fichiers.
///
/// Le tri alphabétique brut place `ep10` avant `ep2`, ce qui est insupportable
/// pour une série. Ici, les suites de chiffres sont comparées comme des
/// nombres : `ep2` < `ep10` < `ep11`.
///
/// Les zéros de tête ne changent pas la valeur (`ep02` se range comme `ep2`).
///
/// Le texte est comparé sans tenir compte de la casse ; à égalité, la casse
/// départage pour que l'ordre reste stable et déterministe. Deux fichiers
/// distincts ne renvoient donc jamais 0 : `ep02` et `ep2` se rangent côte à
/// côte, mais dans un ordre reproductible.
int compareNatural(String a, String b) {
  final la = a.toLowerCase();
  final lb = b.toLowerCase();

  var i = 0;
  var j = 0;
  while (i < la.length && j < lb.length) {
    final ca = la.codeUnitAt(i);
    final cb = lb.codeUnitAt(j);
    final aDigit = _isDigit(ca);
    final bDigit = _isDigit(cb);

    if (aDigit && bDigit) {
      // Deux nombres : on les compare par valeur, pas caractère par caractère.
      final startA = i;
      final startB = j;
      while (i < la.length && _isDigit(la.codeUnitAt(i))) {
        i++;
      }
      while (j < lb.length && _isDigit(lb.codeUnitAt(j))) {
        j++;
      }

      // Les zéros de tête ne changent pas la valeur (`ep02` == `ep2`).
      final sa = _stripLeadingZeros(la.substring(startA, i));
      final sb = _stripLeadingZeros(lb.substring(startB, j));

      if (sa.length != sb.length) return sa.length - sb.length;
      if (sa != sb) return sa.compareTo(sb);
      continue;
    }

    if (ca != cb) return ca - cb;
    i++;
    j++;
  }

  // Le plus court d'abord si l'un est le préfixe de l'autre.
  final rest = (la.length - i) - (lb.length - j);
  if (rest != 0) return rest;

  // Égalité insensible à la casse : on départage pour rester déterministe.
  return a.compareTo(b);
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

String _stripLeadingZeros(String digits) {
  var k = 0;
  while (k < digits.length - 1 && digits.codeUnitAt(k) == 0x30) {
    k++;
  }
  return digits.substring(k);
}
