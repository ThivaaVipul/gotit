import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/link/pairing.dart';

void main() {
  final a = 'a' * 64;
  final b = 'b' * 64;
  final c = 'c' * 64;

  test('both sides get the same 4 digits, whichever way round', () {
    expect(pairingCode(a, b), pairingCode(b, a));
    expect(pairingCode(a, b), matches(RegExp(r'^\d{4}$')));
  });

  test('another certificate gives another code', () {
    expect(pairingCode(a, b), isNot(pairingCode(a, c)));
  });

  test('a QR invite reads back as written', () {
    final invite = PairInvite(
      pcId: '0123abcd',
      pcName: 'Desk PC & co',
      hosts: const ['192.0.2.10', '198.51.100.7'],
      port: 47331,
      fingerprint: c,
      token: 'feedface',
    );
    final back = PairInvite.parse(invite.encode())!;
    expect(back.pcId, invite.pcId);
    expect(back.pcName, invite.pcName);
    expect(back.hosts, invite.hosts);
    expect(back.port, invite.port);
    expect(back.fingerprint, invite.fingerprint);
    expect(back.token, invite.token);
  });

  test('anything else in a QR code is not an invite', () {
    expect(PairInvite.parse('https://example.com'), isNull);
    expect(PairInvite.parse('gotit://pair?v=1&p=1&h=x&f=zz&t=y&i=z'), isNull);
    expect(
      PairInvite.parse('gotit://pair?v=1&p=99999&h=x&f=$c&t=y&i=z'),
      isNull,
    );
    expect(PairInvite.parse('not a code at all'), isNull);
  });
}
