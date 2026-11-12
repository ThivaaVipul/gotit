import 'dart:async';

import 'package:flutter/services.dart';

/// Whether the copy watcher (an accessibility service) runs.
enum WatcherState {
  off,
  on,

  /// Switched on in Settings but not running: MIUI stopped it after the app
  /// was killed, and it stays stopped until switched off and on again.
  stopped,

  /// Switched off after it had run: Android turns it off when MIUI
  /// force-stops the app (a swipe-away without Autostart).
  turnedOff;

  static WatcherState parse(Object? value) => switch (value) {
    'on' => on,
    'stopped' => stopped,
    'turnedOff' => turnedOff,
    _ => off,
  };
}

/// What the phone's setup checklist needs to know.
class SetupStatus {
  const SetupStatus({
    this.notifications = false,
    this.battery = false,
    this.watcher = WatcherState.off,
    this.restricted = false,
    this.autostart = false,
    this.autostartOpened = false,
    this.locked = false,
    this.tileSupported = false,
    this.tile = false,
    this.screenshots = false,
    this.photos = false,
    this.maker = '',
  });

  /// Gotit may show notifications.
  final bool notifications;

  /// Battery optimisation is off for Gotit, so it can run, and start again,
  /// in the background.
  final bool battery;

  /// The copy watcher, which sends this phone's copies by itself.
  final WatcherState watcher;

  /// Android 13 and later may keep the watcher's switch greyed out (for apps
  /// installed from outside a store) until "Allow restricted settings" is
  /// chosen. Apps can't read whether it was, so this only says it may be.
  final bool restricted;

  /// MIUI's Autostart, which only you can tell is on, and whether its page
  /// was opened.
  final bool autostart;
  final bool autostartOpened;

  /// Gotit locked in MIUI's recents, which only you can tell.
  final bool locked;

  /// Android 13 and later can offer to add the quick settings tile, and
  /// whether it was added or the offer answered.
  final bool tileSupported;
  final bool tile;

  /// Whether new screenshots go to the PC (a Settings switch), and whether
  /// Android lets Gotit open them (Photos access).
  final bool screenshots;
  final bool photos;

  /// The phone's maker, for steps only some makers need.
  final String maker;

  /// Every step is done, so the checklist can go.
  bool get done =>
      notifications &&
      battery &&
      watcher == WatcherState.on &&
      (!xiaomi || (autostart && locked)) &&
      (!tileSupported || tile) &&
      (!screenshots || photos);

  bool get xiaomi {
    final m = maker.toLowerCase();
    return m.contains('xiaomi') || m.contains('redmi') || m.contains('poco');
  }
}

/// The phone side of the setup checklist.
abstract interface class PhoneSetup {
  Future<SetupStatus> status();

  /// Android's notification prompt, or its settings page once it was answered.
  Future<void> askNotifications();

  /// Android's "let it run in the background" prompt.
  Future<void> askBattery();

  /// The copy watcher's switch in Accessibility settings.
  Future<void> openWatcher();

  /// Gotit's app info page, which has "Allow restricted settings" (a switch
  /// at the bottom on MIUI, in the menu elsewhere).
  Future<void> openAppInfo();

  /// MIUI's Autostart list, in its Security app.
  Future<void> openAutostart();

  /// A step only you can tell is done: `autostart` or `locked`.
  Future<void> mark(String step);

  /// Android's prompt to add the quick settings tile. Completes once it was
  /// answered.
  Future<void> addTile();

  /// Android's Photos prompt, or Gotit's permissions page once it was
  /// answered.
  Future<void> askPhotos();

  /// The copy watcher started or stopped.
  Stream<WatcherState> get watcherChanges;
}

class ChannelPhoneSetup implements PhoneSetup {
  ChannelPhoneSetup() {
    _setup.setMethodCallHandler((call) async {
      if (call.method == 'watcher') {
        _watcher.add(WatcherState.parse(call.arguments));
      }
    });
  }

  static const _setup = MethodChannel('app.gotit/setup');
  static const _window = MethodChannel('app.gotit/activity');
  final _watcher = StreamController<WatcherState>.broadcast();

  @override
  Future<SetupStatus> status() async {
    final map = await _setup.invokeMapMethod<String, Object?>('status') ?? {};
    return SetupStatus(
      notifications: map['notifications'] == true,
      battery: map['battery'] == true,
      watcher: WatcherState.parse(map['watcher']),
      restricted: map['restricted'] == true,
      autostart: map['autostart'] == true,
      autostartOpened: map['autostartOpened'] == true,
      locked: map['locked'] == true,
      tileSupported: map['tileSupported'] == true,
      tile: map['tile'] == true,
      screenshots: map['screenshots'] == true,
      photos: map['photos'] == true,
      maker: map['maker'] as String? ?? '',
    );
  }

  @override
  Future<void> askNotifications() =>
      _window.invokeMethod<void>('notifications');

  @override
  Future<void> askBattery() => _setup.invokeMethod<void>('battery');

  @override
  Future<void> openWatcher() => _setup.invokeMethod<void>('watcher');

  @override
  Future<void> openAppInfo() => _setup.invokeMethod<void>('appInfo');

  @override
  Future<void> openAutostart() => _setup.invokeMethod<void>('autostart');

  @override
  Future<void> mark(String step) =>
      _setup.invokeMethod<void>('mark', {'step': step});

  @override
  Future<void> addTile() => _setup.invokeMethod<void>('tile');

  @override
  Future<void> askPhotos() => _window.invokeMethod<void>('photos');

  @override
  Stream<WatcherState> get watcherChanges => _watcher.stream;
}

/// The phone's ongoing notification, which also keeps the link running.
abstract interface class LinkNotice {
  /// Shows or updates it, with Send and Turn off while [sharing], or Turn
  /// on while not; or, while a file is on its way, its [percent] (null while
  /// unknown) and Cancel for the transfer [cancel]. False when Android won't
  /// start it from the background (the battery step allows that).
  Future<bool> show(
    String title, {
    String? text,
    bool sharing = true,
    int? percent,
    String? cancel,
  });

  Future<void> hide();
}

class ChannelLinkNotice implements LinkNotice {
  const ChannelLinkNotice();

  static const _channel = MethodChannel('app.gotit/service');

  @override
  Future<bool> show(
    String title, {
    String? text,
    bool sharing = true,
    int? percent,
    String? cancel,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('show', {
            'title': title,
            'text': text,
            'sharing': sharing,
            'percent': percent,
            'cancel': cancel,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> hide() => _channel.invokeMethod<void>('hide');
}
