import 'package:flutter/material.dart';

/// Familles de polices embarquées (voir `pubspec.yaml` et DESIGN.md).
abstract final class OmniaFonts {
  /// Interface : Instrument Sans (variable).
  static const ui = 'InstrumentSans';

  /// Timecodes et compteurs : IBM Plex Mono.
  static const mono = 'IBMPlexMono';
}

/// Rôles typographiques d'OMNIA.
///
/// Les couleurs sont injectées par le thème ; ici, seules les formes.
@immutable
class OmniaTypography extends ThemeExtension<OmniaTypography> {
  const OmniaTypography({
    required this.caption,
    required this.secondary,
    required this.body,
    required this.bodyStrong,
    required this.sectionTitle,
    required this.viewTitle,
    required this.heroTitle,
    required this.wordmark,
    required this.timecode,
    required this.timecodeLarge,
    required this.shortcut,
    required this.osdValue,
    required this.osdLabel,
  });

  final TextStyle caption;
  final TextStyle secondary;
  final TextStyle body;
  final TextStyle bodyStrong;
  final TextStyle sectionTitle;
  final TextStyle viewTitle;
  final TextStyle heroTitle;

  /// Le mot « OMNIA » tel qu'il apparaît dans la barre de titre.
  final TextStyle wordmark;

  /// Timecodes, compteurs, vitesse.
  final TextStyle timecode;
  final TextStyle timecodeLarge;

  /// Étiquettes de raccourcis (`Ctrl+O`).
  final TextStyle shortcut;

  /// OSD : la valeur (« +5 s », « 65 », « 1.25× ») en mono, et son libellé.
  final TextStyle osdValue;
  final TextStyle osdLabel;

  factory OmniaTypography.standard({required Color primary, required Color muted}) {
    const ui = OmniaFonts.ui;
    const mono = OmniaFonts.mono;
    return OmniaTypography(
      caption: TextStyle(fontFamily: ui, fontSize: 11, height: 1.3, color: muted, letterSpacing: 0.2),
      secondary: TextStyle(fontFamily: ui, fontSize: 12.5, height: 1.35, color: muted),
      body: TextStyle(fontFamily: ui, fontSize: 14, height: 1.4, color: primary),
      bodyStrong: TextStyle(fontFamily: ui, fontSize: 14, height: 1.4, color: primary, fontWeight: FontWeight.w600),
      sectionTitle: TextStyle(fontFamily: ui, fontSize: 16, height: 1.3, color: primary, fontWeight: FontWeight.w600),
      viewTitle: TextStyle(fontFamily: ui, fontSize: 22, height: 1.25, color: primary, fontWeight: FontWeight.w600, letterSpacing: -0.2),
      heroTitle: TextStyle(fontFamily: ui, fontSize: 32, height: 1.2, color: primary, fontWeight: FontWeight.w600, letterSpacing: -0.5),
      wordmark: TextStyle(fontFamily: ui, fontSize: 12, height: 1, color: muted, fontWeight: FontWeight.w700, letterSpacing: 4),
      timecode: TextStyle(fontFamily: mono, fontSize: 12.5, height: 1, color: primary, fontWeight: FontWeight.w500, letterSpacing: 0.4, fontFeatures: const [FontFeature.tabularFigures()]),
      timecodeLarge: TextStyle(fontFamily: mono, fontSize: 18, height: 1, color: primary, fontWeight: FontWeight.w500, letterSpacing: 0.6, fontFeatures: const [FontFeature.tabularFigures()]),
      shortcut: TextStyle(fontFamily: mono, fontSize: 11, height: 1, color: muted, fontWeight: FontWeight.w500, letterSpacing: 0.3),
      osdValue: TextStyle(fontFamily: mono, fontSize: 15, height: 1, color: primary, fontWeight: FontWeight.w600, letterSpacing: 0.4, fontFeatures: const [FontFeature.tabularFigures()]),
      osdLabel: TextStyle(fontFamily: ui, fontSize: 14, height: 1, color: primary, fontWeight: FontWeight.w500),
    );
  }

  @override
  OmniaTypography copyWith({
    TextStyle? caption,
    TextStyle? secondary,
    TextStyle? body,
    TextStyle? bodyStrong,
    TextStyle? sectionTitle,
    TextStyle? viewTitle,
    TextStyle? heroTitle,
    TextStyle? wordmark,
    TextStyle? timecode,
    TextStyle? timecodeLarge,
    TextStyle? shortcut,
    TextStyle? osdValue,
    TextStyle? osdLabel,
  }) {
    return OmniaTypography(
      caption: caption ?? this.caption,
      secondary: secondary ?? this.secondary,
      body: body ?? this.body,
      bodyStrong: bodyStrong ?? this.bodyStrong,
      sectionTitle: sectionTitle ?? this.sectionTitle,
      viewTitle: viewTitle ?? this.viewTitle,
      heroTitle: heroTitle ?? this.heroTitle,
      wordmark: wordmark ?? this.wordmark,
      timecode: timecode ?? this.timecode,
      timecodeLarge: timecodeLarge ?? this.timecodeLarge,
      shortcut: shortcut ?? this.shortcut,
      osdValue: osdValue ?? this.osdValue,
      osdLabel: osdLabel ?? this.osdLabel,
    );
  }

  @override
  OmniaTypography lerp(ThemeExtension<OmniaTypography>? other, double t) {
    if (other is! OmniaTypography) return this;
    return OmniaTypography(
      caption: TextStyle.lerp(caption, other.caption, t)!,
      secondary: TextStyle.lerp(secondary, other.secondary, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      bodyStrong: TextStyle.lerp(bodyStrong, other.bodyStrong, t)!,
      sectionTitle: TextStyle.lerp(sectionTitle, other.sectionTitle, t)!,
      viewTitle: TextStyle.lerp(viewTitle, other.viewTitle, t)!,
      heroTitle: TextStyle.lerp(heroTitle, other.heroTitle, t)!,
      wordmark: TextStyle.lerp(wordmark, other.wordmark, t)!,
      timecode: TextStyle.lerp(timecode, other.timecode, t)!,
      timecodeLarge: TextStyle.lerp(timecodeLarge, other.timecodeLarge, t)!,
      shortcut: TextStyle.lerp(shortcut, other.shortcut, t)!,
      osdValue: TextStyle.lerp(osdValue, other.osdValue, t)!,
      osdLabel: TextStyle.lerp(osdLabel, other.osdLabel, t)!,
    );
  }
}
