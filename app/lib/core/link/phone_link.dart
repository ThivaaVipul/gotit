import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:gotit/core/link/frame.dart';
import 'package:gotit/core/link/identity.dart';
import 'package:gotit/core/link/pairing.dart';
import 'package:gotit/core/link/pc_link.dart' show Connection;
import 'package:gotit/core/link/peer.dart';
import 'package:gotit/core/link/protocol.dart';
import 'package:gotit/core/link/session.dart';

export 'package:gotit/core/link/pc_link.dart' show Connection;

/// Where a PC can be reached.
class Endpoint {
  const Endpoint(this.host, this.port);

  final String host;
  final int port;

  @override
  bool operator ==(Object other) =>
      other is Endpoint && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => '$host:$port';
}

/// A step of pairing, as the phone sees it.
sealed class PairProgress {
  const PairProgress();
}

class PairConnecting extends PairProgress {
  const PairConnecting();
}

/// Both screens now show [code]; the PC waits for Accept.
class PairShowCode extends PairProgress {
  const PairShowCode({required this.code, required this.pcName});

  final String code;
  final String pcName;
}

class PairDone extends PairProgress {
  const PairDone(this.pc);

  final Peer pc;
}

/// The PC said no, or the time ran out.
class PairRefused extends PairProgress {
  const PairRefused(this.reason);

  final PairRefusal reason;
}

/// The PC couldn't be reached, or the link broke.
class PairFailed extends PairProgress {
  const PairFailed();
}

/// One try at pairing. Cancelling closes the connection at once.
class PairAttempt {
  PairAttempt._();

  /// An attempt that reports [steps], for screens in tests.
  @visibleForTesting
  PairAttempt.fromSteps(Stream<PairProgress> steps) {
    steps.listen(_report, onDone: _progress.close);
  }

  final _progress = StreamController<PairProgress>();
  LinkSession? _link;
  bool _cancelled = false;

  Stream<PairProgress> get progress => _progress.stream;

  Future<void> cancel() async {
    _cancelled = true;
    await _link?.close();
  }

  void _report(PairProgress step) {
    if (!_progress.isClosed) _progress.add(step);
  }
}

/// What the phone's side of the link is doing, for the screens.
class PhoneLinkState {
  const PhoneLinkState({
    this.pc,
    this.connection = Connection.offline,
    this.theirVersion,
  });

  /// The paired PC, if there is one.
  final Peer? pc;
  final Connection connection;

  /// The PC's link version, when it differs from this one.
  final int? theirVersion;
}

/// The phone's side of the link: it pairs with a PC, then keeps a session
/// with it open while it is running.
class PhoneLink {
  PhoneLink({
    required this.identity,
    required this.name,
    required Peer? pc,
    required this.savePc,
    required this.locate,
    this.version = LinkSpec.version,
    this.pairTimeout = LinkSpec.pairTimeout,
    this.connectTimeout = LinkSpec.connectTimeout,
    this.stepTimeout = LinkSpec.stepTimeout,
    this.pingEvery = LinkSpec.pingEvery,
    this.silenceLimit = LinkSpec.silenceLimit,
    this.backoff = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 20),
      Duration(seconds: 30),
    ],
  }) : _state = PhoneLinkState(pc: pc);

  final Identity identity;

  /// This phone's name as the PC shows it.
  final String name;

  /// Keeps the pairing (null when forgotten).
  final Future<void> Function(Peer? pc) savePc;

  /// Where the PC with this ID can be reached right now, from mDNS.
  final Future<List<Endpoint>> Function(String pcId) locate;

  final int version;
  final Duration pairTimeout;
  final Duration connectTimeout;
  final Duration stepTimeout;
  final Duration pingEvery;
  final Duration silenceLimit;

  /// Waits between tries to reach the PC; the last one repeats.
  final List<Duration> backoff;

  final _states = StreamController<PhoneLinkState>.broadcast();
  PhoneLinkState _state;
  LinkSession? _session;
  bool _running = false;
  Completer<void>? _pause;

  PhoneLinkState get state => _state;
  Stream<PhoneLinkState> get states => _states.stream;

  // Pairing --------------------------------------------------------------

  /// Pairs with a PC found on the network at [endpoints], tried in order:
  /// both show a code, and the PC's Accept finishes it.
  PairAttempt pair(List<Endpoint> endpoints) {
    final attempt = PairAttempt._();
    unawaited(_pair(attempt, endpoints));
    return attempt;
  }

  /// Pairs from a scanned QR code: no code to compare and no Accept.
  PairAttempt pairWithInvite(PairInvite invite) {
    final attempt = PairAttempt._();
    unawaited(
      _pair(attempt, [
        for (final host in invite.hosts) Endpoint(host, invite.port),
      ], invite: invite),
    );
    return attempt;
  }

  Future<void> _pair(
    PairAttempt attempt,
    List<Endpoint> endpoints, {
    PairInvite? invite,
  }) async {
    attempt._report(const PairConnecting());
    try {
      if (invite != null && invite.version != version) {
        attempt._report(const PairRefused(PairRefusal.version));
        return;
      }
      // ignore: close_sinks, the LinkSession below owns and closes it.
      SecureSocket? socket;
      Endpoint? reached;
      for (final at in endpoints) {
        if (attempt._cancelled) return;
        socket = await _connect(
          at,
          // No certificate of its own: this phone isn't paired yet. From a QR
          // code, only the PC it names is accepted; found on the network, the
          // code on both screens does that job.
          SecurityContext(withTrustedRoots: false),
          (fingerprint) => invite == null || fingerprint == invite.fingerprint,
        );
        if (socket != null) {
          reached = at;
          break;
        }
      }
      if (socket == null || reached == null) {
        attempt._report(const PairFailed());
        return;
      }
      final pcCert = socket.peerCertificate!;
      final link = LinkSession(
        socket,
        pingEvery: pingEvery,
        silenceLimit: silenceLimit,
      );
      attempt._link = link;
      if (attempt._cancelled) {
        await link.close();
        return;
      }
      link.send(
        Frame(Frames.pairRequest, {
          'id': identity.id,
          'name': name,
          'cert': identity.certPem,
          'v': version,
          if (invite != null) 'token': invite.token,
        }),
      );

      var answer = await link.next(timeout: stepTimeout);
      if (answer != null && answer.type == Frames.pairWait) {
        attempt._report(
          PairShowCode(
            code: pairingCode(
              identity.fingerprint,
              fingerprintOfDer(pcCert.der),
            ),
            pcName: answer.text('name') ?? '',
          ),
        );
        answer = await link.next(timeout: pairTimeout + stepTimeout);
      }
      await link.close();
      if (attempt._cancelled) return;

      if (answer == null) {
        attempt._report(const PairFailed());
      } else if (answer.type == Frames.pairNo) {
        attempt._report(PairRefused(PairRefusal.parse(answer.text('reason'))));
      } else if (answer.type == Frames.pairOk && answer.text('id') != null) {
        final pc = Peer(
          id: answer.text('id')!,
          name: _clean(answer.text('name') ?? ''),
          certPem: pcCert.pem,
          host: reached.host,
          port: reached.port,
        );
        await savePc(pc);
        _set(PhoneLinkState(pc: pc));
        attempt._report(PairDone(pc));
        start();
      } else {
        attempt._report(const PairFailed());
      }
    } finally {
      await attempt._progress.close();
    }
  }

  // The paired session ---------------------------------------------------

  /// Keeps the link to the paired PC up until [stop]. Safe to call again.
  void start() {
    if (_running || _state.pc == null) return;
    _running = true;
    unawaited(_run());
  }

  /// Drops the link and stops trying.
  Future<void> stop() async {
    _running = false;
    retryNow();
    await _session?.close();
  }

  /// Tries the PC again now instead of waiting, such as when the app comes
  /// back to the front or mDNS sees it.
  void retryNow() {
    final pause = _pause;
    if (pause != null && !pause.isCompleted) pause.complete();
  }

  /// Forgets the PC, telling it too when it is connected.
  Future<void> forget() async {
    _running = false;
    retryNow();
    final session = _session;
    if (session != null) {
      session.send(const Frame(Frames.bye));
      await session.finish();
    }
    await savePc(null);
    _set(const PhoneLinkState());
  }

  Future<void> close() async {
    await stop();
    await _states.close();
  }

  Future<void> _run() async {
    var failures = 0;
    while (_running) {
      final pc = _state.pc;
      if (pc == null) break;
      _set(PhoneLinkState(pc: pc, connection: Connection.connecting));

      final endpoints = <Endpoint>{
        if (pc.host != null && pc.port != null) Endpoint(pc.host!, pc.port!),
        ...await _locateSafely(pc.id),
      };
      LinkSession? link;
      Endpoint? reached;
      for (final at in endpoints) {
        if (!_running) break;
        link = await _open(at, pc);
        if (link != null) {
          reached = at;
          break;
        }
      }
      if (!_running) {
        await link?.close();
        break;
      }

      if (link != null && reached != null) {
        failures = 0;
        if (reached.host != pc.host || reached.port != pc.port) {
          final moved = pc.copyWith(host: reached.host, port: reached.port);
          await savePc(moved);
          _set(PhoneLinkState(pc: moved, connection: _state.connection));
        }
        await _serve(link);
        if (!_running || _state.pc == null) break;
      } else {
        failures++;
      }
      if (_state.pc != null) {
        _set(PhoneLinkState(pc: _state.pc));
      }
      final wait = backoff[min(failures, backoff.length - 1)];
      final pause = Completer<void>();
      _pause = pause;
      await Future.any([pause.future, Future<void>.delayed(wait)]);
      _pause = null;
    }
    _running = false;
  }

  Future<List<Endpoint>> _locateSafely(String pcId) async {
    try {
      return await locate(pcId);
    } on Object {
      return const [];
    }
  }

  /// Opens a session with [pc] at [at]: TLS with this phone's certificate,
  /// the PC's pinned one, and hellos both ways.
  Future<LinkSession?> _open(Endpoint at, Peer pc) async {
    // ignore: close_sinks, the LinkSession below owns and closes it.
    final socket = await _connect(
      at,
      identity.context(),
      (fingerprint) => fingerprint == pc.fingerprint,
    );
    if (socket == null) return null;
    final link = LinkSession(
      socket,
      pingEvery: pingEvery,
      silenceLimit: silenceLimit,
    );
    link.send(_hello());
    // With TLS 1.3 the phone only learns that the PC turned its certificate
    // away when nothing comes back.
    final hello = await link.next(timeout: stepTimeout);
    if (hello == null || hello.type != Frames.hello) {
      await link.close();
      return null;
    }
    _session = link;
    await _greeted(hello);
    return link;
  }

  Future<void> _serve(LinkSession link) async {
    while (true) {
      final frame = await link.next();
      if (frame == null) break;
      switch (frame.type) {
        case Frames.hello:
          await _greeted(frame);
        case Frames.bye:
          // The PC forgot this pairing.
          _running = false;
          await savePc(null);
          _set(const PhoneLinkState());
          await link.close();
      }
    }
    if (identical(_session, link)) _session = null;
  }

  Future<void> _greeted(Frame hello) async {
    var pc = _state.pc;
    if (pc == null) return;
    final newName = hello.text('name');
    if (newName != null && _clean(newName) != pc.name) {
      pc = pc.copyWith(name: _clean(newName));
      await savePc(pc);
    }
    final theirs = hello.number('v');
    _set(
      PhoneLinkState(
        pc: pc,
        connection: theirs == version ? Connection.online : Connection.mismatch,
        theirVersion: theirs == version ? null : theirs,
      ),
    );
  }

  Frame _hello() =>
      Frame(Frames.hello, {'id': identity.id, 'name': name, 'v': version});

  Future<SecureSocket?> _connect(
    Endpoint at,
    SecurityContext context,
    bool Function(String fingerprint) accept,
  ) async {
    try {
      return await SecureSocket.connect(
        at.host,
        at.port,
        context: context,
        // Self-signed: TLS can't vouch for it, so the pin decides.
        onBadCertificate: (cert) => accept(fingerprintOfDer(cert.der)),
        timeout: connectTimeout,
      );
    } on Object {
      return null;
    }
  }

  void _set(PhoneLinkState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }
}

String _clean(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'PC';
  return trimmed.length > 40 ? trimmed.substring(0, 40) : trimmed;
}
