import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/clip/clip.dart';
import 'package:gotit/core/link/identity.dart';
import 'package:gotit/core/link/pairing.dart';
import 'package:gotit/core/link/pc_link.dart';
import 'package:gotit/core/link/peer.dart';
import 'package:gotit/core/link/phone_link.dart';
import 'package:gotit/core/link/protocol.dart';
import 'package:gotit/core/sharing/sharing.dart';

/// The two ends of the link, talking real TLS over localhost.
class Pair {
  Pair({
    required this.pcIdentity,
    required this.phoneIdentity,
    this.pcName = 'Desk PC',
  });

  final Identity pcIdentity;
  final Identity phoneIdentity;
  String pcName;
  Peer? pcSaved;
  Peer? phoneSaved;
  late PcLink pc;
  late PhoneLink phone;

  Future<void> startPc({
    Peer? phone,
    int port = 0,
    Duration pairTimeout = const Duration(seconds: 5),
  }) async {
    pcSaved = phone;
    pc = PcLink(
      identity: pcIdentity,
      name: () => pcName,
      phone: phone,
      savePhone: (p) async => pcSaved = p,
      address: InternetAddress.loopbackIPv4,
      preferredPort: port,
      pairTimeout: pairTimeout,
      stepTimeout: const Duration(seconds: 3),
    );
    await pc.start();
  }

  PhoneLink makePhone({
    Identity? identity,
    Peer? pc,
    int version = LinkSpec.version,
    Duration pairTimeout = const Duration(seconds: 5),
  }) {
    phoneSaved = pc;
    return PhoneLink(
      identity: identity ?? phoneIdentity,
      name: 'Test phone',
      pc: pc,
      savePc: (p) async => phoneSaved = p,
      locate: (_) async => [Endpoint('127.0.0.1', this.pc.port)],
      version: version,
      pairTimeout: pairTimeout,
      connectTimeout: const Duration(seconds: 3),
      stepTimeout: const Duration(seconds: 3),
      backoff: const [Duration(milliseconds: 50)],
    );
  }

  Endpoint get here => Endpoint('127.0.0.1', pc.port);

  /// The phone as the PC knows it once paired, and the PC as the phone does.
  Peer get phoneAsPeer => Peer(
    id: phoneIdentity.id,
    name: 'Test phone',
    certPem: phoneIdentity.certPem,
  );
  Peer get pcAsPeer => Peer(
    id: pcIdentity.id,
    name: pcName,
    certPem: pcIdentity.certPem,
    host: '127.0.0.1',
    port: pc.port,
  );
}

Future<void> until(
  bool Function() test, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!test()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for the link');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late Identity pcId;
  late Identity phoneId;
  late Identity strangerId;
  late Pair link;
  final toClose = <Future<void> Function()>[];

  setUpAll(() {
    pcId = makeIdentity();
    phoneId = makeIdentity();
    strangerId = makeIdentity();
  });

  setUp(() => link = Pair(pcIdentity: pcId, phoneIdentity: phoneId));

  tearDown(() async {
    for (final close in toClose.reversed) {
      await close();
    }
    toClose.clear();
  });

  Future<void> startPc({
    Peer? phone,
    int port = 0,
    Duration? pairTimeout,
  }) async {
    await link.startPc(
      phone: phone,
      port: port,
      pairTimeout: pairTimeout ?? const Duration(seconds: 5),
    );
    final pc = link.pc;
    toClose.add(pc.stop);
  }

  PhoneLink phone({
    Identity? identity,
    Peer? pc,
    int? version,
    Duration? pairTimeout,
  }) {
    final made = link.makePhone(
      identity: identity,
      pc: pc,
      version: version ?? LinkSpec.version,
      pairTimeout: pairTimeout ?? const Duration(seconds: 5),
    );
    toClose.add(made.close);
    return made;
  }

  test(
    'pairs by code: the same digits on both, then Accept, then the link',
    () async {
      await startPc();
      final ph = phone();
      final steps = <PairProgress>[];
      final attempt = ph.pair([link.here]);
      attempt.progress.listen(steps.add);

      await until(() => link.pc.state.request != null);
      await until(() => steps.whereType<PairShowCode>().isNotEmpty);
      final shown = steps.whereType<PairShowCode>().single;
      expect(shown.code, link.pc.state.request!.code);
      expect(shown.code, matches(RegExp(r'^\d{4}$')));
      expect(shown.pcName, 'Desk PC');
      expect(link.pc.state.request!.phoneName, 'Test phone');

      link.pc.state.request!.accept();
      await until(() => steps.whereType<PairDone>().isNotEmpty);
      expect(link.pcSaved?.id, phoneId.id);
      expect(link.pcSaved?.fingerprint, phoneId.fingerprint);
      expect(link.phoneSaved?.id, pcId.id);
      expect(link.phoneSaved?.fingerprint, pcId.fingerprint);
      expect(link.pc.state.request, isNull);

      await until(
        () =>
            ph.state.connection == Connection.online &&
            link.pc.state.connection == Connection.online,
      );
    },
  );

  test('Decline pairs nothing', () async {
    await startPc();
    final ph = phone();
    final steps = <PairProgress>[];
    ph.pair([link.here]).progress.listen(steps.add);
    await until(() => link.pc.state.request != null);
    link.pc.state.request!.decline();
    await until(() => steps.whereType<PairRefused>().isNotEmpty);
    expect(steps.whereType<PairRefused>().single.reason, PairRefusal.declined);
    expect(link.pcSaved, isNull);
    expect(link.phoneSaved, isNull);
    await until(() => link.pc.state.request == null);
  });

  test('an unanswered request runs out of time', () async {
    await startPc(pairTimeout: const Duration(milliseconds: 300));
    final ph = phone(pairTimeout: const Duration(milliseconds: 300));
    final steps = <PairProgress>[];
    ph.pair([link.here]).progress.listen(steps.add);
    await until(() => steps.whereType<PairRefused>().isNotEmpty);
    expect(steps.whereType<PairRefused>().single.reason, PairRefusal.timeout);
    expect(link.pcSaved, isNull);
  });

  test('cancelling on the phone takes the request off the PC', () async {
    await startPc();
    final attempt = phone().pair([link.here]);
    attempt.progress.listen((_) {});
    await until(() => link.pc.state.request != null);
    await attempt.cancel();
    await until(() => link.pc.state.request == null);
    expect(link.pcSaved, isNull);
  });

  test('a QR code pairs at once, and only once', () async {
    await startPc();
    final invite = link.pc.invite(['127.0.0.1']);
    final first = <PairProgress>[];
    phone().pairWithInvite(invite).progress.listen(first.add);
    await until(() => first.whereType<PairDone>().isNotEmpty);
    expect(link.pcSaved?.id, phoneId.id);

    final again = <PairProgress>[];
    phone(
      identity: strangerId,
    ).pairWithInvite(invite).progress.listen(again.add);
    await until(() => again.whereType<PairRefused>().isNotEmpty);
    expect(again.whereType<PairRefused>().single.reason, PairRefusal.expired);
    expect(link.pcSaved?.id, phoneId.id);
  });

  test(
    'a QR code naming another PC is refused before anything is sent',
    () async {
      await startPc();
      final real = link.pc.invite(['127.0.0.1']);
      final forged = PairInvite(
        pcId: real.pcId,
        pcName: real.pcName,
        hosts: real.hosts,
        port: real.port,
        fingerprint: strangerId.fingerprint,
        token: real.token,
      );
      final steps = <PairProgress>[];
      phone().pairWithInvite(forged).progress.listen(steps.add);
      await until(() => steps.whereType<PairFailed>().isNotEmpty);
      expect(link.pcSaved, isNull);
    },
  );

  test("a stranger's certificate gets no session", () async {
    await startPc(phone: link.phoneAsPeer);
    final stranger = phone(identity: strangerId, pc: link.pcAsPeer)..start();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(stranger.state.connection, isNot(Connection.online));
    expect(link.pc.state.connection, Connection.offline);
  });

  test('different link versions show a mismatch on both', () async {
    await startPc(phone: link.phoneAsPeer);
    final ph = phone(pc: link.pcAsPeer, version: LinkSpec.version + 1)..start();
    await until(
      () =>
          ph.state.connection == Connection.mismatch &&
          link.pc.state.connection == Connection.mismatch,
    );
    expect(link.pc.state.theirVersion, LinkSpec.version + 1);
    expect(ph.state.theirVersion, LinkSpec.version);
  });

  test('forgetting on the phone tells the PC', () async {
    await startPc(phone: link.phoneAsPeer);
    final ph = phone(pc: link.pcAsPeer)..start();
    await until(() => link.pc.state.connection == Connection.online);
    await ph.forget();
    expect(link.phoneSaved, isNull);
    await until(() => link.pc.state.phone == null);
    expect(link.pcSaved, isNull);
  });

  test('forgetting on the PC tells the phone', () async {
    await startPc(phone: link.phoneAsPeer);
    final ph = phone(pc: link.pcAsPeer)..start();
    await until(() => ph.state.connection == Connection.online);
    await link.pc.forget();
    expect(link.pcSaved, isNull);
    await until(() => ph.state.pc == null);
    expect(link.phoneSaved, isNull);
  });

  test("the PC's new name reaches the phone", () async {
    await startPc(phone: link.phoneAsPeer);
    final ph = phone(pc: link.pcAsPeer)..start();
    await until(() => ph.state.connection == Connection.online);
    link.pcName = 'Studio';
    link.pc.renamed();
    await until(() => ph.state.pc?.name == 'Studio');
    expect(link.phoneSaved?.name, 'Studio');
  });

  test('the phone comes back after the PC restarts', () async {
    await startPc(phone: link.phoneAsPeer);
    final port = link.pc.port;
    final ph = phone(pc: link.pcAsPeer)..start();
    await until(() => ph.state.connection == Connection.online);

    await link.pc.stop();
    await until(() => ph.state.connection != Connection.online);
    await startPc(phone: link.phoneAsPeer, port: port);
    await until(
      () =>
          ph.state.connection == Connection.online &&
          link.pc.state.connection == Connection.online,
    );
  });

  test('the sharing switch crosses both ways once linked', () async {
    await startPc(phone: link.phoneAsPeer);
    final ph = phone(pc: link.pcAsPeer);
    final off = SharingState(
      on: false,
      changedAt: DateTime(2026, 11, 11, 9),
      by: 'phone',
    );
    expect(ph.sendSharing(off), isFalse);

    final atPhone = <SharingState>[];
    final atPc = <SharingState>[];
    final phoneLinked = <bool>[];
    ph.sharingChanges.listen(atPhone.add);
    link.pc.sharingChanges.listen(atPc.add);
    ph.linkedChanges.listen(phoneLinked.add);
    ph.start();
    await until(() => ph.linked && link.pc.linked);
    expect(phoneLinked, contains(true));

    expect(ph.sendSharing(off), isTrue);
    expect(link.pc.sendSharing(SharingState.initial), isTrue);
    await until(() => atPhone.isNotEmpty && atPc.isNotEmpty);
    expect(atPc.single, off);
    expect(atPhone.single, SharingState.initial);
  });

  test('an image bigger than a text frame crosses', () async {
    await startPc(phone: link.phoneAsPeer);
    final ph = phone(pc: link.pcAsPeer);
    final atPc = <Clip>[];
    link.pc.clips.listen(atPc.add);
    ph.start();
    await until(() => ph.linked && link.pc.linked);

    final png = Uint8List(3 * 1024 * 1024)..[0] = 0x89;
    expect(ph.sendClip(Clip(image: png)), isTrue);
    await until(() => atPc.isNotEmpty);
    expect(atPc.single.image, png);
  });

  test('copies cross both ways once linked, and not before', () async {
    await startPc(phone: link.phoneAsPeer);
    final ph = phone(pc: link.pcAsPeer);
    expect(ph.sendClip(Clip(text: 'too early')), isFalse);
    expect(link.pc.sendClip(Clip(text: 'too early')), isFalse);

    final atPhone = <Clip>[];
    final atPc = <Clip>[];
    ph.clips.listen(atPhone.add);
    link.pc.clips.listen(atPc.add);
    ph.start();
    await until(
      () =>
          ph.state.connection == Connection.online &&
          link.pc.state.connection == Connection.online,
    );

    expect(
      link.pc.sendClip(Clip(text: 'from the PC', sensitive: true)),
      isTrue,
    );
    expect(ph.sendClip(Clip(text: 'from the phone')), isTrue);
    await until(() => atPhone.isNotEmpty && atPc.isNotEmpty);
    expect(atPhone.single.text, 'from the PC');
    expect(atPhone.single.sensitive, isTrue);
    expect(atPc.single.text, 'from the phone');
    expect(atPc.single.sensitive, isFalse);
  });
}
