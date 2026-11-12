/// The link between the phone and the PC: what both sides agree on.
abstract final class LinkSpec {
  /// Bumped whenever the two sides would no longer understand each other.
  /// A mismatch shows "Update Gotit" on both, and nothing crosses.
  /// 2: image clips, in frames bigger than version 1 accepts.
  /// 3: files.
  static const version = 3;

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

  /// Both ways, on a paired link: something copied. kind (text or image),
  /// sensitive, at; the body is the text (UTF-8) or the image (PNG).
  static const clip = 'clip';

  /// Both ways, on a paired link: the sharing switch. on, at (when it was
  /// changed, ms since epoch), by (the device ID where it was changed). Sent
  /// when it changes and each time the link comes up.
  static const sharing = 'sharing';

  /// Both ways, on a paired link: a file is coming. id, name, size (-1 when
  /// unknown), and batch, index and count for files sent together.
  static const fileOffer = 'file.offer';

  /// A piece of the file: id; the body is up to 256 KiB of it.
  static const fileChunk = 'file.chunk';

  /// The whole file has been sent: id, and sha256 (hex) of all of it.
  static const fileDone = 'file.done';

  /// Either side stops a file: id.
  static const fileCancel = 'file.cancel';

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
