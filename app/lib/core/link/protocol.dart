/// The link between the phone and the PC: what both sides agree on.
abstract final class LinkSpec {
  /// Bumped whenever the two sides would no longer understand each other.
  /// A mismatch shows "Update Gotit" on both, and nothing crosses.
  static const version = 1;

  /// The mDNS service the PC advertises and the phone looks for.
  static const serviceType = '_gotit._tcp';

  /// The PC listens here when it can, so a remembered address stays good.
  static const preferredPort = 47331;

  /// How often an idle link says something, and how long silence may last
  /// before the link counts as lost.
  static const pingEvery = Duration(seconds: 30);
  static const silenceLimit = Duration(seconds: 75);

  /// How long a pairing request waits for Accept on the PC.
  static const pairTimeout = Duration(seconds: 60);

  /// How long a QR code on the PC can be used.
  static const inviteLifetime = Duration(minutes: 5);

  /// How long connecting, and a pairing step, may take.
  static const connectTimeout = Duration(seconds: 6);
  static const stepTimeout = Duration(seconds: 10);
}

/// Frame types.
abstract final class Frames {
  /// Phone to PC, unpaired: id, name, cert (PEM), v, and token from a QR code.
  static const pairRequest = 'pair.req';

  /// PC to phone: the request is on screen; both now show the code. id, name.
  static const pairWait = 'pair.wait';

  /// PC to phone: paired. id, name.
  static const pairOk = 'pair.ok';

  /// PC to phone: not paired. reason: declined, timeout, expired, busy,
  /// version.
  static const pairNo = 'pair.no';

  /// Both ways, first on a paired link: id, name, v.
  static const hello = 'hello';

  /// Both ways, on a paired link: the other side forgot this pairing.
  static const bye = 'bye';

  /// Both ways, on a paired link: something copied. kind (text), sensitive,
  /// at; the text is the body.
  static const clip = 'clip';

  static const ping = 'ping';
  static const pong = 'pong';
}

/// Why pairing didn't happen.
enum PairRefusal {
  declined,
  timeout,
  expired,
  busy,
  version,
  failed;

  static PairRefusal parse(String? reason) => PairRefusal.values.firstWhere(
    (r) => r.name == reason,
    orElse: () => PairRefusal.failed,
  );
}
