import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Les quatre onglets du bas de l'accueil.
enum HomeSection { home, folders, connect, settings }

/// Onglet affiché. Gardé hors de l'écran : fermer un média ramène sur
/// l'onglet qu'on avait quitté, et non toujours sur l'accueil.
final homeSectionProvider =
    NotifierProvider<HomeSectionController, HomeSection>(HomeSectionController.new);

class HomeSectionController extends Notifier<HomeSection> {
  @override
  HomeSection build() => HomeSection.home;

  void show(HomeSection section) => state = section;
}

/// Dossier montré par l'onglet Dossiers ; `null` pour la liste des
/// stockages du téléphone.
final folderLocationProvider =
    NotifierProvider<FolderLocationController, String?>(FolderLocationController.new);

class FolderLocationController extends Notifier<String?> {
  @override
  String? build() => null;

  void open(String? path) => state = path;
}

/// Ouvre l'onglet Dossiers sur [folder] : c'est « l'emplacement » d'un
/// fichier, qu'on parcourt au lieu de lire un chemin.
void revealFolder(WidgetRef ref, String folder) {
  ref.read(folderLocationProvider.notifier).open(folder);
  ref.read(homeSectionProvider.notifier).show(HomeSection.folders);
}
