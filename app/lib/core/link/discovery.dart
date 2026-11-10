import 'package:gotit/core/link/phone_link.dart' show Endpoint;

/// A Gotit PC seen on the network.
class FoundPc {
  const FoundPc({
    required this.id,
    required this.name,
    required this.endpoints,
    required this.version,
  });

  final String id;
  final String name;
  final List<Endpoint> endpoints;

  /// The PC's link version, from its advertisement.
  final int version;
}

/// Looks for Gotit PCs on the network (the phone's side).
abstract interface class PcFinder {
  /// The PCs seen so far, again after every change.
  Stream<List<FoundPc>> get changes;

  List<FoundPc> get current;

  Future<void> start();
  Future<void> stop();
}

/// Tells the network about this PC (the PC's side).
abstract interface class PcBeacon {
  Future<void> start({
    required String id,
    required String name,
    required int port,
  });

  Future<void> stop();
}

/// Where the PC with [pcId] was last seen, from [finder].
List<Endpoint> endpointsOf(PcFinder finder, String pcId) => [
  for (final pc in finder.current)
    if (pc.id == pcId) ...pc.endpoints,
];

/// Whether [address] can be dialled as is: IPv4, or IPv6 that isn't
/// link-local (those need an interface the address doesn't name).
bool isDialable(String address) =>
    !address.contains(':') || !address.toLowerCase().startsWith('fe80');
