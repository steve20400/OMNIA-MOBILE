// Même fichier dans les dépôts bureau et mobile, aux imports près.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia_mobile/core/services/connect_transfer.dart';
import 'package:omnia_mobile/core/services/omnia_connect_service.dart';
import 'package:path/path.dart' as p;

/// Un dossier de travail jetable, effacé à la fin du test.
Directory _scratch() {
  final dir = Directory.systemTemp.createTempSync('omnia_transfert_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

/// Un serveur local qui ne sert que les propositions de [outgoing].
Future<HttpServer> _serve(OutgoingTransfers outgoing) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(outgoing.serve);
  addTearDown(() => server.close(force: true));
  return server;
}

List<String> _names(Directory dir) =>
    dir.listSync().map((e) => p.basename(e.path)).toList()..sort();

/// Attend que [condition] devienne vraie, deux secondes au plus.
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  group('Nom de fichier reçu', () {
    test('ne sort jamais du dossier choisi', () {
      expect(safeFileName('../../.bashrc'), '.bashrc');
      expect(safeFileName(r'C:\Windows\system.ini'), 'system.ini');
      expect(safeFileName('/etc/passwd'), 'passwd');
      expect(safeFileName('..'), 'fichier');
      expect(safeFileName('dossier/'), 'fichier');
    });

    test('remplace ce que Windows interdit', () {
      expect(safeFileName('a<b>c?.mkv'), 'a_b_c_.mkv');
      expect(safeFileName('film. '), 'film');
      expect(safeFileName('CON.txt'), '_CON.txt');
      expect(safeFileName('lpt1'), '_lpt1');
      expect(safeFileName('${'x' * 300}.mp4'), hasLength(180));
      expect(safeFileName('${'x' * 300}.mp4'), endsWith('.mp4'));
    });

    test("n'écrase jamais un fichier déjà là", () {
      final dir = _scratch();
      expect(freeDestination(dir.path, 'a.txt'), p.join(dir.path, 'a.txt'));
      File(p.join(dir.path, 'a.txt')).writeAsStringSync('déjà là');
      expect(freeDestination(dir.path, 'a.txt'), p.join(dir.path, 'a (2).txt'));
      // Une réception en cours réserve aussi son nom.
      File(p.join(dir.path, 'a (2).txt.part')).writeAsStringSync('');
      expect(freeDestination(dir.path, 'a.txt'), p.join(dir.path, 'a (3).txt'));
    });
  });

  group('Messages de transfert', () {
    test('une proposition fait l’aller-retour', () {
      const offer = TransferOffer(
        id: 'abcdefgh1234',
        name: 'vacances.mp4',
        size: 1234,
        port: 41530,
        token: 'abcdefghijklmnopqrstuvwxyz012345',
        from: 'OMNIA Mobile',
      );
      final copy = TransferOffer.fromPayload(offer.toPayload())!;
      expect(copy.id, offer.id);
      expect(copy.name, offer.name);
      expect(copy.size, offer.size);
      expect(copy.port, offer.port);
      expect(copy.token, offer.token);
      expect(copy.from, offer.from);
    });

    test('une proposition mal formée est écartée', () {
      Map<String, Object?> payload({
        Object? id = 'abcdefgh1234',
        Object? name = 'a.mp4',
        Object? size = 10,
        Object? port = 41530,
        Object? token = 'abcdefghijklmnopqrstuvwxyz012345',
      }) =>
          {'id': id, 'name': name, 'size': size, 'port': port, 'token': token};

      expect(TransferOffer.fromPayload(payload()), isNotNull);
      expect(TransferOffer.fromPayload(payload(id: 'court')), isNull);
      expect(TransferOffer.fromPayload(payload(id: '../../etc/x')), isNull);
      expect(TransferOffer.fromPayload(payload(name: '  ')), isNull);
      expect(TransferOffer.fromPayload(payload(size: -1)), isNull);
      expect(TransferOffer.fromPayload(payload(size: 1.5)), isNull);
      expect(TransferOffer.fromPayload(payload(size: TransferOffer.maxSize + 1)), isNull);
      expect(TransferOffer.fromPayload(payload(port: 0)), isNull);
      expect(TransferOffer.fromPayload(payload(port: 70000)), isNull);
      expect(TransferOffer.fromPayload(payload(token: 'court')), isNull);
      expect(TransferOffer.fromPayload(payload(token: 'a b c d e f g h i j k l')), isNull);
    });

    test('une réponse fait l’aller-retour, une inconnue est écartée', () {
      const reply = TransferReply(
        id: 'abcdefgh1234',
        kind: TransferReplyKind.failed,
        message: 'Disque plein',
      );
      final copy = TransferReply.fromPayload(reply.toPayload())!;
      expect(copy.kind, TransferReplyKind.failed);
      expect(copy.message, 'Disque plein');
      expect(copy.isFinal, isTrue);
      expect(const TransferReply(id: 'x', kind: TransferReplyKind.accepted).isFinal, isFalse);
      expect(TransferReply.fromPayload({'id': 'x', 'kind': 'pirate'}), isNull);
    });

    test('tailles lisibles', () {
      expect(transferSizeLabel(840), '840 o');
      expect(transferSizeLabel(12 * 1024 + 410), '12,4 Ko');
      expect(transferSizeLabel(3 * 1024 * 1024 * 1024), '3,0 Go');
    });
  });

  group('Réception', () {
    test('le fichier arrive entier, sous son nom, sans reste', () async {
      final source = _scratch();
      final target = _scratch();
      final outgoing = OutgoingTransfers();
      final server = await _serve(outgoing);
      final bytes = List<int>.generate(300000, (i) => i % 251);
      final file = File(p.join(source.path, 'concert.mkv'))..writeAsBytesSync(bytes);

      final offer = outgoing.offer(file.path, port: server.port, from: 'PC')!;
      expect(offer.name, 'concert.mkv');
      expect(offer.size, bytes.length);

      var last = -1;
      final received = await receiveTransfer(
        IncomingTransfer(offer: offer, host: '127.0.0.1'),
        target.path,
        onProgress: (done, total) {
          expect(total, bytes.length);
          last = done;
        },
      );

      expect(p.basename(received.path), 'concert.mkv');
      expect(received.readAsBytesSync(), bytes);
      expect(last, bytes.length);
      expect(_names(target), ['concert.mkv']);
    });

    test('un mauvais jeton ne donne rien, et ne laisse rien', () async {
      final source = _scratch();
      final target = _scratch();
      final outgoing = OutgoingTransfers();
      final server = await _serve(outgoing);
      final file = File(p.join(source.path, 'secret.txt'))..writeAsStringSync('privé');
      final offer = outgoing.offer(file.path, port: server.port)!;

      final forged = TransferOffer(
        id: offer.id,
        name: offer.name,
        size: offer.size,
        port: offer.port,
        token: 'abcdefghijklmnopqrstuvwxyz012345',
      );
      await expectLater(
        receiveTransfer(IncomingTransfer(offer: forged, host: '127.0.0.1'), target.path),
        throwsA(isA<TransferException>()),
      );
      expect(_names(target), isEmpty);
    });

    test('une proposition close ou expirée n’est plus servie', () async {
      final source = _scratch();
      final target = _scratch();
      var now = DateTime(2026, 11, 17, 12);
      final outgoing = OutgoingTransfers(clock: () => now);
      final server = await _serve(outgoing);
      final file = File(p.join(source.path, 'a.pdf'))..writeAsStringSync('pdf');

      final closed = outgoing.offer(file.path, port: server.port)!;
      outgoing.close(closed.id);
      await expectLater(
        receiveTransfer(IncomingTransfer(offer: closed, host: '127.0.0.1'), target.path),
        throwsA(isA<TransferException>()),
      );

      final expiring = outgoing.offer(file.path, port: server.port)!;
      expect(outgoing.isOpen(expiring.id), isTrue);
      now = now.add(transferLifetime + const Duration(seconds: 1));
      expect(outgoing.isOpen(expiring.id), isFalse);
      expect(_names(target), isEmpty);
    });

    test('ni plus ni moins que la taille annoncée', () async {
      final source = _scratch();
      final target = _scratch();
      final outgoing = OutgoingTransfers();
      final server = await _serve(outgoing);
      final file = File(p.join(source.path, 'b.bin'))..writeAsBytesSync(List<int>.filled(5000, 7));
      final offer = outgoing.offer(file.path, port: server.port)!;

      TransferOffer resized(int size) => TransferOffer(
            id: offer.id,
            name: offer.name,
            size: size,
            port: offer.port,
            token: offer.token,
          );

      // Plus d'octets qu'annoncé : arrêt net.
      await expectLater(
        receiveTransfer(IncomingTransfer(offer: resized(100), host: '127.0.0.1'), target.path),
        throwsA(isA<TransferException>()),
      );
      // Moins qu'annoncé : le fichier serait tronqué.
      await expectLater(
        receiveTransfer(IncomingTransfer(offer: resized(9000), host: '127.0.0.1'), target.path),
        throwsA(isA<TransferException>()),
      );
      expect(_names(target), isEmpty);
    });

    test('annuler en cours de route ne laisse rien', () async {
      final source = _scratch();
      final target = _scratch();
      final outgoing = OutgoingTransfers();
      final server = await _serve(outgoing);
      final file = File(p.join(source.path, 'c.bin'))..writeAsBytesSync(List<int>.filled(400000, 1));
      final offer = outgoing.offer(file.path, port: server.port)!;

      await expectLater(
        receiveTransfer(
          IncomingTransfer(offer: offer, host: '127.0.0.1'),
          target.path,
          cancelled: () => true,
        ),
        throwsA(isA<TransferException>()),
      );
      expect(_names(target), isEmpty);
    });
  });

  group('Entre deux appareils reliés', () {
    late OmniaConnectService pc;
    late OmniaConnectService mobile;

    setUp(() async {
      pc = OmniaConnectService(port: 0);
      mobile = OmniaConnectService(port: 0);
      final port = await pc.start(address: InternetAddress.loopbackIPv4);
      final ok = await mobile.client.connect(
        host: '127.0.0.1',
        port: port,
        token: pc.sessionToken!,
        name: 'OMNIA Mobile',
      );
      expect(ok, isTrue);
      await _until(() => pc.hasConnectedClients);
    });

    tearDown(() async {
      await mobile.stop();
      mobile.dispose();
      await pc.stop();
      pc.dispose();
    });

    test('du téléphone au PC : proposé, reçu, puis plus servi', () async {
      final source = _scratch();
      final target = _scratch();
      final file = File(p.join(source.path, 'photo.jpg'))..writeAsBytesSync(List<int>.filled(2048, 3));

      final arrival = pc.incomingTransfers.first;
      final offer = await mobile.offerFile(file.path, from: 'OMNIA Mobile');
      expect(offer, isNotNull);
      final incoming = await arrival.timeout(const Duration(seconds: 5));

      // L'adresse est celle d'où vient la liaison, pas une adresse annoncée.
      expect(incoming.host, '127.0.0.1');
      expect(incoming.offer.name, 'photo.jpg');
      expect(incoming.offer.from, 'OMNIA Mobile');

      final received = await receiveTransfer(incoming, target.path);
      expect(received.lengthSync(), 2048);

      final answer = mobile.transferReplies.first;
      pc.replyToTransfer(TransferReply(id: offer!.id, kind: TransferReplyKind.completed));
      final reply = await answer.timeout(const Duration(seconds: 5));
      expect(reply.kind, TransferReplyKind.completed);
      expect(mobile.transfers.isOpen(offer.id), isFalse);
    });

    test('du PC au téléphone : la proposition passe par la même liaison', () async {
      final source = _scratch();
      final target = _scratch();
      final file = File(p.join(source.path, 'notes.pdf'))..writeAsStringSync('%PDF-1.4');

      final arrival = mobile.incomingTransfers.first;
      final offer = await pc.offerFile(file.path, from: 'OMNIA Desktop');
      expect(offer, isNotNull);
      final incoming = await arrival.timeout(const Duration(seconds: 5));
      expect(incoming.host, '127.0.0.1');

      final received = await receiveTransfer(incoming, target.path);
      expect(received.readAsStringSync(), '%PDF-1.4');

      // Un refus ferme aussi la proposition.
      final answer = pc.transferReplies.first;
      mobile.replyToTransfer(TransferReply(id: offer!.id, kind: TransferReplyKind.declined));
      await answer.timeout(const Duration(seconds: 5));
      expect(pc.transfers.isOpen(offer.id), isFalse);
    });

    test('sans appareil relié, rien n’est proposé', () async {
      final seul = OmniaConnectService(port: 0);
      addTearDown(() async {
        await seul.stop();
        seul.dispose();
      });
      final file = File(p.join(_scratch().path, 'x.txt'))..writeAsStringSync('x');
      expect(await seul.offerFile(file.path, from: 'PC'), isNull);
    });

    test('la route des transferts ne sert aucun autre fichier', () async {
      final http = HttpClient();
      addTearDown(() => http.close(force: true));
      final request = await http.getUrl(
        Uri.http('127.0.0.1:${await pc.start()}', transferPath, {
          'id': 'abcdefgh1234',
          'token': pc.sessionToken!,
          'path': '/etc/passwd',
        }),
      );
      final response = await request.close();
      await response.drain<void>();
      expect(response.statusCode, HttpStatus.notFound);
    });
  });
}
