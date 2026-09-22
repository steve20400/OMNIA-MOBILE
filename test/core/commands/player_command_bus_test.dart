import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/commands/player_command.dart';
import 'package:omnia_mobile/core/commands/player_command_bus.dart';

void main() {
  group('PlayerCommandBus', () {
    late PlayerCommandBus bus;

    setUp(() => bus = PlayerCommandBus());
    tearDown(() => bus.dispose());

    test('livre les commandes dans l’ordre d’émission', () async {
      final received = <PlayerCommand>[];
      final sub = bus.commands.listen(received.add);

      bus.dispatch(const Play());
      bus.dispatch(const SeekRelative(5));
      bus.dispatch(const Pause());
      await Future<void>.delayed(Duration.zero);

      expect(received, [const Play(), const SeekRelative(5), const Pause()]);
      await sub.cancel();
    });

    test('plusieurs abonnés reçoivent chaque commande (broadcast)', () async {
      final a = <PlayerCommand>[];
      final b = <PlayerCommand>[];
      final subA = bus.commands.listen(a.add);
      final subB = bus.commands.listen(b.add);

      bus.dispatch(const ToggleMute());
      await Future<void>.delayed(Duration.zero);

      expect(a, [const ToggleMute()]);
      expect(b, [const ToggleMute()]);
      await subA.cancel();
      await subB.cancel();
    });

    test('transporte l’origine et l’horodatage', () async {
      final before = DateTime.now();
      final future = bus.stream.first;
      bus.dispatch(const NextFile(), source: CommandSource.keyboard);
      final dispatched = await future;

      expect(dispatched.command, const NextFile());
      expect(dispatched.source, CommandSource.keyboard);
      expect(dispatched.timestamp.isBefore(before), isFalse);
    });

    test('l’origine par défaut est l’interface', () async {
      final future = bus.stream.first;
      bus.dispatch(const Play());
      expect((await future).source, CommandSource.ui);
    });

    test('après dispose, dispatch est ignoré sans erreur', () async {
      final local = PlayerCommandBus();
      await local.dispose();
      expect(local.isClosed, isTrue);
      expect(() => local.dispatch(const Play()), returnsNormally);
    });

    test('une commande sérialisée peut être rejouée sur le bus', () async {
      // Simule ce que fera la télécommande : JSON → commande → bus.
      final json = const SetVolume(30).toJson();
      final future = bus.commands.first;
      bus.dispatch(PlayerCommand.fromJson(json), source: CommandSource.remote);
      expect(await future, const SetVolume(30));
    });
  });
}
