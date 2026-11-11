# Chantiers OMNIA

Inventaire des bugs et des fonctionnalités à venir, rangé par ordre de
travail. Couvre les deux dépôts : `OMNIA-Descktop` et `OMNIA-MOBILE`.

Source : tests de Steve des 3, 4 et 7 novembre 2026. Dernière mise à jour :
11 novembre 2026.

**Règle d'ordre** : on descend la liste. Les régressions d'abord — ce qui
marchait et ne marche plus coûte plus cher que ce qui n'a jamais marché. Les
fonctionnalités ne commencent qu'une fois tous les bugs réglés.

---

## 0. Régressions — ça marchait avant

### 0.1 — Bureau : le mini-lecteur n'a plus aucun bouton 🔴

En mode mini-lecteur, les boutons apparaissent un instant puis disparaissent
totalement. Plus de fermeture, plus d'épinglage, plus de zoom. Et le
défilement ne répond plus non plus.

> « Dès qu'on se met en mode mini-lecteur, les boutons apparaissent un
> moment, après ça a disparu totalement. […] Il y a une personne qui a cassé
> quelque chose là-bas qu'il ne fallait pas. »

**Cause probable** : l'effacement automatique de la barre des documents
(commit `28ca3b6`) s'applique aussi au mini-lecteur, où il n'a rien à faire.
Le mini-lecteur n'a pas de place pour une barre qui revient au clic.

- [ ] Le mini-lecteur garde ses commandes, quel que soit le type de média

### 0.2 — Bureau : le curseur de la souris disparaît avec la barre 🔴

L'effacement au bout de cinq secondes emporte aussi le pointeur. On manipule
la fenêtre sans voir où on pointe.

> « Ce qui était dit de demander de faire disparaître au bout de 5 secondes
> d'inactivité, c'est uniquement la barre de dessous là. Le curseur devait
> rester intact. »

**Rappel de la règle voulue** : seule la barre s'efface. Faire défiler ne la
ramène pas. Seul un **clic** dans la fenêtre la ramène.

- [ ] Seule la barre s'efface ; le curseur reste visible en permanence

---

## 1. Bureau

### 1.1 — Le mini-lecteur plante toujours au redimensionnement 🔴

Signalé plusieurs fois, toujours pas résolu. Le correctif de la file de
commandes bornée (`7e0c67a`) n'a pas suffi : la cause est ailleurs.

- [ ] Reproduire, trouver la vraie cause, corriger

### 1.2 — La fenêtre devient floue 🟠

À l'agrandissement rapide, et parfois à l'ouverture d'un fichier, la fenêtre
passe par un état flou avant de redevenir nette.

> « Ce genre de petits bugs là ne doit pas exister. »

**Piste** : le moteur rend à l'ancienne taille et l'image est étirée le temps
d'une image ou deux ; ou la surface vidéo est redimensionnée avant que le
contenu ne suive.

- [ ] Pas d'état intermédiaire flou au redimensionnement ni à l'ouverture

### 1.3 — On ne distingue pas les bords de la fenêtre 🟠

La fenêtre n'a pas de cadre dessiné : impossible de voir où elle commence.

> « Lorsque j'essaie de redimensionner une des fenêtres, je n'arrive même pas
> à savoir où la fenêtre commence, parce que les bordures ne sont pas
> distinguables. Sur Ubuntu, comme mon fond d'écran est noir, les bordures ne
> se distinguent même pas du fond d'écran. Je suis obligé de passer
> l'application au thème clair avant de pouvoir la redimensionner. »

Deux cas cités : deux fenêtres d'OMNIA superposées, et une fenêtre sombre
sur un fond d'écran sombre.

**Cause** : la barre de titre du système est masquée, donc le système ne
dessine plus de bord. Rien ne l'a remplacé.

- [ ] Un bord visible, qui tienne sur fond clair comme sur fond sombre, et
      qui distingue deux fenêtres d'OMNIA l'une de l'autre

### 1.4 — La fermeture n'est pas encore assez rapide 🟡

Déjà améliorée (fermeture bornée), mais la référence est VLC.

> « Je ne veux pas une application de basse gamme, je veux une application
> qui soit une référence. »

- [ ] Mesurer, puis rapprocher le temps de fermeture de celui de VLC

---

## 2. Mobile

### 2.1 — L'arrière-plan noir de l'icône ne part pas 🔴

Les contours du téléphone sont bien devenus ambre — donc le nouveau dessin
est bien installé — **mais le fond noir reste**.

Écarté par les tests de Steve : redémarrage du téléphone, vidage du cache de
l'application, **désinstallation complète puis réinstallation**. Ce n'est
donc pas le cache du lanceur, contrairement à ce que j'avais conclu le
3 novembre. Cette conclusion était fausse.

**Pistes à vérifier** :
- Le lanceur HiOS pose peut-être sa propre plaque derrière une icône
  adaptative dont le fond est transparent.
- Vérifier le rendu hors du lanceur : Paramètres → Applications → OMNIA,
  et l'écran de partage. Si l'icône y est correcte, c'est le lanceur.
- Essayer sans icône adaptative (retirer `mipmap-anydpi-v26/ic_launcher.xml`)
  pour forcer le PNG transparent.
- Essayer une couche `<monochrome>`, ou un fond explicitement blanc plutôt
  que transparent, et voir ce que le lanceur en fait.

- [ ] L'icône n'a plus de fond noir sur l'appareil de test

### 2.2 — Les fichiers voisins manquent à l'ouverture depuis l'extérieur 🔴

En ouvrant un fichier depuis le gestionnaire de fichiers (« Ouvrir avec →
OMNIA »), le menu latéral ne montre pas les autres fichiers du même dossier.
Depuis l'application, ça fonctionne.

- [ ] Les fichiers du même dossier apparaissent aussi quand le fichier
      arrive d'une autre application

### 2.3 — Pas de défilement du document en mini-lecteur 🟠

En mini-lecteur flottant, un document ne défile toujours pas.

> « Il ne croit pas que quelqu'un peut arriver à lire le document en mode de
> mini-lecteur. À moins s'il est sur une grosse tablette. Mais il va quand
> même falloir arranger ça. »

- [ ] Le défilement fonctionne sur un document en fenêtre flottante

### 2.4 — La barre des documents ne s'efface pas 🟠

Demandé pour le mobile, où l'écran est petit et où la barre gêne le plus.
Le code a été écrit (`9f65c9d`) mais Steve ne le voit pas à l'usage : à
vérifier sur l'appareil avant de conclure.

> « Tu dois implémenter ça comme tu as fait pour le lecteur vidéo. »

- [ ] Vérifier sur l'appareil ; corriger si l'effacement ne se produit pas

---

## 3. Interconnexion

### 3.1 — Le mode « Point d'accès » refuse toujours 🔴

Le téléphone partage sa connexion, le PC y est connecté. Le bouton « Point
d'accès » répond qu'aucun point d'accès n'est actif. Le bouton « Wi-Fi
local » — pourtant faux, le téléphone n'est connecté à aucun Wi-Fi — marche
du premier coup.

> « Le problème à ce niveau, c'est juste peut-être au niveau du bouton.
> Parce que j'ai essayé la connexion, ça a pris instantanément. »

La liaison elle-même fonctionne donc : c'est la détection qui se trompe.

- [ ] Le mode « Point d'accès » reconnaît le partage de connexion du
      téléphone, ou cesse de prétendre savoir

### 3.2 — Le pare-feu : il a fallu le désactiver 🔴

Steve a dû couper le pare-feu de Windows pour que la liaison passe.

> « Si on désactive notre pare-feu, on est exposé. »

L'installateur pose désormais une règle (`c0d6d92`), mais il faut vérifier
qu'elle s'applique. Et Steve veut mieux : une **demande d'autorisation au
moment de la connexion**.

> « Si un équipement essaie de se connecter via OMNIA Connect, ça envoie une
> notification à notre machine pour dire que telle personne veut se
> connecter. Si on accepte, ça part créer une règle qui permet de projeter
> sans désactiver le pare-feu. »

- [ ] Vérifier que la règle de l'installateur suffit
- [ ] Demander l'accord à l'arrivée d'un appareil, et créer la règle alors

### 3.3 — La lecture miroir ne suit pas les petits gestes 🔴

Le défaut le plus visible du mode miroir, constaté sur vidéo **et** sur
document.

| Geste | Résultat |
|---|---|
| Avance brusque (2ᵉ → 10ᵉ minute) | suit |
| Avance lente à la molette | **ne suit pas** |
| Saut de page (1 → 30) | suit |
| Défilement lent d'un document | **ne suit pas** |
| Pause sur le mobile | **ne suit pas** |
| Volume | suit parfois |

> « J'ai l'impression que l'envoi des commandes n'est pas temps réel. […] On
> ne peut pas me dire que c'est un problème de connexion, on est sur un
> réseau local, on n'était que deux. »

**Analyse** : ce n'est pas le réseau. Les petits changements sont filtrés
avant d'être envoyés — seuil de position, anti-rebond, ou état miroir émis
seulement quand une grandeur change assez. La pause, elle, ne passe pas du
tout : c'est un changement d'état, pas de position, donc probablement un cas
oublié.

- [ ] La pause traverse la liaison
- [ ] Les petits déplacements et défilements traversent aussi
- [ ] Le volume suit systématiquement

### 3.4 — Message d'erreur intermittent en Wi-Fi 🟡

Sur un Wi-Fi partagé avec d'autres appareils, l'appairage marche parfois et
échoue parfois, avec un message. **Capture d'écran attendue de Steve.**

- [ ] Obtenir la capture, identifier le message, corriger

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

### 4.2 — Projeter sans rescanner

Aujourd'hui, changer de fichier oblige à rescanner le QR : l'appareil distant
continue d'afficher l'ancien fichier.

> « Je dois juste cliquer sur le bouton de projection. J'actualise. »

- [ ] L'onglet OMNIA Connect garde la liaison et offre un bouton
      « Actualiser la projection » qui envoie le média en cours

OMNIA Connect reste également accessible depuis les paramètres : l'onglet
est un raccourci, pas un déplacement.

### 4.3 — Transfert de fichiers

Transférer un fichier d'un appareil à l'autre, avec choix du dossier de
destination, sur n'importe lequel des trois modes de liaison.

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

- [ ] Rassembler des références visuelles (façades d'émulateurs, accueils de
      consoles) avant de dessiner quoi que ce soit
- [ ] Fond d'écran personnalisable
- [ ] Bibliothèque parcourable à vignettes, pensée pour être belle à l'arrêt
- [ ] Refonte page par page, bureau d'abord

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

## Fait

- Barre des documents qui s'efface au bout de cinq secondes, bureau et
  mobile (`28ca3b6`, `9f65c9d`) — **à revoir, voir 0.1 et 0.2**
- Halo noir autour du téléphone de l'icône (`d4d5cdf`, `be64826`) — partiel,
  voir 2.1
- Fenêtre flottante : image rendue à l'application au retour, retrait par
  n'importe quel chemin, son coupé à la fermeture, maintien avant
  déplacement, verrou lisible (`54424ad`)
- Autorisation de superposition demandée à l'ouverture (`007185d`)
- Règle de pare-feu posée par l'installateur (`c0d6d92`)
- Messages d'échec d'appairage qui nomment la vraie cause (`cffa47d`)
- Archive Linux qui ne se perd plus à la publication (`624c87c`)
- Durcissement d'OMNIA Connect : jeton 256 bits, comparaison à temps
  constant, enveloppe de protocole contre le rejeu, valeurs bornées, CORS
  retiré, en-tête Range vérifié, plafonds de charge, empreintes SHA-256
  (`ec62097`, `2502901`)
