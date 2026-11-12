import 'dart:async';

import 'package:flutter/services.dart';
import 'package:gotit/core/link/phone_link.dart';
import 'package:gotit/core/sharing/sharing.dart';
import 'package:gotit/core/state/settings.dart';

/// The phone's switch outside the app, through Kotlin: the quick settings
/// tile, the notification's Turn on and Turn off, and the copy watcher and
/// the screenshot watcher, which do nothing while sharing is off. Whether
/// screenshots go to the PC at all travels with it.
class PhoneSharingControls {
  PhoneSharingControls({
    required this.sharing,
    required this.link,
    required this.settings,
  });

  final SharingSwitch sharing;
  final PhoneLink link;
  final SettingsStore settings;

  static const _channel = MethodChannel('app.gotit/sharing');
  StreamSubscription<bool>? _paired;

  void start() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'set') sharing.set(on: call.arguments == true);
    });
    sharing.addListener(_tell);
    settings.addListener(_tell);
    _paired = link.states
        .map((state) => state.pc != null)
        .distinct()
        .listen((_) => _tell());
    _tell();
    unawaited(_takeEarlyTap());
  }

  Future<void> stop() async {
    sharing.removeListener(_tell);
    settings.removeListener(_tell);
    await _paired?.cancel();
    _channel.setMethodCallHandler(null);
  }

  void _tell() => unawaited(
    _channel.invokeMethod<void>('update', {
      'on': sharing.on,
      'paired': link.state.pc != null,
      'screenshots': settings.value.sendsScreenshots,
    }),
  );

  /// A tap on the tile can start the app; it waits in Kotlin until now.
  Future<void> _takeEarlyTap() async {
    final on = await _channel.invokeMethod<bool>('ready');
    if (on != null) sharing.set(on: on);
  }
}
