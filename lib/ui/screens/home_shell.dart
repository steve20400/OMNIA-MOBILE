import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/providers.dart';
import '../../core/services/mobile_window_service.dart';
import '../home_navigation.dart';
import '../settings/settings_screen.dart';
import '../theme/omnia_theme.dart';
import '../widgets/home_menu_button.dart';
import '../widgets/omnia_connect_modal.dart';
import '../widgets/overlay_permission_dialog.dart';
import 'folders_tab.dart';
import 'home_screen.dart';

/// L'accueil d'OMNIA Mobile : quatre onglets en bas, comme dans toute
/// application mobile d'aujourd'hui — Accueil, Dossiers, OMNIA Connect,
/// Paramètres.
///
/// Il occupe l'écran tant qu'aucun média n'est ouvert ; le lecteur prend sa
/// place dès qu'un fichier s'ouvre, d'où qu'il vienne, et le rend à sa
/// fermeture, sur l'onglet qu'on avait quitté.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  /// Onglets déjà ouverts une fois.
  ///
  /// Un onglet n'est construit qu'à sa première visite. C'est voulu pour
  /// OMNIA Connect surtout : le construire démarre le serveur d'appairage, et
  /// celui-ci ne doit pas tourner à l'insu de l'utilisateur dès le lancement.
  final Set<HomeSection> _built = {HomeSection.home};

  @override
  void initState() {
    super.initState();
    // Après la première image : montrer une boîte pendant la construction
    // de l'écran reviendrait à demander à Flutter de dessiner deux choses à
    // la fois.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_askOverlayOnce());
    });
  }

  /// Demande l'autorisation du mini-lecteur flottant, une seule fois.
  ///
  /// Elle ne concerne que les appareils dépourvus d'image dans l'image : chez
  /// les autres, le mini-lecteur est celui du système et n'a besoin de rien.
  /// Cette demande vivait dans l'ancien écran d'accueil — qui n'était affiché
  /// nulle part : elle ne s'était donc jamais déclenchée.
  Future<void> _askOverlayOnce() async {
    // Une autorisation d'Android : elle n'existe nulle part ailleurs.
    if (!Platform.isAndroid) return;
    if (ref.read(preferencesProvider).overlayPromptDone) return;
    final window = ref.read(windowServiceProvider);
    if (window is! MobileWindowService) return;
    final caps = await window.windowCapabilities();
    if (caps.pip || caps.overlay) return;
    if (!mounted) return;

    // Le choix est retenu avant d'ouvrir les réglages : partir vers une page
    // du système suspend l'écran, et la question reviendrait au retour.
    final prefs = ref.read(preferencesProvider);
    ref.read(commandBusProvider).dispatch(
          UpdatePreferences.between(
            prefs,
            prefs.copyWith(overlayPromptDone: true),
          ),
        );
    await askOverlayPermission(context, window);
  }

  Widget _page(HomeSection section) => switch (section) {
        HomeSection.home => const HomeTab(),
        HomeSection.folders => const FoldersTab(),
        HomeSection.connect => const OmniaConnectModal(embedded: true),
        HomeSection.settings => const SettingsOverlay(standalone: false),
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final section = ref.watch(homeSectionProvider);
    _built.add(section);

    return Scaffold(
      backgroundColor: colors.velvet,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _ShellTopBar(section: section),
            Expanded(
              child: IndexedStack(
                index: section.index,
                sizing: StackFit.expand,
                children: [
                  for (final s in HomeSection.values)
                    _built.contains(s) ? _page(s) : const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _ShellNavigation(section: section),
    );
  }
}

class _ShellTopBar extends StatelessWidget {
  const _ShellTopBar({required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final title = switch (section) {
      HomeSection.home => 'OMNIA',
      HomeSection.folders => 'Dossiers',
      HomeSection.connect => 'OMNIA Connect',
      HomeSection.settings => 'Paramètres',
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(
        OmniaMetrics.space4,
        OmniaMetrics.space2,
        OmniaMetrics.space1,
        OmniaMetrics.space2,
      ),
      decoration: BoxDecoration(
        color: colors.curtain,
        border: Border(bottom: BorderSide(color: colors.seam)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colors.projector,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                'O',
                style: TextStyle(
                  fontFamily: OmniaFonts.ui,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: colors.velvet,
                ),
              ),
            ),
          ),
          const SizedBox(width: OmniaMetrics.space3),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: type.bodyStrong.copyWith(
                color: colors.screen,
                fontSize: 18,
                letterSpacing: section == HomeSection.home ? 2 : 0.2,
              ),
            ),
          ),
          const HomeMenuButton(),
        ],
      ),
    );
  }
}

class _ShellNavigation extends ConsumerWidget {
  const _ShellNavigation({required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.seam)),
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: colors.curtain,
          indicatorColor: colors.projector.withValues(alpha: 0.18),
          height: 64,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontFamily: OmniaFonts.ui,
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected) ? colors.projector : colors.dust,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              size: 24,
              color: states.contains(WidgetState.selected) ? colors.projector : colors.dust,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: section.index,
          onDestinationSelected: (index) =>
              ref.read(homeSectionProvider.notifier).show(HomeSection.values[index]),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Accueil',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder_rounded),
              label: 'Dossiers',
            ),
            NavigationDestination(
              icon: Icon(Icons.wifi_tethering_rounded),
              label: 'Connect',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Paramètres',
            ),
          ],
        ),
      ),
    );
  }
}
