import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:gotit/core/link/protocol.dart';

/// The 4-digit code both screens show while pairing, made from both
/// certificates' fingerprints. A device in the middle has its own certificate,
/// so the two screens would show different codes.
String pairingCode(String fingerprintA, String fingerprintB) {
  final both = [fingerprintA, fingerprintB]..sort();
  final digest = sha256.convert(
    utf8.encode('gotit-pair:${both[0]}:${both[1]}'),
  );
  final value = ByteData.sublistView(
    Uint8List.fromList(digest.bytes),
  ).getUint32(0);
  return (value % 10000).toString().padLeft(4, '0');
}

/// What the PC's QR code holds: where to reach it, the certificate to expect,
/// and a one-time token that pairs without the code and Accept.
class PairInvite {
  const PairInvite({
    required this.pcId,
    required this.pcName,
    required this.hosts,
    required this.port,
    required this.fingerprint,
    required this.token,
    this.version = LinkSpec.version,
  });

  final String pcId;
  final String pcName;
  final List<String> hosts;
  final int port;
  final String fingerprint;
  final String token;
  final int version;

  /// The text inside the QR code.
  String encode() => Uri(
    scheme: 'gotit',
    host: 'pair',
    queryParameters: {
      'v': '$version',
      'i': pcId,
      'n': pcName,
      'h': hosts.join(','),
      'p': '$port',
      'f': fingerprint,
      't': token,
    },
  ).toString();

  /// Reads a scanned code. Anything that isn't a complete Gotit invite gives
  /// null.
  static PairInvite? parse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.scheme != 'gotit' || uri.host != 'pair') {
      return null;
    }
    final q = uri.queryParameters;
    final version = int.tryParse(q['v'] ?? '');
    final port = int.tryParse(q['p'] ?? '');
    final hosts = (q['h'] ?? '').split(',').where((h) => h.isNotEmpty).toList();
    final fingerprint = q['f'] ?? '';
    final token = q['t'] ?? '';
    final pcId = q['i'] ?? '';
    if (version == null ||
        port == null ||
        port <= 0 ||
        port > 65535 ||
        hosts.isEmpty ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint) ||
        token.isEmpty ||
        pcId.isEmpty) {
      return null;
    }
    return PairInvite(
      pcId: pcId,
      pcName: q['n'] ?? '',
      hosts: hosts,
      port: port,
      fingerprint: fingerprint,
      token: token,
      version: version,
    );
  }
}
