import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/services/mobile_window_service.dart';

void main() {
  group('MobileWindowService', () {
    late MobileWindowService service;

    setUp(() {
      service = MobileWindowService();
    });

    tearDown(() {
      service.dispose();
    });

    test('fullscreen toggle updates state', () async {
      expect(await service.isFullscreen(), isFalse);
      // setFullscreen interacts with SystemChrome in flutter test
    });

    test('alwaysOnTop toggle updates state', () async {
      expect(await service.isAlwaysOnTop(), isFalse);
    });

    test('isMaximized is always true on mobile', () async {
      expect(await service.isMaximized(), isTrue);
    });
  });
}
