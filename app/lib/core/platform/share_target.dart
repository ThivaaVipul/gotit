import 'dart:async';

import 'package:flutter/services.dart';
import 'package:gotit/core/clip/bridge.dart';
import 'package:gotit/core/clip/clip.dart';
import 'package:gotit/core/link/phone_link.dart';
import 'package:gotit/core/sharing/sharing.dart';
import 'package:gotit/core/transfer/transfers.dart';

/// Share > Gotit on the phone, through Kotlin's share target: files go to the
/// PC, and links or text land on its clipboard. Each share gets an answer
/// Kotlin shows: `sending:` and the PC's name, `sent`, `off`, `away:` and
/// the PC's name, `unpaired` or `failed`. Nothing waits for a PC that is away, apart from a
/// few seconds for a link that is still coming up (the share may have just
/// started the app).
class PhoneShareTarget {
  PhoneShareTarget({
    required this.link,
    required this.transfers,
    required this.sharing,
    required this.bridge,
    this.linkWait = const Duration(seconds: 6),
  });

  final PhoneLink link;
  final Transfers transfers;
  final SharingSwitch sharing;
  final ClipBridge bridge;
  final Duration linkWait;

  static const _channel = MethodChannel('app.gotit/share');

  void start() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'shared':
          return _shared(
            (call.arguments as Map<Object?, Object?>?) ?? const {},
          );
        case 'cancel':
          if (call.arguments case final String id) transfers.cancel(id);
      }
      return null;
    });
    unawaited(_channel.invokeMethod<void>('ready'));
  }

  Future<String> _shared(Map<Object?, Object?> share) async {
    final text = share['text'];
    final files = [
      for (final item in (share['files'] as List<Object?>?) ?? const [])
        if (item is Map<Object?, Object?>) ChannelOutgoingFile.from(item),
    ].nonNulls.toList();
    final pc = link.state.pc;
    if (pc == null) return 'unpaired';
    if (!sharing.on) {
      if (share['turnOn'] != true) return 'off';
      sharing.set(on: true);
    }
    if (!link.linked) {
      try {
        await link.linkedChanges.firstWhere((up) => up).timeout(linkWait);
      } on TimeoutException {
        return 'away:${pc.name}';
      }
    }
    if (files.isEmpty) {
      if (text is! String || text.isEmpty) return 'failed';
      return bridge.sendNow(Clip(text: text, manual: true))
          ? 'sent'
          : 'away:${pc.name}';
    }
    unawaited(transfers.send(files));
    return 'sending:${pc.name}';
  }
}

/// A file shared on the phone, read in pieces from Kotlin, which opened it.
class ChannelOutgoingFile implements OutgoingFile {
  ChannelOutgoingFile({
    required this.handle,
    required this.name,
    required this.size,
  });

  static ChannelOutgoingFile? from(Map<Object?, Object?> item) {
    final handle = item['handle'];
    final name = item['name'];
    final size = item['size'];
    if (handle is! int) return null;
    return ChannelOutgoingFile(
      handle: handle,
      name: name is String && name.isNotEmpty ? name : 'file',
      size: size is int ? size : -1,
    );
  }

  static const _channel = MethodChannel('app.gotit/share');

  /// Read from Kotlin a mebibyte at a time; the link sends it in 256 KiB
  /// chunks.
  static const _piece = 1024 * 1024;

  final int handle;

  @override
  final String name;

  @override
  final int size;

  @override
  Stream<List<int>> read() async* {
    Future<Uint8List?> fetch() => _channel.invokeMethod<Uint8List>('read', {
      'handle': handle,
      'max': _piece,
    });
    try {
      // The next piece is read while this one is sent.
      var next = fetch();
      while (true) {
        final bytes = await next;
        if (bytes == null) return;
        next = fetch();
        yield bytes;
      }
    } finally {
      // At the end, or when the send stops early.
      unawaited(_channel.invokeMethod<void>('close', {'handle': handle}));
    }
  }
}
