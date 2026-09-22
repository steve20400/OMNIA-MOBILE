import 'dart:async';

import 'player_command.dart';

/// Origine d'une commande. Purement informatif aujourd'hui ; permettra demain
/// de distinguer les commandes locales des commandes de la télécommande.
enum CommandSource { ui, keyboard, cli, system, remote }

/// Une commande accompagnée de son origine et de son horodatage.
class DispatchedCommand {
  DispatchedCommand(this.command, this.source, [DateTime? timestamp])
      : timestamp = timestamp ?? DateTime.now();

  final PlayerCommand command;
  final CommandSource source;
  final DateTime timestamp;

  @override
  String toString() => 'DispatchedCommand(${source.name}: $command)';
}

/// Bus de commandes central.
///
/// Toute action utilisateur — clic, raccourci clavier, argument en ligne de
/// commande, et plus tard message WebSocket — passe par [dispatch]. Les
/// services (lecture, fenêtre, playlist) s'abonnent à [stream] et réagissent.
/// L'interface ne connaît que ce bus, jamais les contrôleurs.
class PlayerCommandBus {
  PlayerCommandBus();

  final StreamController<DispatchedCommand> _controller =
      StreamController<DispatchedCommand>.broadcast();

  /// Flux de toutes les commandes, dans l'ordre d'émission.
  Stream<DispatchedCommand> get stream => _controller.stream;

  /// Flux des commandes seules, sans métadonnées.
  Stream<PlayerCommand> get commands => stream.map((d) => d.command);

  bool get isClosed => _controller.isClosed;

  /// Publie une commande. Ne fait rien si le bus est fermé.
  void dispatch(PlayerCommand command, {CommandSource source = CommandSource.ui}) {
    if (_controller.isClosed) return;
    _controller.add(DispatchedCommand(command, source));
  }

  Future<void> dispose() => _controller.close();
}
