// Même fichier dans les dépôts bureau et mobile, aux imports près.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/providers.dart';
import 'package:omnia_mobile/core/services/connect_transfer.dart';
import 'package:omnia_mobile/core/services/omnia_connect_service.dart';
import 'package:omnia_mobile/ui/theme/omnia_theme.dart';
import 'package:omnia_mobile/ui/widgets/connect_transfer_widgets.dart';

/// Un service qui retient les réponses au lieu de les envoyer.
class _RecordingService extends OmniaConnectService {
  final List<TransferReply> replies = [];

  @override
  void replyToTransfer(TransferReply reply) => replies.add(reply);
}

const _incoming = IncomingTransfer(
  offer: TransferOffer(
    id: 'abcdefgh1234',
    // Un nom piégé : il ne doit ni s'afficher tel quel, ni servir tel quel.
    name: '../../vacances.mp4',
    size: 12 * 1024 * 1024,
    port: 41530,
    token: 'abcdefghijklmnopqrstuvwxyz012345',
    from: 'OMNIA Mobile',
  ),
  host: '192.168.1.20',
);

Future<_RecordingService> _open(WidgetTester tester) async {
  final service = _RecordingService();
  addTearDown(service.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [omniaConnectServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        theme: buildOmniaTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const IncomingTransferDialog(incoming: _incoming),
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return service;
}

void main() {
  testWidgets('une proposition dit qui envoie quoi, et un refus répond', (tester) async {
    final service = await _open(tester);

    expect(find.text('Fichier proposé'), findsOneWidget);
    expect(find.text('OMNIA Mobile vous propose un fichier.'), findsOneWidget);
    expect(find.text('vacances.mp4'), findsOneWidget);
    expect(find.text('12,0 Mo'), findsOneWidget);
    expect(find.text('Recevoir'), findsOneWidget);
    // Rien ne part tant que personne n'a répondu.
    expect(service.replies, isEmpty);

    await tester.tap(find.text('Refuser'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Fichier proposé'), findsNothing);
    expect(service.replies, hasLength(1));
    expect(service.replies.single.id, 'abcdefgh1234');
    expect(service.replies.single.kind, TransferReplyKind.declined);
  });
}
