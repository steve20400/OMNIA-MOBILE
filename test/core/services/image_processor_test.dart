import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/services/image_processor.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ImageProcessorService', () {
    test('generateCopyPath génère un nom incrémental unique sans écraser', () {
      final tempDir = Directory.systemTemp.createTempSync('omnia_img_test');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final originalPath = p.join(tempDir.path, 'photo.png');
      File(originalPath).writeAsStringSync('dummy');

      final copy1 = ImageProcessorService.generateCopyPath(originalPath, suffix: '_edit');
      expect(copy1, p.join(tempDir.path, 'photo_edit.png'));

      File(copy1).writeAsStringSync('dummy copy 1');
      final copy2 = ImageProcessorService.generateCopyPath(originalPath, suffix: '_edit');
      expect(copy2, p.join(tempDir.path, 'photo_edit_1.png'));

      File(copy2).writeAsStringSync('dummy copy 2');
      final copy3 = ImageProcessorService.generateCopyPath(originalPath, suffix: '_edit');
      expect(copy3, p.join(tempDir.path, 'photo_edit_2.png'));
    });

    test('ImageEditParams détecte correctement la présence de modifications', () {
      const empty = ImageEditParams();
      expect(empty.hasModifications, isFalse);

      const withBrightness = ImageEditParams(brightness: 0.2);
      expect(withBrightness.hasModifications, isTrue);

      const withResize = ImageEditParams(targetWidth: 800);
      expect(withResize.hasModifications, isTrue);

      const withRotate = ImageEditParams(rotationAngle: 90);
      expect(withRotate.hasModifications, isTrue);

      const withPreset = ImageEditParams(preset: ImageFilterPreset.sepia);
      expect(withPreset.hasModifications, isTrue);
    });
  });
}
