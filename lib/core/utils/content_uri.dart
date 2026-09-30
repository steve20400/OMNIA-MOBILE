/// Les URI « content:// » d'Android.
///
/// Depuis Android 11, la plupart des applications (gestionnaire de fichiers,
/// messageries, stockage en nuage) ne transmettent plus un chemin de fichier
/// mais un URI de fournisseur de contenu. OMNIA les ouvre tels quels, par
/// descripteur : aucun octet n'est recopié, même pour un film de plusieurs
/// gigaoctets.
///
/// Un tel URI ne porte ni extension ni nom lisible. La plateforme relève le
/// vrai nom du fichier à l'ouverture, et ce registre le garde le temps de la
/// session : c'est lui qui donne son type au média et son titre à l'affichage.
library;

/// Préfixe des URI de fournisseur de contenu Android.
const String contentUriScheme = 'content://';

/// Vrai si [path] est un URI de fournisseur de contenu plutôt qu'un chemin.
bool isContentUri(String path) => path.startsWith(contentUriScheme);

/// Au-delà, les plus anciens noms sont oubliés : un lecteur ouvert des heures
/// n'a pas à garder la trace de tout ce qu'il a lu.
const int _maxRememberedNames = 64;

final Map<String, String> _names = <String, String>{};

/// Retient le nom réel (`film.avi`) derrière un URI.
///
/// Un nom vide ou un chemin ordinaire ne sont pas retenus : ils n'apprennent
/// rien que le chemin ne dise déjà.
void rememberContentUriName(String uri, String name) {
  if (!isContentUri(uri) || name.isEmpty) return;
  // Le réinscrire le remet en fin de file : ce sont les plus anciens qui
  // partent, pas celui qu'on vient d'ouvrir.
  _names.remove(uri);
  _names[uri] = name;
  while (_names.length > _maxRememberedNames) {
    _names.remove(_names.keys.first);
  }
}

/// Nom réel retenu pour [uri], ou `null` : URI inconnu, ou chemin ordinaire.
String? contentUriDisplayName(String uri) => _names[uri];

/// Vide le registre. Réservé aux tests : deux tests ne doivent pas se passer
/// des noms sous la table.
void forgetContentUriNames() => _names.clear();
