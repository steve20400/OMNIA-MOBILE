# Chantiers OMNIA

Inventaire des bugs et des fonctionnalités à venir, rangé par ordre de
travail. Couvre les deux dépôts : `OMNIA-Descktop` et `OMNIA-MOBILE`.

Source : tests de Steve des 3, 4 et 7 novembre 2026. Dernière mise à jour :
17 novembre 2026.

**Règle d'ordre** : on descend la liste. Les régressions d'abord — ce qui
marchait et ne marche plus coûte plus cher que ce qui n'a jamais marché. Les
fonctionnalités ne commencent qu'une fois tous les bugs réglés.

---

## Où on en est

Chaque point porte deux cases. La première se coche quand la correction est
écrite et que la CI la compile ; la seconde quand **Steve l'a vue marcher**.
Seule la seconde vaut « réglé » : je ne peux pas lancer l'application ici.

| | Corrigé, compilé | Confirmé au test |
|---|---|---|
| 0.1 Mini-lecteur sans boutons | ✅ | — |
| 0.2 Curseur qui disparaît | ✅ | — |
| 1.1 Mini-lecteur figé au redimensionnement | ✅ | — |
| 1.2 Fenêtre floue | en partie | — |
| 1.3 Bords de fenêtre invisibles | ✅ | — |
| 1.4 Fermeture pas assez rapide | ✅ | — |
| 2.1 Fond noir de l'icône mobile | ✅ | — |
| 2.2 Fichiers voisins absents | ✅ | — |
| 2.3 Défilement en fenêtre flottante | ✅ | — |
| 2.4 Barre des documents sur mobile | ✅ | — |
| 3.1 Mode « Point d'accès » | ✅ | — |
| 3.2 Pare-feu | ✅ | — |
| 3.3 Lecture miroir | ✅ | — |
| 3.4 Erreur intermittente en Wi-Fi | message précisé, capture attendue | — |
| 4.1 Accueil mobile à quatre onglets | ✅ | — |
| 4.2 Actualiser la projection | ✅ | — |
| 4.3 Transfert de fichiers | ✅ | — |

---

## 0. Régressions — ça marchait avant

### 0.1 — Bureau : le mini-lecteur n'a plus aucun bouton

En mode mini-lecteur, les boutons apparaissaient un instant puis
disparaissaient totalement. Plus de fermeture, plus d'épinglage, plus de zoom.

> « Dès qu'on se met en mode mini-lecteur, les boutons apparaissent un
> moment, après ça a disparu totalement. […] Il y a une personne qui a cassé
> quelque chose là-bas qu'il ne fallait pas. »

**Cause** (`3d6c736`) : deux, et il fallait les deux. Un document effaçait sa
barre dans le mini-lecteur comme ailleurs, alors que ses commandes sont tout
ce qu'il a. Et le clic du mini-lecteur passait par la fonction dont un
document coupe justement le réveil : rien ne pouvait les rappeler.

- [x] Corrigé, compilé
- [ ] Confirmé au test

### 0.2 — Bureau : le curseur de la souris disparaît avec la barre

> « Ce qui était dit de demander de faire disparaître au bout de 5 secondes
> d'inactivité, c'est uniquement la barre de dessous là. Le curseur devait
> rester intact. »

**La règle voulue, pour mémoire** : seule la barre s'efface, au bout de cinq
secondes. Faire défiler ne la ramène pas. Seul un **clic** dans la fenêtre la
ramène. Le curseur ne disparaît jamais sur un document.

**Cause** (`3d6c736`) : le code effaçait le pointeur avec les commandes sans
distinguer une vidéo d'un document.

- [x] Corrigé, compilé
- [ ] Confirmé au test

---

## 1. Bureau

### 1.1 — Le mini-lecteur plante au redimensionnement

Signalé depuis le 3 novembre, corrigé deux fois à côté avant de trouver.

**Cause réelle** (`549ef71`) : à chaque image d'un redimensionnement, la vue
PDF demande un ajustement à la largeur. Il était exécuté par un zoom **animé**
dont la fin était **attendue** dans la file des commandes. Or pdfrx remet son
animation à zéro à chaque changement de taille, et une animation annulée ne se
termine jamais. La file étant strictement ordonnée, cette première commande
suspendue emportait toutes les suivantes : plus de défilement, plus de zoom,
plus de sortie du mini-lecteur.

L'ajustement se fait désormais sans animation, et plus aucune commande
n'attend la fin d'une animation. Deux filets restent en place au cas où : les
appels à la fenêtre sont bornés (`7e0c67a`), et une commande qui ne répond pas
en soixante secondes est abandonnée **en disant son nom** (`76244e5`).

> Si un message « la commande … n'a pas abouti » apparaît un jour, il désigne
> le coupable : me l'envoyer tel quel.

- [x] Corrigé, compilé
- [ ] Confirmé au test

### 1.2 — La fenêtre devient floue

À l'agrandissement rapide, et parfois à l'ouverture d'un fichier.

> « Ce genre de petits bugs là ne doit pas exister. »

**Cause** (`549ef71`) : la même que 1.1 pour l'agrandissement — tant que les
ajustements animés se succédaient, la page restait en transition entre deux
tailles. Et à l'ouverture, le média entrait à 98,5 % de sa taille dans un
fondu : rééchantillonné, donc mou le temps de la transition.

**Ce qui peut rester** : sous Windows, pendant qu'on étire une fenêtre, le
système montre l'ancienne image étirée tant que la nouvelle n'est pas
dessinée. Les deux retards ci-dessus sont corrigés ; il peut subsister un
flou bref à l'agrandissement rapide. Le suspect suivant est connu : le
greffon de fenêtre (`window_manager`) répond à Windows qu'il n'a rien à
redessiner quand la fenêtre change de taille. Le corriger demande d'embarquer
ce greffon dans le projet, et risque d'échanger le flou contre un
clignotement — à n'essayer que si le test le demande, dans un commit à part.

- [x] Deux causes corrigées, compilées
- [ ] Test : dire si le flou persiste, et **où** — document ou vidéo, Windows
      ou Ubuntu, en étirant le bord ou en agrandissant d'un coup

### 1.3 — On ne distingue pas les bords de la fenêtre

> « Lorsque j'essaie de redimensionner une des fenêtres, je n'arrive même pas
> à savoir où la fenêtre commence. […] Sur Ubuntu, comme mon fond d'écran est
> noir, les bordures ne se distinguent même pas du fond d'écran. Je suis
> obligé de passer l'application au thème clair avant de pouvoir la
> redimensionner. »

**Cause** (`a027e12`) : la barre de titre du système est masquée, donc le
système ne dessine plus de bord, et rien ne l'avait remplacé. OMNIA dessine
maintenant un trait, d'une couleur prise à l'écart du fond de l'application
**et** d'un bureau sombre.

- [x] Corrigé, compilé
- [ ] Confirmé au test — notamment deux fenêtres superposées, et Ubuntu sur
      fond noir

### 1.4 — La fermeture n'est pas encore assez rapide

La référence est VLC.

> « Je ne veux pas une application de basse gamme, je veux une application
> qui soit une référence. »

**Cause** (`de9cc83`) : la fenêtre restait affichée pendant qu'OMNIA coupait
le son puis enregistrait son état — jusqu'à plus de trois secondes dans le
pire cas. Elle disparaît maintenant à l'instant du clic, en même temps que le
son ; l'enregistrement se fait derrière, fenêtre déjà invisible. Rien n'est
perdu : ce qui était enregistré l'est toujours.

- [x] Corrigé, compilé
- [ ] Confirmé au test

---

## 2. Mobile

### 2.1 — L'arrière-plan noir de l'icône ne part pas

Écarté par les tests de Steve : redémarrage, vidage du cache,
**désinstallation complète puis réinstallation**. Ce n'était donc pas le cache
du lanceur, contrairement à ce que j'avais conclu le 3 novembre.

**Cause réelle** (`485dd05`) : j'avais rendu le fond de l'icône adaptative
transparent pour qu'elle n'ait « pas de fond ». Or un lanceur découpe les deux
couches à sa forme, et là où elles sont toutes deux transparentes il peint du
**noir**, pas le fond d'écran. Android impose une plaque : on n'en choisit que
la couleur.

L'icône a désormais une plaque claire (le blanc chaud de la palette), et le
moniteur y prend un cadre prune pour rester lisible. Le dessin est aussi rendu
plus petit, pour ne pas être rogné par un lanceur à icônes rondes.

**À savoir** : une icône Android *sans aucune plaque* n'existe pas depuis
Android 8. Si la plaque claire ne convient pas, sa couleur se change en une
ligne — dire laquelle.

- [x] Corrigé, compilé
- [ ] Confirmé au test

### 2.2 — Les fichiers voisins manquent à l'ouverture depuis l'extérieur

En ouvrant un fichier depuis le gestionnaire de fichiers (« Ouvrir avec →
OMNIA »), le menu latéral ne montrait pas les autres fichiers du même dossier.

**Cause** (`c154067`) : un gestionnaire de fichiers partage par son propre
fournisseur, dont OMNIA ne savait pas tirer le vrai chemin ; il se rabattait
sur MediaStore, qui ne montre que les médias — un document n'y avait donc
jamais de voisins. Le chemin est maintenant lu dans l'adresse elle-même, et
vérifié (existence, nom, taille) avant d'être utilisé.

- [x] Corrigé, compilé
- [ ] Confirmé au test — dire depuis **quel gestionnaire de fichiers**, si
      cela ne marche pas : chacun a sa façon d'écrire ses adresses

### 2.3 — Pas de défilement du document en mini-lecteur

> « Il ne croit pas que quelqu'un peut arriver à lire le document en mode de
> mini-lecteur. À moins s'il est sur une grosse tablette. Mais il va quand
> même falloir arranger ça. »

**Cause** (`1ca8d0a`) : la fenêtre flottante montrait une image fixe de la
page, et le geste partait faire défiler la vue de l'application — qui ne
dessine rien tant qu'elle est en arrière-plan. Rien ne pouvait donc bouger.

Le défilement se fait maintenant dans la fenêtre même. Tirer au-delà du bas
ou du haut tourne la page. La fenêtre d'un document est en hauteur (3:4) et
non plus en 16:9. Un fichier texte y affiche son texte, et non son seul titre.

- [x] Corrigé, compilé
- [ ] Confirmé au test

### 2.4 — La barre des documents ne s'efface pas

> « Tu dois implémenter ça comme tu as fait pour le lecteur vidéo. »

**Cause** (`02966e1`) : le minuteur tournait bien depuis `9f65c9d`, mais
l'affichage l'ignorait — une condition disait « sur un document, toujours
visible ». Steve avait raison : ce n'était pas fait.

Même règle que sur le bureau : cinq secondes, le défilement ne la rappelle
pas, un toucher bref la rappelle.

- [x] Corrigé, compilé
- [ ] Confirmé au test

---

## 3. Interconnexion

### 3.1 — Le mode « Point d'accès » refuse toujours

> « Le problème à ce niveau, c'est juste peut-être au niveau du bouton.
> Parce que j'ai essayé la connexion, ça a pris instantanément. »

**Cause** (`fcf0954`, `8d45d9f`) : Steve avait vu juste. Le mode exigeait de
reconnaître une interface de partage de connexion. Or des deux appareils
reliés, un seul partage — l'autre n'a qu'une adresse Wi-Fi ordinaire — et
celui qui partage ne montre pas toujours son interface. L'adresse trouvée est
désormais acceptée. Celle des données mobiles, privée mais injoignable, n'est
plus annoncée : elle coûtait une tentative perdue à chaque appairage.

- [x] Corrigé, compilé
- [ ] Confirmé au test

### 3.2 — Le pare-feu : il a fallu le désactiver

> « Si on désactive notre pare-feu, on est exposé. »

> « Si un équipement essaie de se connecter via OMNIA Connect, ça envoie une
> notification à notre machine pour dire que telle personne veut se
> connecter. Si on accepte, ça part créer une règle qui permet de projeter
> sans désactiver le pare-feu. »

**Une limite à connaître** : quand le pare-feu bloque, la demande de connexion
n'arrive jamais jusqu'à OMNIA — c'est justement ce que « bloquer » veut dire.
L'application ne peut donc pas afficher « tel appareil veut se connecter »
pour une connexion que le pare-feu a déjà refusée. La règle doit exister
**avant**. D'où deux pièces distinctes :

- [x] L'installateur pose la règle (`c0d6d92`) — mais seulement pour une
      installation « pour tous les utilisateurs »
- [x] OMNIA vérifie le pare-feu à l'ouverture d'OMNIA Connect et, s'il
      bloque, propose d'autoriser OMNIA d'un clic (`32293e7`). Windows demande
      la confirmation d'administrateur ; un refus ne change rien.
- [ ] Confirmé au test : pare-feu **allumé**, ouvrir OMNIA Connect sur le PC,
      cliquer « Autoriser OMNIA dans le pare-feu », puis appairer
- [ ] Demander l'accord à l'arrivée d'un appareil **inconnu** — c'est une
      protection de plus, à faire avec le chantier de sécurité 7.1

**Ce que le test a révélé en chemin** : la règle de l'installateur pouvait ne
servir à rien. Quand on ferme sans répondre la boîte de Windows « le pare-feu
a bloqué certaines fonctionnalités », Windows crée des règles d'**interdiction**
pour l'application — et une interdiction l'emporte toujours sur une
autorisation. Le bouton retire donc d'abord celles qui visent OMNIA.

**À garder en tête** : la règle rend le serveur d'OMNIA Connect joignable
depuis le réseau, y compris un réseau public. Il ne tourne que lorsque la
fenêtre OMNIA Connect a été ouverte, mais ses protections restent celles
décrites en 7.1 — raison de plus pour ne pas laisser ce chantier attendre.

### 3.3 — La lecture miroir ne suit pas les petits gestes

| Geste | Avant |
|---|---|
| Avance brusque (2ᵉ → 10ᵉ minute) | suivait |
| Avance lente à la molette | ne suivait pas |
| Saut de page (1 → 30) | suivait |
| Défilement lent d'un document | ne suivait pas |
| Pause sur le mobile | ne suivait pas |
| Volume | suivait parfois |

> « J'ai l'impression que l'envoi des commandes n'est pas temps réel. […] On
> ne peut pas me dire que c'est un problème de connexion. »

**Cause** (`1cd7279`, `ede071a`) : ce n'était pas le réseau, et Steve avait
raison sur le rythme. L'envoi était cadencé sur la seule position de lecture :
un état ne partait que lorsqu'elle changeait de demi-seconde. En pause elle ne
bouge plus — la pause elle-même ne partait donc jamais. Et la position de
lecture d'un document est immobile par nature : seuls les changements de page
passaient.

L'envoi regarde maintenant ce qui a changé, quoi que ce soit, et part en
soixante millisecondes au plus. Le lecteur PDF publie sa position dans le
document, et non plus sa seule page.

- [x] Corrigé, compilé
- [ ] Confirmé au test — pause, volume, avance lente, défilement lent

### 3.4 — Message d'erreur intermittent en Wi-Fi

Sur un Wi-Fi partagé avec d'autres appareils, l'appairage marche parfois et
échoue parfois, avec un message. **Capture d'écran attendue de Steve.**

Le correctif 3.1 peut y avoir changé quelque chose : l'adresse des données
mobiles n'est plus essayée en premier.

- [x] En attendant la capture, ce qui vaut quelle que soit la cause :
      l'appairage fait deux passes sur toutes les adresses annoncées (une
      tentative perdue sur un Wi-Fi chargé ne condamne plus la suivante),
      et le message d'échec donne, pour chaque adresse, **sa cause** : pas
      de réponse (pare-feu, ou réseau qui isole les appareils), connexion
      refusée (OMNIA Connect fermé), refus de l'autre appareil (rescanner le
      QR code), ou adresse injoignable. Le PC essaie désormais lui aussi
      toutes les adresses du téléphone, et non plus la première seule.
- [ ] Capture du message au prochain échec : il dira maintenant laquelle
      de ces causes est en jeu.

---

## 4. Fonctionnalités — seulement après les bugs

### 4.1 — Refonte de l'accueil mobile

Référence citée : Visual Player.

**Menu de navigation en bas, quatre onglets** — aucune application mobile
d'aujourd'hui n'en est dépourvue.

1. **Accueil**
   - Défilement **horizontal** : fichiers récemment ajoutés au téléphone,
     tous types confondus. Bouton « Tout afficher » qui déploie la liste
     complète sur toute la page.
   - Défilement **vertical** : fichiers récemment ouverts (l'existant).
   - **Aperçus (previews)** partout : vidéos comme documents.
   - Le chemin d'accès sort de la ligne — « ce n'est pas esthétique ».
     Il passe dans un **menu à trois points** par fichier : détails,
     emplacement, ouvrir le dossier contenant.
2. **Dossiers** — parcourir le téléphone depuis l'application, chercher un
   fichier ou un dossier, l'ouvrir d'un clic.
3. **OMNIA Connect** — voir 4.2.
4. **Paramètres** — déplacés du haut vers le bas.

**Menu à trois points en haut à droite**, présent en permanence (accueil,
document, vidéo) : Ouvrir un fichier, Ouvrir un dossier, Rotation d'écran.
Les boutons « Ouvrir fichier » et « Ouvrir dossier » quittent l'accueil.

**Fait, première version** :
- [x] Quatre onglets en bas : Accueil, Dossiers, Connect, Paramètres. Ils
      occupent l'écran tant qu'aucun média n'est ouvert ; le lecteur prend la
      place à l'ouverture et la rend à la fermeture, sur l'onglet quitté.
- [x] Accueil : bande horizontale « Ajoutés récemment » (lue dans la
      bibliothèque d'Android) avec « Tout afficher » ; liste « Ouverts
      récemment » avec aperçu, barre d'avancement et « Reprise à 12:05 sur
      40:00 » à la place du chemin.
- [x] Aperçus : image de la vidéo, pochette de la musique, photo, première
      page du PDF. Les documents texte gardent l'icône de leur type.
- [x] Menu à trois points par fichier : Ouvrir, Ouvrir l'emplacement (qui
      bascule sur l'onglet Dossiers, dans le bon dossier), Détails.
- [x] Dossiers : parcourir les stockages, chercher dans le dossier et ses
      sous-dossiers, ouvrir d'un toucher, « Lire tout le dossier ».
- [x] Menu à trois points en haut à droite, à l'accueil comme dans le
      lecteur ; les deux gros boutons flottants ont disparu.
- [ ] Confirmé au test

**Ce que la refonte a révélé** : l'ancien écran d'accueil n'était affiché
nulle part. Ce que Steve voyait était l'état vide du lecteur. La demande
d'autorisation du mini-lecteur au premier lancement (`007185d`) vivait dans
cet écran fantôme : elle ne s'est donc jamais déclenchée. Elle est maintenant
dans l'accueil réel.

**À savoir** : sans l'accès à « tous les fichiers », Android ne montre à OMNIA
que les vidéos, musiques et images. Les documents n'apparaissent alors ni
dans « Ajoutés récemment » ni dans les dossiers ; l'onglet Dossiers le dit et
propose d'accorder l'accès. C'est désormais la justification de cette
autorisation, signalée par l'audit de sécurité (7.2).

### 4.2 — Projeter sans rescanner

Aujourd'hui, changer de fichier oblige à rescanner le QR : l'appareil distant
continue d'afficher l'ancien fichier.

> « Je dois juste cliquer sur le bouton de projection. J'actualise. »

- [x] Première étape : déjà relié au PC, OMNIA Connect s'ouvre directement
      sur la télécommande et son bouton « Projeter », au lieu du code
      d'appairage. Changer de fichier puis projeter ne demande plus de
      rescanner.
- [x] « Actualiser la projection » dans le menu à trois points en haut à
      droite, en première ligne, dès qu'un média est ouvert et que le
      téléphone est relié au PC. Un toucher envoie le média en cours, dans
      le mode de projection choisi (fichier, miroir ou écran) ; le résultat
      s'affiche en bas de l'écran. Plus besoin de rouvrir OMNIA Connect.
- [x] La liaison tient hors de la fenêtre OMNIA Connect : elle était déjà
      portée par l'application entière, pas par la fenêtre.
- [ ] Confirmé au test : changer de fichier, puis menu → « Actualiser la
      projection », et le PC affiche le nouveau fichier.

OMNIA Connect reste également accessible depuis les paramètres : l'onglet
est un raccourci, pas un déplacement.

### 4.3 — Transfert de fichiers

Transférer un fichier d'un appareil à l'autre, avec choix du dossier de
destination, sur n'importe lequel des trois modes de liaison.

**Fait, première version** :
- [x] « Envoyer un fichier au PC » dans OMNIA Connect sur le téléphone, une
      fois relié ; « Envoyer un fichier au téléphone » dans la fenêtre OMNIA
      Connect du PC, dès qu'un téléphone est relié. Le fichier part par la
      liaison en place, quel que soit son mode (Wi-Fi, point d'accès,
      Bluetooth).
- [x] Celui qui reçoit voit qui envoie, le nom et la taille, et choisit :
      Refuser, ou Recevoir — avec le dossier de destination, modifiable par
      « Changer ». Par défaut : `Téléchargements/OMNIA`. Le dernier dossier
      choisi est repris jusqu'à la fermeture d'OMNIA.
- [x] Barre d'avancement, « Annuler », puis « Ouvrir » (si OMNIA sait le
      lire) et, sur PC, « Afficher dans le dossier ». Sur le téléphone, le
      fichier reçu apparaît aussitôt dans la galerie et l'accueil.
- [x] L'expéditeur suit : proposé, en cours, arrivé, refusé ou échoué.
- [ ] Confirmé au test, dans les deux sens

**Sécurité, choisie d'office** tant que les décisions de 7.1 attendent :
- rien ne s'écrit sans que la personne devant l'appareil qui reçoit ait
  accepté, et une seule demande s'affiche à la fois (une autre est refusée
  d'office : un appareil du réseau ne peut pas couvrir l'écran de fenêtres) ;
- l'expéditeur ne sert que le fichier proposé, sous un jeton propre à cette
  proposition, jusqu'à la réponse finale ou 30 minutes au plus — jamais un
  chemin choisi par l'autre ;
- le fichier est cherché à l'adresse d'où vient la liaison, pas à une
  adresse dictée par le message ;
- le nom reçu est assaini (« ../../x » reste dans le dossier choisi), un
  fichier existant n'est jamais écrasé, la taille annoncée est exigée à
  l'octet près, et un transfert interrompu ne laisse aucun fichier tronqué.

**À savoir** : sur le téléphone, ranger ailleurs que dans `Download` demande
l'accès à « tous les fichiers ». Un appareil resté sur une version
antérieure ignore la proposition : l'expéditeur le dit au bout de deux
minutes sans réponse.

---

## 5. Refonte des interfaces — quand tout le reste est réglé

Ne commence **qu'une fois toutes les fonctionnalités en place et tous les
bugs réglés**. C'est une refonte, pas une retouche, et elle touche les deux
plateformes.

> « Côté IHM, l'application est nulle. […] Côté back-end, tout ce qui tourne
> en arrière-plan, je peux dire c'est bon. »

> « Pour un grand public, je ne vois pas en quoi quelqu'un devrait installer
> ça alors qu'il peut se contenter de VLC. »

**La référence visée, dite explicitement** : l'interface d'accueil d'une
console — PlayStation, Nintendo — et surtout les façades d'émulateurs, leur
page de bibliothèque de jeux. L'accueil qu'on parcourt, les vignettes qui
défilent, le fond personnalisable.

> « Je veux une interface que des gens pourront ouvrir rien que pour la
> laisser sur leur bureau, parce que je veux quelque chose de beau. »

Priorité : le bureau est « carrément très moche » ; le mobile est moins
urgent, et sa refonte d'accueil est déjà cadrée en 4.1.

- [x] Références retenues : l'accueil PS5 (fond tiré du jeu sélectionné),
      celui de la Switch (bande de grandes tuiles, la sélection agrandie et
      cerclée), les façades d'émulateurs en plein écran — Playnite,
      LaunchBox Big Box, ES-DE — (fiche du jeu au-dessus de la bande, fond
      flouté, navigation à la manette)
- [x] Maquette montrée le 17 novembre, **validée par Steve** : « le design
      que tu m'as montré est bon ». Exigences rappelées : tout responsive,
      aucun texte qui déborde, bonne ergonomie, marges et espacements soignés
- [x] Bureau, accueil : « le hall ». Bande d'affiches des médias récents
      (image tirée du film par libmpv, pochette, première page du PDF, la
      photo), sélection éclairée par le projecteur, fond qui suit la
      sélection, fiche de la séance (titre, où l'on en est, Reprendre),
      rayons (Tout, Vidéos, Musique, Documents, Images), heure et date.
      Clavier : ← → Entrée, comme à la manette. Détail dans `DESIGN.md` §7
- [x] Fond d'écran personnalisable : affiche sélectionnée, image à soi, ou
      uni (Paramètres → Général → Fond de l'accueil)
- [x] Images des films : vérifiées en CI contre le vrai libmpv, sous Windows
      et sous Linux. Le libmpv livré sous Windows n'a pas le filtre de
      réduction : l'extracteur s'en passe alors, l'image arrive plus grande
- [x] Palette : plus aucune couleur hors de DESIGN.md (verts, rouges divers
      remplacés par l'ambre du projecteur, la Poussière ou l'Alerte)
- [ ] Manette de jeu : la navigation est prête (← → Entrée), il reste à lire
      la manette elle-même. Demande un greffon natif, et le nom des boutons
      change d'une manette à l'autre : à faire avec la manette de Steve sous
      la main pour l'essayer
- [x] Rayons remplis aussi par les dossiers personnels (Vidéos, Musique,
      Images, Documents ; « Vidéos » et « Musique » d'un Ubuntu en français
      compris) : un premier lancement n'ouvre plus sur un hall vide. Parcours
      borné (3 niveaux, 3 secondes, dossiers cachés et corbeille sautés), hors
      de l'interface. Désactivable : Paramètres → Général → Fichiers de vos
      dossiers
- [x] Panneau du dossier et liste du mini-lecteur : chaque fichier a sa
      petite affiche, cerclée d'ambre pour celui en cours. Les images des
      vidéos se tirent d'abord pour ce qui est à l'écran ; ce qu'on a fait
      défiler est abandonné, pas calculé pour rien
- [x] Mobile, accueil : en tête, la carte « Reprendre » de la dernière
      séance entamée — son image en grand, cerclée d'ambre, le titre, où
      l'on en est, le faisceau, un bouton lecture de 48 px —, sur un fond
      tiré de la même image. Hauteur bornée (160 à 300 px), titre coupé net
      avec un grand texte
- [ ] Refonte page par page, la suite : lecteur, paramètres, fenêtres
      OMNIA Connect
- [ ] Confirmé au test

---

## 6. Horizon

### 6.1 — Lanceur de jeux PC

Le même soin d'interface, appliqué à une bibliothèque de jeux. OMNIA sert
d'entraînement : on apprend la façade ici avant de la faire là-bas.

> « J'avais vu l'interface, waouh, ça m'a impressionné. On aurait dit qu'on
> était sur une PlayStation, et il manipulait même avec les manettes. »

Les projets plus lointains ont leurs propres fichiers :
[`PROJET-LABORATOIRE-VIRTUEL.md`](PROJET-LABORATOIRE-VIRTUEL.md) et
[`PROJET-MONDE-GENERE.md`](PROJET-MONDE-GENERE.md).

---

## 7. Sécurité — décisions en attente

Audit du 4 novembre. Les failles faibles et moyennes sont corrigées
(`ec62097`, `2502901`). Restent :

### 7.1 — Critiques

- [ ] **Clé de signature Android publiée** dans un dépôt public, avec son
      mot de passe écrit en clair dans `android/app/build.gradle` (valeur de
      repli des variables d'environnement). **Décision attendue** :
      générer une nouvelle clé (impose une désinstallation/réinstallation aux
      utilisateurs actuels) ou garder celle-ci en sachant qu'elle est
      publique. La clé est dans l'historique git : la retirer du HEAD ne
      suffit pas.
- [ ] **Tout appareil du réseau local est admis sans jeton** sur `/api/ws`
- [ ] **Lecture de n'importe quel fichier** via `/api/stream?path=`
- [ ] **`openRemoteStream` ouvre n'importe quelle URL** dictée par le client

### 7.2 — Élevées

- [ ] Tout circule en clair : pas de TLS
- [x] En attendant, plus de fausse promesse : OMNIA Connect et les
      Paramètres annonçaient un « chiffrement de session » qui n'existe pas.
      Ils disent maintenant que la liaison passe par le réseau local, sans
      Internet, et n'est pas chiffrée — à réserver à un réseau de confiance
- [ ] `REQUEST_INSTALL_PACKAGES` et `MANAGE_EXTERNAL_STORAGE` à justifier ou
      retirer
- [ ] Les trois interrupteurs d'OMNIA Connect ne sont lus nulle part :
      décoratifs, et tous à `true` par défaut
- [ ] `usesCleartextTraffic="true"`, aucun `networkSecurityConfig`
- [ ] Aucune minification ni obfuscation

### 7.3 — Licence des binaires

Vérifié le 4 novembre. Côté Windows, OMNIA embarque
`mpv-dev-x86_64-20230924-git-652a1dd.7z`, et non le paquet `mpv-dev-lgpl-*`
que l'auteur amont documente comme le seul sous LGPL. Un build mpv standard
est GPL : le distribuer avec une application « Tous droits réservés » est ce
que la GPL interdit. Android et Linux ne posent pas ce problème.

**Décision attendue** : basculer le build Windows sur la variante LGPL et
respecter ses obligations, publier OMNIA sous GPL, ou assumer.

---
