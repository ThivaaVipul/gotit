import 'dart:io';

import 'package:flutter/services.dart';
import 'package:gotit/core/link/identity.dart';
import 'package:gotit/core/platform/secrets.dart';

/// Secrets for this device, sealed by the platform's key store (DPAPI on the
/// PC, the Android Keystore on the phone) in [support]'s `secrets` folder.
SecretStore deviceSecrets(Directory support) => SealedFileSecrets(
  Directory('${support.path}${Platform.pathSeparator}secrets'),
  Platform.isWindows ? const WindowsSealer() : const AndroidSealer(),
);

/// The phone's name as set in Settings > About phone.
Future<String> phoneName() async {
  try {
    final name = await const MethodChannel(
      'app.gotit/device',
    ).invokeMethod<String>('name');
    if (name != null && name.trim().isNotEmpty) return name.trim();
  } on PlatformException {
    // Fall through to a plain name.
  } on MissingPluginException {
    // Not on Android.
  }
  return 'Phone';
}

/// This PC's addresses on the local network, for the QR code: private IPv4
/// addresses, with likely Wi-Fi and Ethernet adapters first and virtual ones
/// (Hyper-V, WSL, VPNs) last.
Future<List<String>> localAddresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  );
  final scored = <(int, String)>[];
  for (final interface in interfaces) {
    final name = interface.name.toLowerCase();
    final virtual = const [
      'vethernet',
      'virtual',
      'vmware',
      'hyper-v',
      'wsl',
      'loopback',
      'vpn',
      'tailscale',
      'zerotier',
    ].any(name.contains);
    for (final address in interface.addresses) {
      if (!_isPrivate(address.address)) continue;
      scored.add((virtual ? 1 : 0, address.address));
    }
  }
  scored.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final s in scored) s.$2];
}

bool _isPrivate(String ip) {
  final parts = ip.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.contains(null)) return false;
  final a = parts[0]!;
  final b = parts[1]!;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}
