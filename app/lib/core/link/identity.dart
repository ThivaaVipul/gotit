import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

/// Who this device is on the link: a random ID, and a key with a self-signed
/// certificate. The other side pins the certificate when the two pair.
class Identity {
  const Identity({
    required this.id,
    required this.certPem,
    required this.keyPem,
  });

  factory Identity.fromJson(Map<String, Object?> json) => Identity(
    id: json['id']! as String,
    certPem: json['cert']! as String,
    keyPem: json['key']! as String,
  );

  final String id;
  final String certPem;
  final String keyPem;

  /// SHA-256 of the certificate, the value the other side pins.
  String get fingerprint => fingerprintOfPem(certPem);

  /// A TLS context that proves this identity and trusts nothing by default.
  SecurityContext context() => SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certPem))
    ..usePrivateKeyBytes(utf8.encode(keyPem));

  Map<String, Object?> toJson() => {'id': id, 'cert': certPem, 'key': keyPem};
}

/// SHA-256 of a certificate's DER bytes, as lowercase hex.
String fingerprintOfDer(List<int> der) => sha256.convert(der).toString();

/// SHA-256 of a PEM certificate's DER bytes, as lowercase hex.
String fingerprintOfPem(String pem) => fingerprintOfDer(derOfPem(pem));

/// The DER bytes inside a PEM block.
Uint8List derOfPem(String pem) {
  final body = pem
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('-----'))
      .join();
  return base64.decode(body);
}

/// A random hex string of [bytes] bytes.
String randomHex(int bytes, [Random? random]) {
  final source = random ?? Random.secure();
  return List.generate(
    bytes,
    (_) => source.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Makes a new identity: an EC P-256 key and a certificate for it.
///
/// The certificate counts as valid from 2020 to the end of 2049, so clocks
/// that disagree between the two devices never make it look not yet valid or
/// expired. 2049 is the limit: certificates store years before 2050 as two
/// digits, and "60" would read as 1960.
Identity makeIdentity() {
  final id = randomHex(16);
  final pair = CryptoUtils.generateEcKeyPair();
  final privateKey = pair.privateKey as ECPrivateKey;
  final publicKey = pair.publicKey as ECPublicKey;
  final csr = X509Utils.generateEccCsrPem(
    {'CN': 'Gotit $id'},
    privateKey,
    publicKey,
  );
  final notBefore = DateTime.utc(2020);
  final cert = X509Utils.generateSelfSignedCertificate(
    privateKey,
    csr,
    DateTime.utc(2049, 12, 31).difference(notBefore).inDays,
    notBefore: notBefore,
    serialNumber: BigInt.parse(randomHex(8), radix: 16).toString(),
  );
  return Identity(
    id: id,
    certPem: cert,
    keyPem: CryptoUtils.encodeEcPrivateKeyToPem(privateKey),
  );
}

/// Somewhere to keep secrets: the device key store in the app, memory in tests.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Keeps this device's [Identity], making it on first use.
class IdentityStore {
  IdentityStore(this._secrets);

  final SecretStore _secrets;

  static const _key = 'identity';

  Future<Identity> loadOrCreate() async {
    final saved = await _secrets.read(_key);
    if (saved != null) {
      try {
        return Identity.fromJson(jsonDecode(saved) as Map<String, Object?>);
      } on Object {
        // Damaged: make a new one. Pairing has to be done again.
      }
    }
    // Making a key takes a moment in pure Dart: keep it off the UI thread.
    final identity = await Isolate.run(makeIdentity);
    await _secrets.write(_key, jsonEncode(identity.toJson()));
    return identity;
  }
}
