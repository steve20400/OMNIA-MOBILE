import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/models/app_preferences.dart';
import 'package:omnia_mobile/core/providers.dart';
import 'package:omnia_mobile/ui/theme/omnia_theme.dart';
import 'package:omnia_mobile/ui/widgets/desktop_promo_banner.dart';

class _CustomPreferencesNotifier extends PreferencesNotifier {
  _CustomPreferencesNotifier(this._initial);
  final AppPreferences _initial;

  @override
  AppPreferences build() => _initial;
}

void main() {
  testWidgets('DesktopPromoBanner displays PC promotion when not dismissed', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWith(
            () => _CustomPreferencesNotifier(const AppPreferences()),
          ),
        ],
        child: MaterialApp(
          theme: buildOmniaTheme(Brightness.dark),
          home: const Scaffold(body: DesktopPromoBanner()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Découvrez OMNIA pour PC'), findsOneWidget);
    expect(find.text('Découvrir'), findsOneWidget);
    expect(find.text('Afficher plus tard'), findsOneWidget);
    expect(find.text('Ne plus afficher'), findsOneWidget);
  });

  testWidgets('DesktopPromoBanner hides when desktopPromoDismissed is true', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWith(
            () => _CustomPreferencesNotifier(
              const AppPreferences(desktopPromoDismissed: true),
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildOmniaTheme(Brightness.dark),
          home: const Scaffold(body: DesktopPromoBanner()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Découvrez OMNIA pour PC'), findsNothing);
  });

  testWidgets('DesktopPromoBanner hides when desktopPromoSnoozeUntil is in the future', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWith(
            () => _CustomPreferencesNotifier(
              AppPreferences(
                desktopPromoSnoozeUntil: DateTime.now().add(const Duration(days: 3)),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildOmniaTheme(Brightness.dark),
          home: const Scaffold(body: DesktopPromoBanner()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Découvrez OMNIA pour PC'), findsNothing);
  });
}
