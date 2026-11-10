import 'package:flutter/foundation.dart';
import 'package:gotit/core/link/identity.dart';

/// The device this one is paired with: its ID, its name, the certificate it
/// proved itself with when pairing, and where it was last reached (phone only).
@immutable
class Peer {
  const Peer({
    required this.id,
    required this.name,
    required this.certPem,
    this.host,
    this.port,
  });

  factory Peer.fromJson(Map<String, Object?> json) => Peer(
    id: json['id']! as String,
    name: json['name']! as String,
    certPem: json['cert']! as String,
    host: json['host'] is String ? json['host'] as String : null,
    port: json['port'] is int ? json['port'] as int : null,
  );

  final String id;
  final String name;
  final String certPem;
  final String? host;
  final int? port;

  /// The pinned fingerprint: only this certificate is accepted from the peer.
  String get fingerprint => fingerprintOfPem(certPem);

  Peer copyWith({String? name, String? host, int? port}) => Peer(
    id: id,
    name: name ?? this.name,
    certPem: certPem,
    host: host ?? this.host,
    port: port ?? this.port,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'cert': certPem,
    if (host != null) 'host': host,
    if (port != null) 'port': port,
  };

  @override
  bool operator ==(Object other) =>
      other is Peer &&
      other.id == id &&
      other.name == name &&
      other.certPem == certPem &&
      other.host == host &&
      other.port == port;

  @override
  int get hashCode => Object.hash(id, name, certPem, host, port);
}
