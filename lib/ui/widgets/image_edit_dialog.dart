import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/models/media_file.dart';
import '../../core/providers.dart';
import '../../core/services/image_processor.dart';
import '../theme/omnia_theme.dart';
import 'omnia_icon_button.dart';

/// Boîte de dialogue épurée et complète pour la retouche et le redimensionnement d'image.
/// Enregistre une NOUVELLE COPIE sans jamais modifier l'original, puis bascule
/// automatiquement la lecture sur cette nouvelle copie.
class ImageEditDialog extends ConsumerStatefulWidget {
  const ImageEditDialog({super.key, required this.file});

  final MediaFile file;

  static Future<void> show(BuildContext context, MediaFile file) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => ImageEditDialog(file: file),
    );
  }

  @override
  ConsumerState<ImageEditDialog> createState() => _ImageEditDialogState();
}

class _ImageEditDialogState extends ConsumerState<ImageEditDialog> {
  Size? _originalSize;
  int? _targetWidth;
  int? _targetHeight;
  bool _lockAspect = true;

  double _brightness = 0.0; // -1.0 à +1.0
  double _contrast = 1.0; // 0.0 à 2.0
  double _saturation = 1.0; // 0.0 à 2.0

  int _rotationAngle = 0; // 0, 90, 180, 270
  bool _flipHorizontal = false;
  bool _flipVertical = false;

  ImageFilterPreset _preset = ImageFilterPreset.none;

  bool _isSaving = false;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;

  @override
  void initState() {
    super.initState();
    _widthController = TextEditingController();
    _heightController = TextEditingController();
    _loadDimensions();
  }

  Future<void> _loadDimensions() async {
    final size = await ImageProcessorService.getImageDimensions(widget.file.path);
    if (mounted && size != null) {
      setState(() {
        _originalSize = size;
        _targetWidth = size.width.round();
        _targetHeight = size.height.round();
        _widthController.text = _targetWidth.toString();
        _heightController.text = _targetHeight.toString();
      });
    }
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _onWidthChanged(String val) {
    final w = int.tryParse(val);
    if (w == null || w <= 0) return;
    _targetWidth = w;
    if (_lockAspect && _originalSize != null && _originalSize!.width > 0) {
      final ratio = _originalSize!.height / _originalSize!.width;
      final h = (w * ratio).round();
      _targetHeight = h;
      _heightController.text = h.toString();
    }
    setState(() {});
  }

  void _onHeightChanged(String val) {
    final h = int.tryParse(val);
    if (h == null || h <= 0) return;
    _targetHeight = h;
    if (_lockAspect && _originalSize != null && _originalSize!.height > 0) {
      final ratio = _originalSize!.width / _originalSize!.height;
      final w = (h * ratio).round();
      _targetWidth = w;
      _widthController.text = w.toString();
    }
    setState(() {});
  }

  void _applyScalePreset(double factor) {
    if (_originalSize == null) return;
    final w = (_originalSize!.width * factor).round();
    final h = (_originalSize!.height * factor).round();
    setState(() {
      _targetWidth = w;
      _targetHeight = h;
      _widthController.text = w.toString();
      _heightController.text = h.toString();
    });
  }

  void _reset() {
    setState(() {
      if (_originalSize != null) {
        _targetWidth = _originalSize!.width.round();
        _targetHeight = _originalSize!.height.round();
        _widthController.text = _targetWidth.toString();
        _heightController.text = _targetHeight.toString();
      }
      _brightness = 0.0;
      _contrast = 1.0;
      _saturation = 1.0;
      _rotationAngle = 0;
      _flipHorizontal = false;
      _flipVertical = false;
      _preset = ImageFilterPreset.none;
    });
  }

  Future<void> _saveCopy() async {
    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final curtainColor = context.colors.curtain;

    try {
      final prefs = ref.read(preferencesProvider);
      final params = ImageEditParams(
        targetWidth: (_originalSize != null &&
                _targetWidth != null &&
                _targetWidth != _originalSize!.width.round())
            ? _targetWidth
            : null,
        targetHeight: (_originalSize != null &&
                _targetHeight != null &&
                _targetHeight != _originalSize!.height.round())
            ? _targetHeight
            : null,
        brightness: _brightness,
        contrast: _contrast,
        saturation: _saturation,
        rotationAngle: _rotationAngle,
        flipHorizontal: _flipHorizontal,
        flipVertical: _flipVertical,
        preset: _preset,
      );

      final newPath = await ImageProcessorService.processAndSaveCopy(
        sourcePath: widget.file.path,
        params: params,
        suffix: prefs.imageEditSuffix,
        jpegQuality: prefs.imageEditQuality,
      );

      if (mounted) {
        Navigator.of(context).pop();
        // Bascule immédiate de la lecture sur la NOUVELLE COPIE
        await ref.read(playbackServiceProvider).openPath(newPath);

        messenger?.showSnackBar(
          SnackBar(
            content: Text('Nouvelle copie enregistrée : ${p.basename(newPath)}'),
            duration: const Duration(seconds: 3),
            backgroundColor: curtainColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        messenger?.showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l’enregistrement de l’image : $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Dialog(
      backgroundColor: colors.velvet,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.seam),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(OmniaMetrics.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Entête
              Row(
                children: [
                  Icon(Icons.tune_rounded, color: colors.projector, size: 22),
                  const SizedBox(width: OmniaMetrics.space2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Modifier et redimensionner', style: type.bodyStrong),
                        Text(
                          _originalSize != null
                              ? '${p.basename(widget.file.path)} (${_originalSize!.width.round()} × ${_originalSize!.height.round()} px)'
                              : p.basename(widget.file.path),
                          style: type.caption.copyWith(color: colors.dust),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  OmniaIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: OmniaMetrics.space3),

              // Prévisualisation en direct
              Container(
                height: 180,
                decoration: BoxDecoration(
                  color: colors.curtain,
                  borderRadius: OmniaMetrics.controlRadius,
                  border: Border.all(color: colors.seam),
                ),
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                child: _buildLivePreview(),
              ),
              const SizedBox(height: OmniaMetrics.space3),

              // Sections de réglages avec défilement
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionTitle('Dimensions & Échelle'),
                      const SizedBox(height: OmniaMetrics.space2),
                      _buildDimensionRow(colors, type),
                      const SizedBox(height: OmniaMetrics.space3),

                      _sectionTitle('Couleurs & Retouche'),
                      const SizedBox(height: OmniaMetrics.space2),
                      _buildSlider(
                        label: 'Luminosité',
                        value: _brightness,
                        min: -1.0,
                        max: 1.0,
                        display: '${(_brightness * 100).round() > 0 ? "+" : ""}${(_brightness * 100).round()} %',
                        onChanged: (v) => setState(() => _brightness = v),
                      ),
                      _buildSlider(
                        label: 'Contraste',
                        value: _contrast,
                        min: 0.0,
                        max: 2.0,
                        display: '${(_contrast * 100).round()} %',
                        onChanged: (v) => setState(() => _contrast = v),
                      ),
                      _buildSlider(
                        label: 'Saturation',
                        value: _saturation,
                        min: 0.0,
                        max: 2.0,
                        display: '${(_saturation * 100).round()} %',
                        onChanged: (v) => setState(() => _saturation = v),
                      ),
                      const SizedBox(height: OmniaMetrics.space3),

                      _sectionTitle('Orientation & Filtres'),
                      const SizedBox(height: OmniaMetrics.space2),
                      _buildOrientationAndFilters(colors),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: OmniaMetrics.space3),
              const Divider(height: 1),
              const SizedBox(height: OmniaMetrics.space3),

              // Barre d'actions du bas
              Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: const Text('Réinitialiser'),
                    style: TextButton.styleFrom(foregroundColor: colors.dust),
                    onPressed: _reset,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Annuler', style: TextStyle(color: colors.screen)),
                  ),
                  const SizedBox(width: OmniaMetrics.space2),
                  FilledButton.icon(
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.save_as_rounded, size: 18),
                    label: Text(_isSaving ? 'Enregistrement...' : 'Enregistrer une copie'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.projector,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: _isSaving ? null : _saveCopy,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: context.type.caption.copyWith(
        color: context.colors.dust,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildLivePreview() {
    Widget imgWidget = Image.file(
      File(widget.file.path),
      fit: BoxFit.contain,
    );

    // Rotation & Miroir
    if (_flipHorizontal || _flipVertical) {
      imgWidget = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(
          _flipHorizontal ? -1.0 : 1.0,
          _flipVertical ? -1.0 : 1.0,
          1.0,
        ),
        child: imgWidget,
      );
    }

    if (_rotationAngle != 0) {
      imgWidget = RotatedBox(
        quarterTurns: (_rotationAngle ~/ 90) % 4,
        child: imgWidget,
      );
    }

    // Filtre preset
    if (_preset == ImageFilterPreset.grayscale || _saturation == 0) {
      imgWidget = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0,      0,      0,      1, 0,
        ]),
        child: imgWidget,
      );
    } else if (_preset == ImageFilterPreset.sepia) {
      imgWidget = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.393, 0.769, 0.189, 0, 0,
          0.349, 0.686, 0.168, 0, 0,
          0.272, 0.534, 0.131, 0, 0,
          0,     0,     0,     1, 0,
        ]),
        child: imgWidget,
      );
    } else if (_preset == ImageFilterPreset.invert) {
      imgWidget = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          -1,  0,  0, 0, 255,
           0, -1,  0, 0, 255,
           0,  0, -1, 0, 255,
           0,  0,  0, 1, 0,
        ]),
        child: imgWidget,
      );
    }

    // Luminosité et contraste
    if (_brightness != 0.0 || _contrast != 1.0) {
      final c = _contrast;
      final b = _brightness * 128;
      final t = (1.0 - c) / 2.0 * 255;
      imgWidget = ColorFiltered(
        colorFilter: ColorFilter.matrix([
          c, 0, 0, 0, t + b,
          0, c, 0, 0, t + b,
          0, 0, c, 0, t + b,
          0, 0, 0, 1, 0,
        ]),
        child: imgWidget,
      );
    }

    return imgWidget;
  }

  Widget _buildDimensionRow(OmniaColors colors, OmniaTypography type) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _widthController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Largeur (px)',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixText: 'px',
                ),
                onChanged: _onWidthChanged,
              ),
            ),
            IconButton(
              icon: Icon(
                _lockAspect ? Icons.link_rounded : Icons.link_off_rounded,
                color: _lockAspect ? colors.projector : colors.dust,
              ),
              tooltip: _lockAspect ? 'Conserver les proportions' : 'Proportions libres',
              onPressed: () => setState(() => _lockAspect = !_lockAspect),
            ),
            Expanded(
              child: TextField(
                controller: _heightController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Hauteur (px)',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixText: 'px',
                ),
                onChanged: _onHeightChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: OmniaMetrics.space2),
        Wrap(
          spacing: OmniaMetrics.space2,
          runSpacing: OmniaMetrics.space1,
          children: [
            for (final factor in [0.25, 0.5, 0.75, 1.0, 1.5, 2.0])
              ActionChip(
                label: Text('${(factor * 100).round()} %'),
                onPressed: () => _applyScalePreset(factor),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 85,
            child: Text(label, style: context.type.caption),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              activeColor: context.colors.projector,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              display,
              style: context.type.timecode.copyWith(fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrientationAndFilters(OmniaColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.rotate_right_rounded, size: 18),
              label: Text('$_rotationAngle°'),
              onPressed: () {
                setState(() => _rotationAngle = (_rotationAngle + 90) % 360);
              },
            ),
            const SizedBox(width: OmniaMetrics.space2),
            IconButton.outlined(
              icon: Icon(
                Icons.flip_rounded,
                color: _flipHorizontal ? colors.projector : colors.screen,
              ),
              tooltip: 'Miroir horizontal',
              onPressed: () => setState(() => _flipHorizontal = !_flipHorizontal),
            ),
            const SizedBox(width: OmniaMetrics.space2),
            IconButton.outlined(
              icon: Transform.rotate(
                angle: math.pi / 2,
                child: Icon(
                  Icons.flip_rounded,
                  color: _flipVertical ? colors.projector : colors.screen,
                ),
              ),
              tooltip: 'Miroir vertical',
              onPressed: () => setState(() => _flipVertical = !_flipVertical),
            ),
          ],
        ),
        const SizedBox(height: OmniaMetrics.space2),
        Wrap(
          spacing: OmniaMetrics.space2,
          children: [
            FilterChip(
              label: const Text('Normal'),
              selected: _preset == ImageFilterPreset.none,
              onSelected: (_) => setState(() => _preset = ImageFilterPreset.none),
            ),
            FilterChip(
              label: const Text('Noir & Blanc'),
              selected: _preset == ImageFilterPreset.grayscale,
              onSelected: (_) => setState(() => _preset = ImageFilterPreset.grayscale),
            ),
            FilterChip(
              label: const Text('Sépia'),
              selected: _preset == ImageFilterPreset.sepia,
              onSelected: (_) => setState(() => _preset = ImageFilterPreset.sepia),
            ),
            FilterChip(
              label: const Text('Négatif'),
              selected: _preset == ImageFilterPreset.invert,
              onSelected: (_) => setState(() => _preset = ImageFilterPreset.invert),
            ),
          ],
        ),
      ],
    );
  }
}
