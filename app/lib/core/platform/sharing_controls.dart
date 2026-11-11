import 'dart:async';

import 'package:flutter/services.dart';
import 'package:gotit/core/link/phone_link.dart';
import 'package:gotit/core/sharing/sharing.dart';

/// The phone's switch outside the app, through Kotlin: the quick settings
/// tile, the notification's Turn on and Turn off, and the copy watcher, which
/// reads nothing while sharing is off.
class PhoneSharingControls {
  PhoneSharingControls({required this.sharing, required this.link});

  final SharingSwitch sharing;
  final PhoneLink link;

  static const _channel = MethodChannel('app.gotit/sharing');
  StreamSubscription<bool>? _paired;

  void start() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'set') sharing.set(on: call.arguments == true);
    });
    sharing.addListener(_tell);
    _paired = link.states
        .map((state) => state.pc != null)
        .distinct()
        .listen((_) => _tell());
    _tell();
    unawaited(_takeEarlyTap());
  }

  Future<void> stop() async {
    sharing.removeListener(_tell);
    await _paired?.cancel();
    _channel.setMethodCallHandler(null);
  }

  void _tell() => unawaited(
    _channel.invokeMethod<void>('update', {
      'on': sharing.on,
      'paired': link.state.pc != null,
    }),
  );

  /// A tap on the tile can start the app; it waits in Kotlin until now.
  Future<void> _takeEarlyTap() async {
    final on = await _channel.invokeMethod<bool>('ready');
    if (on != null) sharing.set(on: on);
  }
}
