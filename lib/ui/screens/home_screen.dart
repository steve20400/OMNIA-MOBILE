import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/history_entry.dart';
import '../../core/models/media_type.dart';
import '../../core/models/playback_state.dart';
import '../../core/models/playback_status.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../file_dialogs.dart';
import '../settings/settings_screen.dart';
import '../theme/omnia_theme.dart';
import '../widgets/omnia_button.dart';
import '../widgets/omnia_icon_button.dart';
import 'player_screen.dart';

/// Écran d'accueil de la bibliothèque OMNIA Mobile.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  MediaType? _selectedFilter;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);
    final playback = ref.watch(playbackStateProvider);
    final history = ref.watch(historyStoreProvider);
    final recentEntries = history.recent(limit: 50);

    final filteredEntries = _selectedFilter == null
        ? recentEntries
        : recentEntries.where((e) {
            final type = MediaType.fromJson(e.path.split('.').last.toLowerCase());
            return type == _selectedFilter;
          }).toList();

    return Scaffold(
      backgroundColor: colors.velvet,
      appBar: AppBar(
        backgroundColor: colors.curtain,
        elevation: 0,
        title: Row(
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
            const SizedBox(width: 12),
            Text(
              'OMNIA',
              style: TextStyle(
                fontFamily: OmniaFonts.ui,
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: colors.screen,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          OmniaIconButton(
            icon: Icons.settings_rounded,
            tooltip: l10n.settingsTitle,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsOverlay(),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Filtres par catégorie
          _buildFilterBar(colors, l10n),
          // Liste des récents ou vue vide
          Expanded(
            child: filteredEntries.isEmpty
                ? _buildEmptyState(colors, l10n)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: filteredEntries.length,
                    separatorBuilder: (_, __) => Divider(color: colors.seam, height: 1),
                    itemBuilder: (context, index) {
                      final item = filteredEntries[index];
                      return _buildRecentTile(item, colors, l10n);
                    },
                  ),
          ),
          // Mini-lecteur inférieur si média en cours
          if (playback.hasFile && playback.status != PlaybackStatus.idle)
            _buildBottomMiniPlayer(playback, colors, l10n),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colors.projector,
        foregroundColor: colors.velvet,
        icon: const Icon(Icons.file_open_rounded),
        label: Text(
          l10n.openFile,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        onPressed: _openFilePicker,
      ),
    );
  }

  Widget _buildFilterBar(OmniaColors colors, AppLocalizations l10n) {
    final isFr = l10n.localeName.startsWith('fr');
    final filters = <(MediaType?, String, IconData)>[
      (null, isFr ? 'Tous' : 'All', Icons.dashboard_rounded),
      (MediaType.video, isFr ? 'Vidéos' : 'Videos', Icons.movie_rounded),
      (MediaType.audio, isFr ? 'Audios' : 'Audio', Icons.music_note_rounded),
      (MediaType.pdf, isFr ? 'Documents' : 'Documents', Icons.description_rounded),
      (MediaType.image, isFr ? 'Images' : 'Images', Icons.image_rounded),
    ];

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: colors.curtain.withValues(alpha: 0.5),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (type, label, icon) = filters[index];
          final isSelected = _selectedFilter == type;
          return FilterChip(
            selected: isSelected,
            showCheckmark: false,
            avatar: Icon(
              icon,
              size: 16,
              color: isSelected ? colors.velvet : colors.dust,
            ),
            label: Text(
              label,
              style: TextStyle(
                fontFamily: OmniaFonts.ui,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? colors.velvet : colors.screen,
              ),
            ),
            backgroundColor: colors.velvet,
            selectedColor: colors.projector,
            side: BorderSide(
              color: isSelected ? colors.projector : colors.seam,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            onSelected: (_) {
              setState(() {
                _selectedFilter = type;
              });
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(OmniaColors colors, AppLocalizations l10n) {
    final isFr = l10n.localeName.startsWith('fr');
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open_rounded, size: 64, color: colors.dust.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            l10n.noRecentFiles,
            style: TextStyle(
              fontFamily: OmniaFonts.ui,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colors.screen,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isFr
                ? 'Vos médias et documents récemment ouverts apparaîtront ici.'
                : 'Your recently opened media and documents will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: OmniaFonts.ui,
              fontSize: 13,
              color: colors.dust,
            ),
          ),
          const SizedBox(height: 24),
          OmniaButton(
            label: l10n.openFile,
            icon: Icons.file_open_rounded,
            onPressed: _openFilePicker,
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTile(HistoryEntry item, OmniaColors colors, AppLocalizations l10n) {
    final fileName = item.path.split('/').last.split(r'\').last;
    final isCompleted = item.completed;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colors.curtain,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.seam),
        ),
        child: Icon(
          Icons.play_circle_fill_rounded,
          color: colors.projector,
          size: 24,
        ),
      ),
      title: Text(
        fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: OmniaFonts.ui,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colors.screen,
        ),
      ),
      subtitle: Row(
        children: [
          if (item.page > 0)
            Text(
              'Page ${item.page}',
              style: TextStyle(fontFamily: OmniaFonts.ui, fontSize: 12, color: colors.dust),
            )
          else if (item.position > Duration.zero)
            Text(
              '${(item.position.inSeconds / 60).floor()}:${(item.position.inSeconds % 60).toString().padLeft(2, '0')}',
              style: TextStyle(fontFamily: OmniaFonts.mono, fontSize: 12, color: colors.dust),
            ),
          if (isCompleted) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: colors.projector.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Vu',
                style: TextStyle(fontSize: 10, color: colors.projector, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: colors.dust),
      onTap: () {
        ref.dispatch(OpenFile(item.path));
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const PlayerScreen(),
          ),
        );
      },
    );
  }

  Widget _buildBottomMiniPlayer(PlaybackState state, OmniaColors colors, AppLocalizations l10n) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const PlayerScreen(),
          ),
        );
      },
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: colors.curtain,
          border: Border(top: BorderSide(color: colors.seam)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.motion_photos_on_rounded, color: colors.projector, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.file?.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: OmniaFonts.ui,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: colors.screen,
                    ),
                  ),
                  Text(
                    state.status == PlaybackStatus.playing ? 'En cours de lecture' : 'En pause',
                    style: TextStyle(
                      fontFamily: OmniaFonts.ui,
                      fontSize: 11,
                      color: colors.dust,
                    ),
                  ),
                ],
              ),
            ),
            OmniaIconButton(
              icon: state.status == PlaybackStatus.playing
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              onPressed: () {
                ref.dispatch(const TogglePlay());
              },
            ),
            OmniaIconButton(
              icon: Icons.close_rounded,
              onPressed: () {
                ref.dispatch(const Stop());
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFilePicker() async {
    await pickAndOpenFile(ref);
  }
}
