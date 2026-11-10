import 'dart:convert';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/link/identity.dart';

class MemorySecrets implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  test('a new identity has a fresh ID, a key and a certificate', () {
    final a = makeIdentity();
    final b = makeIdentity();
    expect(a.id, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(a.id, isNot(b.id));
    expect(a.fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(a.fingerprint, isNot(b.fingerprint));
    expect(a.keyPem, contains('PRIVATE KEY'));
  });

  test('the certificate is valid from 2020 to the end of 2049', () {
    // Years from 2050 on would be written as two digits and read back as the
    // 1900s, making every certificate look expired.
    final validity = X509Utils.x509CertificateFromPem(
      makeIdentity().certPem,
    ).tbsCertificate!.validity;
    expect(validity.notBefore.toUtc().year, 2020);
    expect(validity.notAfter.toUtc().year, 2049);
  });

  test('is made once and then kept', () async {
    final secrets = MemorySecrets();
    final first = await IdentityStore(secrets).loadOrCreate();
    final again = await IdentityStore(secrets).loadOrCreate();
    expect(again.id, first.id);
    expect(again.certPem, first.certPem);
    expect(again.keyPem, first.keyPem);
  });

  test('a damaged saved identity is replaced', () async {
    final secrets = MemorySecrets()..values['identity'] = '{"id": 1}';
    final made = await IdentityStore(secrets).loadOrCreate();
    expect(made.id, matches(RegExp(r'^[0-9a-f]{32}$')));
    final saved = jsonDecode(secrets.values['identity']!) as Map;
    expect(saved['id'], made.id);
  });
}
