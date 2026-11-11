import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gotit/core/clip/bridge.dart';
import 'package:gotit/core/clip/clip.dart';
import 'package:gotit/core/link/frame.dart';
import 'package:gotit/core/link/identity.dart';
import 'package:gotit/core/link/pairing.dart';
import 'package:gotit/core/link/peer.dart';
import 'package:gotit/core/link/protocol.dart';
import 'package:gotit/core/link/session.dart';

/// How the link to the other device stands.
enum Connection {
  /// Not reachable right now.
  offline,

  /// Trying to reach it (the phone only).
  connecting,

  /// Linked and talking.
  online,

  /// Linked, but the two apps speak different link versions: update one.
  mismatch,
}

/// A phone asking to pair, waiting for Accept or Decline on the PC.
class PairRequest {
  PairRequest._({
    required this.phoneName,
    required this.code,
    required this.expiresAt,
    this.replaces,
  });

  /// A request as the PC would make it, for screens in tests.
  @visibleForTesting
  PairRequest.forTest({
    required this.phoneName,
    required this.code,
    required this.expiresAt,
    this.replaces,
  });

  final String phoneName;

  /// The 4 digits the phone shows too.
  final String code;
  final DateTime expiresAt;

  /// The phone this one would replace, when the PC is paired already.
  final String? replaces;

  final _decision = Completer<bool>();

  /// True once accepted, false once declined.
  Future<bool> get decided => _decision.future;

  void accept() {
    if (!_decision.isCompleted) _decision.complete(true);
  }

  void decline() {
    if (!_decision.isCompleted) _decision.complete(false);
  }
}

/// What the PC's side of the link is doing, for the screens.
class PcLinkState {
  const PcLinkState({
    this.phone,
    this.connection = Connection.offline,
    this.request,
    this.theirVersion,
  });

  /// The paired phone, if there is one.
  final Peer? phone;
  final Connection connection;

  /// A pairing request waiting for an answer.
  final PairRequest? request;

  /// The phone's link version, when it differs from this one.
  final int? theirVersion;

  PcLinkState copyWith({
    Peer? Function()? phone,
    Connection? connection,
    PairRequest? Function()? request,
    int? Function()? theirVersion,
  }) => PcLinkState(
    phone: phone != null ? phone() : this.phone,
    connection: connection ?? this.connection,
    request: request != null ? request() : this.request,
    theirVersion: theirVersion != null ? theirVersion() : this.theirVersion,
  );
}

/// The PC's side of the link: it listens for the phone, handles pairing, and
/// keeps the session with the paired phone.
///
/// One TLS port does both. A phone that is pairing shows no certificate and
/// can only ask to pair. The paired phone shows the certificate pinned when
/// they paired, and nothing else is let in.
class PcLink implements ClipLink {
  PcLink({
    required this.identity,
    required this.name,
    required Peer? phone,
    required this.savePhone,
    this.onRequest,
    this.address,
    this.preferredPort = LinkSpec.preferredPort,
    this.version = LinkSpec.version,
    this.pairTimeout = LinkSpec.pairTimeout,
    this.inviteLifetime = LinkSpec.inviteLifetime,
    this.stepTimeout = LinkSpec.stepTimeout,
    this.pingEvery = LinkSpec.pingEvery,
    this.silenceLimit = LinkSpec.silenceLimit,
  }) : _state = PcLinkState(phone: phone);

  final Identity identity;

  /// The PC's name as the phone shows it. Read each time it is sent.
  final String Function() name;

  /// Keeps the pairing (null when forgotten).
  final Future<void> Function(Peer? phone) savePhone;

  /// Called when a phone asks to pair, for bringing the window forward.
  final void Function(PairRequest request)? onRequest;

  /// Where to listen: every IPv4 address unless set (tests use loopback).
  final InternetAddress? address;
  final int preferredPort;
  final int version;
  final Duration pairTimeout;
  final Duration inviteLifetime;
  final Duration stepTimeout;
  final Duration pingEvery;
  final Duration silenceLimit;

  final _states = StreamController<PcLinkState>.broadcast();
  final _clips = StreamController<Clip>.broadcast();
  final _invites = <String, DateTime>{};
  PcLinkState _state;
  SecureServerSocket? _server;
  SecurityContext? _context;
  LinkSession? _session;

  PcLinkState get state => _state;
  Stream<PcLinkState> get states => _states.stream;

  @override
  Stream<Clip> get clips => _clips.stream;

  /// Sends [clip] to the phone, when it is linked with the same link version.
  @override
  bool sendClip(Clip clip) {
    final session = _session;
    if (session == null || _state.connection != Connection.online) {
      return false;
    }
    session.send(clip.toFrame());
    return true;
  }

  /// The port the PC listens on, once started.
  int get port => _server?.port ?? 0;

  /// Starts listening, on the preferred port when it is free.
  Future<void> start() async {
    final context = identity.context();
    final phone = _state.phone;
    if (phone != null) {
      context.setTrustedCertificatesBytes(utf8.encode(phone.certPem));
    }
    _context = context;
    final server = await _bind(preferredPort) ?? await _bind(0);
    if (server == null) throw const SocketException('Gotit could not listen');
    _server = server;
    server.listen(
      _onSocket,
      // A failed handshake: a stranger, or a phone this PC forgot. The
      // server keeps listening.
      onError: (Object _) {},
    );
  }

  Future<SecureServerSocket?> _bind(int port) async {
    try {
      return await SecureServerSocket.bind(
        address ?? InternetAddress.anyIPv4,
        port,
        _context,
        requestClientCertificate: true,
      );
    } on SocketException {
      return null;
    }
  }

  Future<void> stop() async {
    await _session?.close();
    await _server?.close();
    _server = null;
    _state.request?.decline();
    await _states.close();
    await _clips.close();
  }

  /// A QR invite: the PC's addresses, its certificate fingerprint and a
  /// one-time token, good for [inviteLifetime].
  PairInvite invite(List<String> hosts) {
    final now = DateTime.now();
    _invites.removeWhere((_, expires) => now.isAfter(expires));
    final token = randomHex(16);
    _invites[token] = now.add(inviteLifetime);
    return PairInvite(
      pcId: identity.id,
      pcName: name(),
      hosts: hosts,
      port: port,
      fingerprint: identity.fingerprint,
      token: token,
      version: version,
    );
  }

  /// Tells the phone the PC's new name.
  void renamed() => _session?.send(_hello());

  /// Forgets the paired phone, telling it too when it is connected.
  Future<void> forget() async {
    final session = _session;
    if (session != null) {
      session.send(const Frame(Frames.bye));
      await session.finish();
    }
    await savePhone(null);
    _set(
      _state.copyWith(
        phone: () => null,
        connection: Connection.offline,
        theirVersion: () => null,
      ),
    );
  }

  void _onSocket(SecureSocket socket) {
    final cert = socket.peerCertificate;
    if (cert == null) {
      unawaited(_pair(socket));
    } else {
      unawaited(_serve(socket, cert));
    }
  }

  Frame _hello() =>
      Frame(Frames.hello, {'id': identity.id, 'name': name(), 'v': version});

  // Pairing --------------------------------------------------------------

  Future<void> _pair(SecureSocket socket) async {
    final link = LinkSession(
      socket,
      pingEvery: pingEvery,
      silenceLimit: silenceLimit,
    );
    PairRequest? request;
    try {
      final asked = await link.next(timeout: stepTimeout);
      if (asked == null || asked.type != Frames.pairRequest) return;
      final id = asked.text('id');
      final phoneName = asked.text('name');
      final cert = asked.text('cert');
      if (id == null || phoneName == null || cert == null) return;
      if (asked.number('v') != version) {
        link.send(_refusal(PairRefusal.version));
        return;
      }
      final String phoneFingerprint;
      try {
        phoneFingerprint = fingerprintOfPem(cert);
      } on FormatException {
        return;
      }
      final phone = Peer(id: id, name: _clean(phoneName), certPem: cert);

      // From the QR code: the token stands in for the code and Accept.
      final token = asked.text('token');
      if (token != null) {
        if (!_useInvite(token)) {
          link.send(_refusal(PairRefusal.expired));
          return;
        }
        await _adopt(phone);
        link.send(_accepted());
        return;
      }

      if (_state.request != null) {
        link.send(_refusal(PairRefusal.busy));
        return;
      }
      request = PairRequest._(
        phoneName: phone.name,
        code: pairingCode(identity.fingerprint, phoneFingerprint),
        expiresAt: DateTime.now().add(pairTimeout),
        replaces: _state.phone?.name,
      );
      _set(_state.copyWith(request: () => request));
      link.send(Frame(Frames.pairWait, {'id': identity.id, 'name': name()}));
      onRequest?.call(request);

      final outcome = await Future.any([
        request._decision.future.then((yes) => yes ? 'accept' : 'decline'),
        Future<String>.delayed(pairTimeout, () => 'timeout'),
        link.done.then((_) => 'gone'),
      ]);
      switch (outcome) {
        case 'accept':
          await _adopt(phone);
          link.send(_accepted());
        case 'decline':
          link.send(_refusal(PairRefusal.declined));
        case 'timeout':
          link.send(_refusal(PairRefusal.timeout));
      }
    } finally {
      if (request != null && identical(_state.request, request)) {
        request.decline();
        _set(_state.copyWith(request: () => null));
      }
      await link.finish();
    }
  }

  Frame _accepted() =>
      Frame(Frames.pairOk, {'id': identity.id, 'name': name()});

  Frame _refusal(PairRefusal why) =>
      Frame(Frames.pairNo, {'reason': why.name, 'v': version});

  bool _useInvite(String token) {
    final expires = _invites.remove(token);
    return expires != null && DateTime.now().isBefore(expires);
  }

  /// Pairs with [phone], replacing any phone paired before.
  Future<void> _adopt(Peer phone) async {
    await savePhone(phone);
    // Trust its certificate for sessions from now on. A phone forgotten
    // later stays trusted by TLS until the next start, but the pin check in
    // _serve turns it away.
    _context?.setTrustedCertificatesBytes(utf8.encode(phone.certPem));
    final old = _session;
    _session = null;
    await old?.close();
    _set(
      _state.copyWith(
        phone: () => phone,
        connection: Connection.offline,
        theirVersion: () => null,
      ),
    );
  }

  // The paired session ---------------------------------------------------

  Future<void> _serve(SecureSocket socket, X509Certificate cert) async {
    final phone = _state.phone;
    if (phone == null || fingerprintOfDer(cert.der) != phone.fingerprint) {
      socket.destroy();
      return;
    }
    // A newer connection from the phone replaces an older one.
    final old = _session;
    final link = LinkSession(
      socket,
      pingEvery: pingEvery,
      silenceLimit: silenceLimit,
    );
    _session = link;
    await old?.close();

    link.send(_hello());
    final hello = await link.next(timeout: stepTimeout);
    if (hello == null || hello.type != Frames.hello) {
      await link.close();
      return;
    }
    await _greeted(hello);

    while (true) {
      final frame = await link.next();
      if (frame == null) break;
      switch (frame.type) {
        case Frames.hello:
          await _greeted(frame);
        case Frames.clip:
          // Only between matching versions.
          final clip = Clip.fromFrame(frame);
          if (clip != null && _state.connection == Connection.online) {
            _clips.add(clip);
          }
        case Frames.bye:
          // The phone forgot this pairing.
          await savePhone(null);
          _set(
            _state.copyWith(
              phone: () => null,
              connection: Connection.offline,
              theirVersion: () => null,
            ),
          );
          await link.close();
      }
    }
    if (identical(_session, link)) {
      _session = null;
      if (_state.phone != null) {
        _set(
          _state.copyWith(
            connection: Connection.offline,
            theirVersion: () => null,
          ),
        );
      }
    }
  }

  /// A hello from the phone: check the version and keep its name current.
  Future<void> _greeted(Frame hello) async {
    final theirs = hello.number('v');
    final newName = hello.text('name');
    var phone = _state.phone;
    if (phone != null && newName != null && _clean(newName) != phone.name) {
      phone = phone.copyWith(name: _clean(newName));
      await savePhone(phone);
    }
    _set(
      _state.copyWith(
        phone: () => phone,
        connection: theirs == version ? Connection.online : Connection.mismatch,
        theirVersion: () => theirs == version ? null : theirs,
      ),
    );
  }

  void _set(PcLinkState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }
}

/// A name from the other device, trimmed and kept to a sane length.
String _clean(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Phone';
  return trimmed.length > 40 ? trimmed.substring(0, 40) : trimmed;
}
