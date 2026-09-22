/// Ratio d'aspect imposé à la vidéo.
enum AspectMode {
  /// Ratio du fichier (défaut).
  auto,

  /// 16:9.
  wide,

  /// 4:3.
  standard,

  /// Remplir l'écran en rognant (« plein »).
  fill;

  /// Valeur de la propriété mpv `video-aspect-override`.
  String get mpvAspect => switch (this) {
        AspectMode.auto => '-1',
        AspectMode.wide => '16:9',
        AspectMode.standard => '4:3',
        AspectMode.fill => '-1',
      };

  /// Valeur de `panscan` : 1 rogne pour remplir, 0 laisse des bandes.
  String get mpvPanscan => this == AspectMode.fill ? '1.0' : '0.0';

  static AspectMode fromJson(Object? value) => values.firstWhere(
        (e) => e.name == value,
        orElse: () => AspectMode.auto,
      );
}

/// Réglages d'image, sur l'échelle mpv (−100 … +100, 0 = neutre).
class VideoAdjust {
  const VideoAdjust({this.brightness = 0, this.contrast = 0, this.saturation = 0});

  static const VideoAdjust neutral = VideoAdjust();
  static const double min = -100;
  static const double max = 100;

  final double brightness;
  final double contrast;
  final double saturation;

  bool get isNeutral => brightness == 0 && contrast == 0 && saturation == 0;

  VideoAdjust copyWith({double? brightness, double? contrast, double? saturation}) =>
      VideoAdjust(
        brightness: (brightness ?? this.brightness).clamp(min, max),
        contrast: (contrast ?? this.contrast).clamp(min, max),
        saturation: (saturation ?? this.saturation).clamp(min, max),
      );

  Map<String, Object?> toJson() =>
      {'brightness': brightness, 'contrast': contrast, 'saturation': saturation};

  factory VideoAdjust.fromJson(Map<String, Object?> json) => VideoAdjust(
        brightness: ((json['brightness'] as num?)?.toDouble() ?? 0).clamp(min, max),
        contrast: ((json['contrast'] as num?)?.toDouble() ?? 0).clamp(min, max),
        saturation: ((json['saturation'] as num?)?.toDouble() ?? 0).clamp(min, max),
      );

  @override
  bool operator ==(Object other) =>
      other is VideoAdjust &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.saturation == saturation;

  @override
  int get hashCode => Object.hash(brightness, contrast, saturation);
}
