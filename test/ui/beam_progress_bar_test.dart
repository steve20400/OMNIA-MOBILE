import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/ui/theme/omnia_theme.dart';
import 'package:omnia_mobile/ui/widgets/beam_progress_bar.dart';
import 'package:omnia_mobile/ui/widgets/slim_slider.dart';

/// Barre de 400 px sur 100 s, posée devant une « scène » qui compte ses clics
/// (comme dans l'écran principal : la scène est dessous, dans la même pile),
/// le tout sous un gestionnaire de molette qui joue le rôle du volume.
class _Harness {
  final seeks = <Duration>[];
  final scrolls = <int>[];
  var stageTaps = 0;
  var volumeScrolls = 0;
  var starts = 0;
  var ends = 0;

  Widget build({bool enabled = true}) => MaterialApp(
        theme: buildOmniaTheme(Brightness.dark),
        home: Material(
          child: Listener(
            onPointerSignal: (event) =>
                GestureBinding.instance.pointerSignalResolver.register(event, (_) => volumeScrolls++),
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => stageTaps++,
                ),
                Center(
                  child: SizedBox(
                    width: 400,
                    child: BeamProgressBar(
                      progress: 0.25,
                      duration: const Duration(seconds: 100),
                      enabled: enabled,
                      onSeek: seeks.add,
                      onScrollSeek: scrolls.add,
                      onInteractionStart: () => starts++,
                      onInteractionEnd: () => ends++,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Point de la barre : [x] depuis la gauche, [y] depuis le haut de la barre.
Offset _at(WidgetTester tester, double x, double y) =>
    tester.getTopLeft(find.byType(BeamProgressBar)) + Offset(x, y);

void main() {
  // Hauteur totale : couloir du timecode (24) puis zone du trait (28), dont
  // le centre est le trait lui-même.
  const lineY = OmniaMetrics.beamTooltipHeight + OmniaMetrics.beamHitHeight / 2;

  testWidgets('un clic sur le trait déplace la lecture à l’endroit visé', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    await tester.tapAt(_at(tester, 200, lineY));
    expect(h.seeks, [const Duration(seconds: 50)]);
    expect(h.stageTaps, 0);
  });

  testWidgets('un clic à côté du trait ne déplace rien, ni ne traverse jusqu’à la scène', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    // Dans la zone du trait, mais hors de la bande sensible.
    await tester.tapAt(_at(tester, 200, lineY - OmniaMetrics.beamGrabHeight / 2 - 3));
    await tester.tapAt(_at(tester, 200, lineY + OmniaMetrics.beamGrabHeight / 2 + 3));
    expect(h.seeks, isEmpty);
    expect(h.stageTaps, 0);
  });

  testWidgets('le couloir du timecode, au-dessus, ne déplace pas la lecture', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    await tester.tapAt(_at(tester, 200, 6));
    expect(h.seeks, isEmpty);
  });

  testWidgets('la molette sur la barre avance ou recule, sans toucher au volume', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(_at(tester, 200, lineY)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -60)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 60)));
    expect(h.scrolls, [1, -1]);
    expect(h.volumeScrolls, 0);
  });

  testWidgets('barre inactive : la molette revient au volume', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build(enabled: false));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(_at(tester, 200, lineY)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -60)));
    expect(h.scrolls, isEmpty);
    expect(h.volumeScrolls, 1);
  });

  testWidgets('un glissement suit le pointeur et signale son début et sa fin', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.build());
    final gesture = await tester.startGesture(_at(tester, 100, lineY));
    // On sort de la bande en glissant : la recherche continue.
    await gesture.moveBy(const Offset(40, -30));
    await gesture.moveBy(const Offset(60, 0));
    await gesture.up();
    await tester.pump();
    expect(h.starts, 1);
    expect(h.ends, 1);
    expect(h.seeks.last, const Duration(seconds: 50));
  });

  testWidgets('curseur étiré : la valeur suit le pointeur sur toute la course', (tester) async {
    double? value;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildOmniaTheme(Brightness.dark),
        home: Material(
          child: Center(
            child: SizedBox(
              width: 300,
              child: Row(
                children: [
                  Expanded(child: SlimSlider(value: 0, onChanged: (v) => value = v)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final left = tester.getTopLeft(find.byType(SlimSlider));
    final height = tester.getSize(find.byType(SlimSlider)).height;
    await tester.tapAt(left + Offset(150, height / 2));
    expect(value, closeTo(0.5, 0.01));
  });
}
