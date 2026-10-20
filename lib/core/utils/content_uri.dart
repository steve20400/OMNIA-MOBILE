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
///
/// La limite tient un dossier entier, et le plafond que la plateforme met au
/// nombre de voisins renvoyés : le panneau latéral retient le nom de chaque
/// voisin listé par MediaStore, et c'est ce nom qui donne son type au fichier,
/// son libellé dans la liste et sa place dans le tri naturel. À 64, une série
/// de 200 épisodes perdait les premiers en route.
const int maxRememberedNames = 2048;

/// Dossiers où un média arrive recopié au lieu d'être ouvert sur place :
/// `opened_media` quand la plateforme n'a pas su faire autrement (document ou
/// image derrière un fournisseur distant), `file_picker` quand le sélecteur de
/// fichiers a rendu une copie au lieu d'un chemin.
///
/// Un chemin qui passe par là n'a pas de voisins à montrer : son dossier ne
/// contient que des copies. Les vrais voisins sont ceux de l'original, que
/// MediaStore connaît.
const List<String> copiedMediaFolders = <String>[
  '/cache/opened_media/',
  '/cache/file_picker/',
];

/// Vrai si [path] est une copie faite par la plateforme, pas un vrai fichier
/// de l'utilisateur.
bool isCopiedFromProvider(String path) => copiedMediaFolders.any(path.contains);

final Map<String, String> _names = <String, String>{};

/// Retient le nom réel (`film.avi`) derrière un chemin qui ne le porte pas.
///
/// Deux cas : un URI de fournisseur, qui n'a pas de nom du tout, et une copie
/// faite par la plateforme, dont le nom de fichier est horodaté et expurgé de
/// ses accents (`1738..._Le_Voyage.avi`). Sans ce registre, c'est ce nom-là que
/// l'utilisateur lirait dans le titre et dans le panneau — et c'est lui que la
/// recherche des voisins présenterait à MediaStore, qui n'en connaît aucun.
///
/// Un nom vide ou un chemin ordinaire ne sont pas retenus : ils n'apprennent
/// rien que le chemin ne dise déjà.
void rememberContentUriName(String uri, String name) {
  if (name.isEmpty) return;
  if (!isContentUri(uri) && !isCopiedFromProvider(uri)) return;
  // Le réinscrire le remet en fin de file : ce sont les plus anciens qui
  // partent, pas celui qu'on vient d'ouvrir.
  _names.remove(uri);
  _names[uri] = name;
  while (_names.length > maxRememberedNames) {
    _names.remove(_names.keys.first);
  }
}

/// Nom réel retenu pour [uri], ou `null` : chemin inconnu, ou chemin ordinaire
/// qui porte déjà son nom.
String? contentUriDisplayName(String uri) => _names[uri];

/// Vide le registre. Réservé aux tests : deux tests ne doivent pas se passer
/// des noms sous la table.
void forgetContentUriNames() => _names.clear();
