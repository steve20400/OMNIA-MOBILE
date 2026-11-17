// Transfert de fichiers d'OMNIA Connect, côté interface. Fichier identique
// dans les dépôts bureau et mobile : toute modification se reporte dans
// l'autre.
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/commands/player_command.dart';
import '../../core/controllers/media_router.dart';
import '../../core/providers.dart';
import '../../core/services/connect_transfer.dart';
import '../../core/services/omnia_connect_service.dart';
import '../theme/omnia_theme.dart';
import 'omnia_button.dart';

/// Dernier dossier choisi pour ranger un fichier reçu, le temps de la
/// session : recevoir plusieurs fichiers d'affilée ne demande de le choisir
/// qu'une fois.
String? _lastFolder;

/// Dossier proposé pour ranger un fichier reçu : « OMNIA » dans les
/// téléchargements de l'appareil.
Future<String> defaultTransferFolder() async {
  if (Platform.isAndroid) return '/storage/emulated/0/Download/OMNIA';
  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return p.join(downloads.path, 'OMNIA');
  } on Object {
    // Dossier des téléchargements inconnu du système : repli ci-dessous.
  }
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.systemTemp.path;
  return p.join(home, 'Downloads', 'OMNIA');
}

/// Écoute les fichiers proposés par l'appareil relié, et demande pour
/// chacun à l'utilisateur s'il l'accepte.
///
/// Une seule demande à la fois : une proposition qui arrive pendant qu'une
/// autre attend sa réponse est refusée d'office. Sans cette limite, un
/// appareil du réseau pourrait couvrir l'écran de fenêtres.
StreamSubscription<IncomingTransfer> listenForIncomingTransfers(
  WidgetRef ref,
  GlobalKey<NavigatorState> navigator,
) {
  final service = ref.read(omniaConnectServiceProvider);
  var asking = false;
  return service.incomingTransfers.listen((incoming) {
    final context = navigator.currentContext;
    if (asking || context == null) {
      service.replyToTransfer(
        TransferReply(
          id: incoming.offer.id,
          kind: TransferReplyKind.declined,
          message: asking
              ? 'Une autre proposition attend déjà une réponse.'
              : "L'application n'est pas prête à recevoir.",
        ),
      );
      return;
    }
    // Monté par construction — `currentContext` ne rend que l'élément en
    // place —, mais la proposition arrive du réseau, à tout moment : la
    // vérification est explicite, comme l'analyse l'exige.
    if (!context.mounted) return;
    asking = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => IncomingTransferDialog(incoming: incoming),
      ).whenComplete(() => asking = false),
    );
  });
}

/// Choisit un fichier à envoyer ; `null` si rien n'a été choisi, ou si le
/// système n'en donne pas de chemin lisible.
Future<String?> _pickFileToSend() async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Envoyer un fichier',
    windowsOptions: const WindowsOptions(lockParentWindow: true),
    linuxOptions: const LinuxOptions(lockParentWindow: true),
  );
  final path = file?.path;
  if (path == null || path.isEmpty) return null;
  return path;
}

/// « Envoyer un fichier » à l'appareil relié, et ce qu'il en advient.
class TransferSendButton extends ConsumerStatefulWidget {
  const TransferSendButton({
    super.key,
    required this.peerLabel,
    required this.deviceName,
  });

  /// L'appareil d'en face, tel qu'on le nomme dans une phrase : « le PC ».
  final String peerLabel;

  /// Le nom de cet appareil, montré à celui qui reçoit.
  final String deviceName;

  @override
  ConsumerState<TransferSendButton> createState() => _TransferSendButtonState();
}

class _TransferSendButtonState extends ConsumerState<TransferSendButton> {
  bool _picking = false;
  String? _status;
  bool _failed = false;
  StreamSubscription<TransferReply>? _replies;
  Timer? _noAnswer;

  @override
  void dispose() {
    _replies?.cancel();
    _noAnswer?.cancel();
    super.dispose();
  }

  String get _peer =>
      widget.peerLabel[0].toUpperCase() + widget.peerLabel.substring(1);

  Future<void> _send() async {
    final service = ref.read(omniaConnectServiceProvider);
    setState(() => _picking = true);
    final path = await _pickFileToSend();
    if (!mounted) return;
    if (path == null) {
      setState(() => _picking = false);
      return;
    }
    final offer = await service.offerFile(path, from: widget.deviceName);
    if (!mounted) return;
    if (offer == null) {
      setState(() {
        _picking = false;
        _failed = true;
        _status = "Envoi impossible : ${widget.peerLabel} n'est plus relié, "
            'ou le fichier est introuvable.';
      });
      return;
    }

    final name = offer.name;
    await _replies?.cancel();
    _replies = service.transferReplies
        .where((reply) => reply.id == offer.id)
        .listen((reply) => _onReply(reply, name));
    _noAnswer?.cancel();
    // Un appareil qui n'est pas à jour ignore la proposition sans répondre :
    // mieux vaut le dire que de laisser attendre.
    _noAnswer = Timer(const Duration(minutes: 2), () {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _status = 'Pas de réponse de ${widget.peerLabel}. Si OMNIA n’y est '
            'pas à jour, il ne sait pas encore recevoir de fichiers.';
      });
    });
    setState(() {
      _picking = false;
      _failed = false;
      _status = 'Proposé à ${widget.peerLabel} : « $name » '
          '(${transferSizeLabel(offer.size)}). En attente de sa réponse…';
    });
  }

  void _onReply(TransferReply reply, String name) {
    _noAnswer?.cancel();
    if (reply.isFinal) {
      unawaited(_replies?.cancel());
      _replies = null;
    }
    if (!mounted) return;
    setState(() {
      _failed = reply.kind == TransferReplyKind.failed ||
          reply.kind == TransferReplyKind.declined;
      _status = switch (reply.kind) {
        TransferReplyKind.accepted => '$_peer reçoit « $name »…',
        TransferReplyKind.completed => '« $name » est arrivé sur ${widget.peerLabel}.',
        TransferReplyKind.declined => reply.message.isEmpty
            ? '$_peer a refusé « $name ».'
            : '$_peer a refusé « $name » : ${reply.message}',
        TransferReplyKind.failed => reply.message.isEmpty
            ? '« $name » n’est pas arrivé.'
            : '« $name » n’est pas arrivé : ${reply.message}',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OmniaButton(
          label: 'Envoyer un fichier à ${widget.peerLabel}',
          icon: Icons.upload_file_rounded,
          onPressed: _picking ? null : _send,
        ),
        if (_status != null) ...[
          const SizedBox(height: 8),
          Text(
            _status!,
            textAlign: TextAlign.center,
            style: type.secondary.copyWith(
              color: _failed ? colors.alert : colors.dust,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

enum _Phase { asking, receiving, done, failed }

/// La proposition d'un fichier : l'accepter ou non, choisir où le ranger,
/// puis le recevoir.
class IncomingTransferDialog extends ConsumerStatefulWidget {
  const IncomingTransferDialog({super.key, required this.incoming});

  final IncomingTransfer incoming;

  @override
  ConsumerState<IncomingTransferDialog> createState() =>
      _IncomingTransferDialogState();
}

class _IncomingTransferDialogState extends ConsumerState<IncomingTransferDialog> {
  _Phase _phase = _Phase.asking;
  String? _folder;
  int _received = 0;
  bool _cancelRequested = false;
  bool _answered = false;
  String? _savedPath;
  String _error = '';
  DateTime _lastPaint = DateTime.fromMillisecondsSinceEpoch(0);

  /// Lu une fois pour toutes : la réponse finale peut partir après une
  /// longue réception, et elle ne doit dépendre de rien d'autre.
  late final OmniaConnectService _service;

  TransferOffer get _offer => widget.incoming.offer;

  @override
  void initState() {
    super.initState();
    _service = ref.read(omniaConnectServiceProvider);
    final remembered = _lastFolder;
    if (remembered != null) {
      _folder = remembered;
    } else {
      unawaited(
        defaultTransferFolder().then((folder) {
          if (mounted) setState(() => _folder = folder);
        }),
      );
    }
  }

  /// Renvoie à l'expéditeur où en est sa proposition. Une seule réponse
  /// finale part, quel que soit le chemin qui ferme la fenêtre.
  void _reply(TransferReplyKind kind, [String message = '']) {
    if (_answered) return;
    if (kind != TransferReplyKind.accepted) _answered = true;
    _service.replyToTransfer(
      TransferReply(id: _offer.id, kind: kind, message: message),
    );
  }

  Future<void> _chooseFolder() async {
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Ranger le fichier reçu dans…',
      windowsOptions: const WindowsOptions(lockParentWindow: true),
      linuxOptions: const LinuxOptions(lockParentWindow: true),
    );
    if (dir != null && mounted) setState(() => _folder = dir);
  }

  Future<void> _accept() async {
    final folder = _folder;
    if (folder == null) return;
    _lastFolder = folder;
    setState(() => _phase = _Phase.receiving);
    _reply(TransferReplyKind.accepted);
    try {
      final file = await receiveTransfer(
        widget.incoming,
        folder,
        onProgress: _onProgress,
        cancelled: () => _cancelRequested,
      );
      _reply(TransferReplyKind.completed);
      await _announceToSystem(file.path);
      if (!mounted) return;
      setState(() {
        _phase = _Phase.done;
        _savedPath = file.path;
      });
    } on TransferException catch (e) {
      _reply(TransferReplyKind.failed, e.message);
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = e.message;
      });
    }
  }

  /// La barre avance par dixièmes de seconde : redessiner à chaque morceau
  /// reçu occuperait l'interface pour rien sur un gros fichier.
  void _onProgress(int received, int total) {
    final now = DateTime.now();
    if (received < total && now.difference(_lastPaint).inMilliseconds < 100) return;
    _lastPaint = now;
    if (mounted) setState(() => _received = received);
  }

  /// Sous Android, signale le nouveau fichier : sans cela il n'apparaît ni
  /// dans la galerie, ni dans « Ajoutés récemment ».
  Future<void> _announceToSystem(String path) async {
    if (!Platform.isAndroid) return;
    try {
      await const MethodChannel('dev.omnia.mobile/intent')
          .invokeMethod<bool>('scanFile', {'path': path});
    } on Object {
      // Le fichier est bien là ; il apparaîtra au prochain passage du système.
    }
  }

  void _decline() {
    _reply(TransferReplyKind.declined);
    Navigator.of(context).pop();
  }

  void _open(String path) {
    ref.read(commandBusProvider).dispatch(OpenFile(path));
    Navigator.of(context).pop();
  }

  void _reveal(String path) {
    ref.read(commandBusProvider).dispatch(RevealInFolder(path));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final from = _offer.from.isEmpty ? "L'appareil relié" : _offer.from;
    final total = _offer.size;

    final List<Widget> body;
    final List<Widget> actions;
    switch (_phase) {
      case _Phase.asking:
        body = [
          Text('$from vous propose un fichier.', style: type.body.copyWith(color: colors.screen)),
          const SizedBox(height: 12),
          _FileLine(name: safeFileName(_offer.name), size: total),
          const SizedBox(height: 16),
          Text('Ranger dans', style: type.caption.copyWith(color: colors.dust)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  _folder ?? '…',
                  style: type.secondary.copyWith(color: colors.screen),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: _chooseFolder,
                child: Text('Changer', style: type.secondary.copyWith(color: colors.projector)),
              ),
            ],
          ),
        ];
        actions = [
          OmniaButton(label: 'Refuser', onPressed: _decline),
          OmniaButton(
            label: 'Recevoir',
            icon: Icons.download_rounded,
            primary: true,
            onPressed: _folder == null ? null : _accept,
          ),
        ];
      case _Phase.receiving:
        body = [
          _FileLine(name: safeFileName(_offer.name), size: total),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: total == 0 ? null : _received / total,
            color: colors.projector,
            backgroundColor: colors.seam,
          ),
          const SizedBox(height: 8),
          Text(
            '${transferSizeLabel(_received)} sur ${transferSizeLabel(total)}',
            style: type.secondary.copyWith(color: colors.dust),
          ),
        ];
        actions = [
          OmniaButton(
            label: 'Annuler',
            onPressed: _cancelRequested ? null : () => setState(() => _cancelRequested = true),
          ),
        ];
      case _Phase.done:
        final saved = _savedPath!;
        final playable = MediaRouter.typeForPath(saved).isSupported;
        body = [
          Text('Fichier reçu.', style: type.body.copyWith(color: colors.screen)),
          const SizedBox(height: 8),
          Text(saved, style: type.secondary.copyWith(color: colors.dust)),
        ];
        actions = [
          if (!Platform.isAndroid)
            OmniaButton(label: 'Afficher dans le dossier', onPressed: () => _reveal(saved)),
          OmniaButton(label: 'Fermer', onPressed: () => Navigator.of(context).pop()),
          if (playable)
            OmniaButton(
              label: 'Ouvrir',
              icon: Icons.play_arrow_rounded,
              primary: true,
              onPressed: () => _open(saved),
            ),
        ];
      case _Phase.failed:
        body = [
          Text('Le fichier n’a pas été reçu.', style: type.body.copyWith(color: colors.screen)),
          const SizedBox(height: 8),
          Text(_error, style: type.secondary.copyWith(color: colors.alert)),
        ];
        actions = [
          OmniaButton(label: 'Fermer', onPressed: () => Navigator.of(context).pop()),
        ];
    }

    return PopScope(
      // Pendant la réception, seul « Annuler » arrête : un retour en
      // arrière par mégarde ne doit pas couper un gros transfert.
      canPop: _phase != _Phase.receiving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _phase == _Phase.asking) _reply(TransferReplyKind.declined);
      },
      child: AlertDialog(
        backgroundColor: colors.curtain,
        title: Text(
          switch (_phase) {
            _Phase.asking => 'Fichier proposé',
            _Phase.receiving => 'Réception…',
            _Phase.done => 'Reçu',
            _Phase.failed => 'Échec de la réception',
          },
          style: type.sectionTitle.copyWith(color: colors.screen),
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: body,
          ),
        ),
        actionsOverflowButtonSpacing: 8,
        actions: actions,
      ),
    );
  }
}

class _FileLine extends StatelessWidget {
  const _FileLine({required this.name, required this.size});

  final String name;
  final int size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Row(
      children: [
        Icon(Icons.insert_drive_file_rounded, color: colors.projector),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            style: type.bodyStrong.copyWith(color: colors.screen),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        Text(transferSizeLabel(size), style: type.secondary.copyWith(color: colors.dust)),
      ],
    );
  }
}
