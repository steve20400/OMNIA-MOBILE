import 'package:flutter/material.dart';

import 'omnia_colors.dart';
import 'omnia_metrics.dart';
import 'omnia_typography.dart';

export 'omnia_colors.dart';
export 'omnia_metrics.dart';
export 'omnia_motion.dart';
export 'omnia_typography.dart';

/// Construit le [ThemeData] d'OMNIA pour une luminosité donnée.
///
/// Le thème Material n'est qu'un support : les composants Flutter bruts ne sont
/// jamais utilisés tels quels, et les ondulations (ripples) sont désactivées.
ThemeData buildOmniaTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark ? OmniaColors.dark : OmniaColors.light;
  final typography = OmniaTypography.standard(primary: colors.screen, muted: colors.dust);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: colors.projector,
    onPrimary: colors.velvet,
    secondary: colors.ember,
    onSecondary: colors.velvet,
    error: colors.alert,
    onError: colors.screen,
    surface: colors.velvet,
    onSurface: colors.screen,
    surfaceContainerHighest: colors.curtain,
    outline: colors.seam,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: OmniaFonts.ui,
    scaffoldBackgroundColor: colors.velvet,
    canvasColor: colors.velvet,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: colors.hover,
    focusColor: colors.projector.withValues(alpha: 0.25),
    dividerColor: colors.seam,
    iconTheme: IconThemeData(color: colors.dust, size: OmniaMetrics.iconSize),
    textTheme: TextTheme(
      bodySmall: typography.caption,
      bodyMedium: typography.body,
      bodyLarge: typography.bodyStrong,
      titleSmall: typography.secondary,
      titleMedium: typography.sectionTitle,
      titleLarge: typography.viewTitle,
      headlineMedium: typography.heroTitle,
      labelSmall: typography.shortcut,
      labelMedium: typography.timecode,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: colors.curtain,
        borderRadius: const BorderRadius.all(Radius.circular(OmniaMetrics.radiusSmall)),
        border: Border.all(color: colors.seam),
      ),
      textStyle: typography.secondary.copyWith(color: colors.screen),
      padding: const EdgeInsets.symmetric(
        horizontal: OmniaMetrics.space3,
        vertical: OmniaMetrics.space2,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.projector,
      linearTrackColor: colors.seam,
      circularTrackColor: colors.seam,
    ),
    // Menus MenuAnchor (contextuel, récents) : mêmes surfaces que les popups.
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.curtain),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(
          Colors.black.withValues(alpha: OmniaMetrics.overlayShadowAlpha),
        ),
        elevation: const WidgetStatePropertyAll(8),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: OmniaMetrics.space1),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: OmniaMetrics.controlRadius,
            side: BorderSide(color: colors.seam),
          ),
        ),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(
          Size(OmniaMetrics.menuMinWidth, OmniaMetrics.menuItemHeight),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: OmniaMetrics.space3),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
              ? colors.hover
              : Colors.transparent,
        ),
        foregroundColor: WidgetStatePropertyAll(colors.screen),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
        textStyle: WidgetStatePropertyAll(typography.body),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.curtain,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: OmniaMetrics.overlayShadowAlpha),
      textStyle: typography.body,
      shape: RoundedRectangleBorder(
        borderRadius: OmniaMetrics.controlRadius,
        side: BorderSide(color: colors.seam),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: OmniaMetrics.space1),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? colors.dust
            : colors.seam,
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.projector,
      selectionColor: colors.projector.withValues(alpha: 0.3),
      selectionHandleColor: colors.projector,
    ),
    extensions: [colors, typography],
  );
}

/// Accès direct aux jetons de design depuis n'importe quel widget.
extension OmniaThemeX on BuildContext {
  OmniaColors get colors => Theme.of(this).extension<OmniaColors>()!;
  OmniaTypography get type => Theme.of(this).extension<OmniaTypography>()!;
}
