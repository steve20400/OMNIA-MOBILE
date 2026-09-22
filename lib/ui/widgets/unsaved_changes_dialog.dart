import 'package:flutter/material.dart';

import '../theme/omnia_theme.dart';

/// Choix possible lors de la fermeture avec des modifications non enregistrées.
enum UnsavedChangesAction {
  /// Enregistrer les modifications sur le disque puis fermer.
  save,

  /// Ignorer les modifications et fermer immédiatement.
  discard,

  /// Annuler la fermeture et rester dans l'application.
  cancel,
}

/// Boîte de dialogue de confirmation élégante affichée lorsque l'utilisateur
/// tente de fermer l'application alors qu'un document est en cours d'édition.
class UnsavedChangesDialog extends StatelessWidget {
  const UnsavedChangesDialog({super.key, required this.fileName});

  final String fileName;

  static Future<UnsavedChangesAction?> show(
    BuildContext context, {
    required String fileName,
  }) {
    return showDialog<UnsavedChangesAction>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (_) => UnsavedChangesDialog(fileName: fileName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 480 || size.height < 360;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: isCompact ? size.width * 0.92 : 460,
            maxHeight: size.height * 0.9,
          ),
          margin: EdgeInsets.symmetric(
            horizontal: isCompact ? OmniaMetrics.space2 : OmniaMetrics.space4,
          ),
          decoration: BoxDecoration(
            color: colors.curtain,
            borderRadius: BorderRadius.circular(OmniaMetrics.radiusLarge),
            border: Border.all(color: colors.seam),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: EdgeInsets.all(isCompact ? OmniaMetrics.space3 : OmniaMetrics.space5),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: isCompact ? 30 : 36,
                      height: isCompact ? 30 : 36,
                      decoration: BoxDecoration(
                        color: colors.projector.withValues(alpha: 0.15),
                        borderRadius: OmniaMetrics.controlRadius,
                      ),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: colors.projector,
                        size: isCompact ? 18 : 22,
                      ),
                    ),
                    const SizedBox(width: OmniaMetrics.space3),
                    Expanded(
                      child: Text(
                        'Enregistrer les modifications ?',
                        style: isCompact
                            ? type.bodyStrong.copyWith(fontSize: 14)
                            : type.sectionTitle,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isCompact ? OmniaMetrics.space2 : OmniaMetrics.space3),
                Text(
                  'Le document « $fileName » contient des modifications non enregistrées. '
                  'Voulez-vous les enregistrer avant de quitter l’application ?',
                  style: (isCompact ? type.caption : type.body).copyWith(
                    color: colors.screen.withValues(alpha: 0.85),
                    height: 1.4,
                  ),
                ),
                SizedBox(height: isCompact ? OmniaMetrics.space3 : OmniaMetrics.space5),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: OmniaMetrics.space2,
                    runSpacing: OmniaMetrics.space2,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(UnsavedChangesAction.cancel),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.screen.withValues(alpha: 0.7),
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 10 : 14,
                            vertical: isCompact ? 6 : 10,
                          ),
                        ),
                        child: const Text('Annuler'),
                      ),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(UnsavedChangesAction.discard),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade300,
                          side: BorderSide(color: Colors.red.shade900.withValues(alpha: 0.6)),
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 10 : 14,
                            vertical: isCompact ? 6 : 10,
                          ),
                          shape: const RoundedRectangleBorder(borderRadius: OmniaMetrics.controlRadius),
                        ),
                        child: const Text('Ne pas enregistrer'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(UnsavedChangesAction.save),
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.projector,
                          foregroundColor: colors.velvet,
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 12 : 16,
                            vertical: isCompact ? 6 : 10,
                          ),
                          shape: const RoundedRectangleBorder(borderRadius: OmniaMetrics.controlRadius),
                        ),
                        child: const Text(
                          'Enregistrer',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
