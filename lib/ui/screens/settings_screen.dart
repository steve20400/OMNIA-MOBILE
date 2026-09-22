import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/app_preferences.dart';
import '../../core/providers.dart';
import '../l10n/app_localizations.dart';
import '../theme/omnia_theme.dart';
import '../widgets/omnia_icon_button.dart';

/// Écran des paramètres d'OMNIA Mobile.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context)!;
    final prefs = ref.watch(preferencesProvider);

    return Scaffold(
      backgroundColor: colors.velvet,
      appBar: AppBar(
        backgroundColor: colors.curtain,
        elevation: 0,
        leading: OmniaIconButton(
          icon: Icons.arrow_back_rounded,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.settingsTitle,
          style: TextStyle(
            fontFamily: OmniaFonts.ui,
            fontWeight: FontWeight.bold,
            color: colors.screen,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildSectionHeader('Général & Écran', colors),
          _buildSwitchTile(
            title: 'Reprendre la lecture là où elle a été interrompue',
            subtitle: 'Sauvegarde continue des positions vidéos et des pages de documents',
            value: prefs.rememberPlaybackState,
            colors: colors,
            onChanged: (val) {
              ref.dispatch(UpdatePreferences(preferences: {'rememberPlaybackState': val}));
            },
          ),
          _buildSwitchTile(
            title: 'Maintenir l\'écran actif pendant la lecture',
            subtitle: 'Empêche le verrouillage automatique de l\'écran',
            value: prefs.normalPlayerAlwaysOnTop,
            colors: colors,
            onChanged: (val) {
              ref.dispatch(UpdatePreferences(preferences: {'normalPlayerAlwaysOnTop': val}));
            },
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('Documents & Édition', colors),
          _buildSwitchTile(
            title: 'Sauvegarde automatique des documents',
            subtitle: 'Enregistre les modifications de texte sans risque de perte',
            value: prefs.docAutoSave,
            colors: colors,
            onChanged: (val) {
              ref.dispatch(UpdatePreferences(preferences: {'docAutoSave': val}));
            },
          ),
          _buildSwitchTile(
            title: 'Mode sombre de lecture pour documents',
            subtitle: 'Inversion douce du contraste pour la lecture nocturne',
            value: prefs.readingDark,
            colors: colors,
            onChanged: (val) {
              ref.dispatch(UpdatePreferences(preferences: {'readingDark': val}));
            },
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('Retouche d\'Images', colors),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Qualité d\'export JPEG (${prefs.imageEditQuality} %)',
              style: TextStyle(fontFamily: OmniaFonts.ui, color: colors.screen, fontSize: 14),
            ),
            subtitle: Slider(
              value: prefs.imageEditQuality.toDouble(),
              min: 50,
              max: 100,
              divisions: 10,
              activeColor: colors.projector,
              inactiveColor: colors.seam,
              onChanged: (val) {
                ref.dispatch(UpdatePreferences(preferences: {'imageEditQuality': val.round()}));
              },
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('À Propos d\'OMNIA Mobile', colors),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.curtain,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.seam),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OMNIA Mobile v0.1.0',
                  style: TextStyle(
                    fontFamily: OmniaFonts.ui,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: colors.projector,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Lecteur universel haute performance et suite d\'édition multimédia.',
                  style: TextStyle(
                    fontFamily: OmniaFonts.ui,
                    fontSize: 12,
                    color: colors.dust,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Copyright © 2026 STEVE AUREL MANFO. Tous droits réservés.',
                  style: TextStyle(
                    fontFamily: OmniaFonts.ui,
                    fontSize: 11,
                    color: colors.dust.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, OmniaColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: OmniaFonts.ui,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: colors.projector,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required OmniaColors colors,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: TextStyle(fontFamily: OmniaFonts.ui, color: colors.screen, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontFamily: OmniaFonts.ui, color: colors.dust, fontSize: 12),
      ),
      value: value,
      activeColor: colors.projector,
      onChanged: onChanged,
    );
  }
}
