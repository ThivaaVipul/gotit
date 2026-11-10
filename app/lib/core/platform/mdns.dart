import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:gotit/core/link/discovery.dart';
import 'package:gotit/core/link/phone_link.dart' show Endpoint;
import 'package:gotit/core/link/protocol.dart';

/// Finds Gotit PCs with mDNS (bonsoir).
class BonsoirPcFinder implements PcFinder {
  final _changes = StreamController<List<FoundPc>>.broadcast();
  final _byName = <String, FoundPc>{};
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _events;

  @override
  Stream<List<FoundPc>> get changes => _changes.stream;

  @override
  List<FoundPc> get current => List.unmodifiable(_byName.values);

  @override
  Future<void> start() async {
    if (_discovery != null) return;
    final discovery = BonsoirDiscovery(type: LinkSpec.serviceType);
    _discovery = discovery;
    await discovery.initialize();
    _events = discovery.eventStream?.listen((event) {
      switch (event) {
        case BonsoirDiscoveryServiceFoundEvent(:final service):
          unawaited(
            Future.sync(
              () => discovery.serviceResolver.resolveService(service),
            ),
          );
        case BonsoirDiscoveryServiceResolvedEvent(:final service):
        case BonsoirDiscoveryServiceUpdatedEvent(:final service):
          _seen(service);
        case BonsoirDiscoveryServiceLostEvent(:final service):
          if (_byName.remove(service.name) != null) _emit();
        default:
          break;
      }
    });
    await discovery.start();
  }

  @override
  Future<void> stop() async {
    await _events?.cancel();
    _events = null;
    await _discovery?.stop();
    _discovery = null;
    _byName.clear();
    _emit();
  }

  void _seen(BonsoirService service) {
    final id = service.attributes['id'];
    if (id == null || id.isEmpty) return;
    final addresses = service.hostAddresses.where(isDialable).toList()
      // IPv4 first: it is what home networks route best.
      ..sort((a, b) => (a.contains(':') ? 1 : 0) - (b.contains(':') ? 1 : 0));
    if (addresses.isEmpty) return;
    _byName[service.name] = FoundPc(
      id: id,
      name: service.name,
      endpoints: [for (final a in addresses) Endpoint(a, service.port)],
      version: int.tryParse(service.attributes['v'] ?? '') ?? 0,
    );
    _emit();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(current);
  }
}

/// Advertises this PC with mDNS (bonsoir).
class BonsoirPcBeacon implements PcBeacon {
  BonsoirBroadcast? _broadcast;

  @override
  Future<void> start({
    required String id,
    required String name,
    required int port,
  }) async {
    await stop();
    final broadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: name,
        type: LinkSpec.serviceType,
        port: port,
        attributes: {'id': id, 'v': '${LinkSpec.version}'},
      ),
    );
    _broadcast = broadcast;
    await broadcast.initialize();
    await broadcast.start();
  }

  @override
  Future<void> stop() async {
    final broadcast = _broadcast;
    _broadcast = null;
    await broadcast?.stop();
  }
}
