# OMNIA Mobile

**OMNIA Mobile** est la suite multimédia et de lecture universelle haute performance pour Android et iOS, conçue pour offrir une expérience fluide, rapide et moderne sans compromis.

Propriété intellectuelle exclusive de **STEVE AUREL MANFO**. Tous droits réservés.

---

## Fonctionnalités Principales

### 1. Moteur Multimédia Universel & Accélération Matérielle
- **Vidéos & Audios Hi-Res** : Décodage matériel GPU natif sans latence (MediaCodec sur Android, VideoToolbox/Metal sur iOS via libmpv).
- **Rendu sans saccade** : Fluidité native 60 / 120 Hz, défilement et scrubbing temporel instantanés.
- **Picture-in-Picture (PiP)** : Fenêtre flottante native au-dessus de toutes les applications mobiles.
- **Écoute en arrière-plan** : Poursuite de la lecture audio avec l'écran verrouillé.

### 2. Documents & Bureautique (PDF, Word, Textes, Code)
- **Rendu vectoriel tuilé PDFium** : Zoom net sans pixellisation, absence de pages blanches lors de défilements rapides.
- **Adaptation automatique à la largeur** : Ajustement réactif de la largeur du document en mode portrait comme en mode paysage.
- **Édition intégrée & Sauvegarde automatique** : Modification directe des fichiers texte et code sur l'appareil avec sauvegarde automatique intelligente pour prévenir toute perte de données en cas d'interruption système.

### 3. Studio de Retouche d'Images Non-Destructif
- **Traitement déporté sur Isolates Dart** : Redimensionnement, ajustements colorimétriques (luminosité, contraste, saturation), rotation et filtres sans bloquer l'interface utilisateur.
- **Sauvegarde non-destructive** : Génération d'une nouvelle copie propre sans jamais altérer l'image originale de la galerie.

### 4. Ergonomie & Contrôles Tactiles
- Glissement vertical gauche : Luminosité de l'écran avec retour visuel immédiat.
- Glissement vertical droit : Volume sonore précis.
- Double-tap gauche / droit : Avance / retour rapide de ±10 secondes.
- Mini-lecteur rétractable en bas d'écran avec tiroir contextuel de liste de lecture.

### 5. Écosystème Zéro-Internet (OMNIA Connect - Phase 3)
- Synchronisation locale pair-à-pair directe via Wi-Fi ou point d'accès mobile.
- Appairage instantané sécurisé par **QR Code** bidirectionnel.
- Projection de lecture et contrôle à distance entre le Mobile et le Desktop sans aucune connexion Internet.

---

## Structure du Projet

```
omnia_mobile/
├── assets/
│   ├── fonts/           # Polices typographiques officielles (Instrument Sans, IBM Plex Mono)
│   └── icons/           # Icônes officielles d'OMNIA (toutes résolutions)
├── lib/
│   ├── core/
│   │   ├── commands/    # Bus de commandes réactif et types de commandes
│   │   ├── controllers/ # Contrôleurs matériels (AV, PDF, Texte, Image)
│   │   ├── models/      # Modèles immuables d'état, historique et préférences
│   │   ├── providers.dart # Câblage Riverpod réactif
│   │   └── services/    # Services de persistance (Hive), isolates et cycle de vie
│   ├── l10n/            # Internationalisation complète (Français / Anglais)
│   ├── ui/
│   │   ├── osd/         # Système de notifications à l'écran (OSD)
│   │   ├── screens/     # Écrans principaux (Accueil, Lecteur tactile, Paramètres)
│   │   ├── theme/       # Système de design officiel OMNIA (Velvet, Curtain, Projector, Screen)
│   │   └── widgets/     # Composants d'interface (Barres d'outils, curseurs, dialogues)
│   └── main.dart        # Point d'entrée de l'application
├── test/                # Suite de tests unitaires et d'intégration
└── pubspec.yaml         # Dépendances et configuration Flutter
```

---

## Licence

Copyright © 2026 **STEVE AUREL MANFO**. Tous droits réservés.
Toute reproduction, diffusion ou exploitation commerciale sans autorisation écrite préalable est strictement interdite. Voir le fichier `LICENSE` pour plus de détails.
