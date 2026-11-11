import 'package:flutter/services.dart';

/// What the phone's setup checklist needs to know.
class SetupStatus {
  const SetupStatus({
    this.notifications = false,
    this.battery = false,
    this.maker = '',
  });

  /// Gotit may show notifications.
  final bool notifications;

  /// Battery optimisation is off for Gotit, so it can run, and start again,
  /// in the background.
  final bool battery;

  /// The phone's maker, for steps only some makers need.
  final String maker;

  /// Every step is done, so the checklist can go.
  bool get done => notifications && battery;

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
}

class ChannelPhoneSetup implements PhoneSetup {
  const ChannelPhoneSetup();

  static const _setup = MethodChannel('app.gotit/setup');
  static const _window = MethodChannel('app.gotit/activity');

  @override
  Future<SetupStatus> status() async {
    final map = await _setup.invokeMapMethod<String, Object?>('status') ?? {};
    return SetupStatus(
      notifications: map['notifications'] == true,
      battery: map['battery'] == true,
      maker: map['maker'] as String? ?? '',
    );
  }

  @override
  Future<void> askNotifications() =>
      _window.invokeMethod<void>('notifications');

  @override
  Future<void> askBattery() => _setup.invokeMethod<void>('battery');
}

/// The phone's ongoing notification, which also keeps the link running.
abstract interface class LinkNotice {
  /// Shows or updates it. False when Android won't start it from the
  /// background (the battery step allows that).
  Future<bool> show(String title, {String? text});

  Future<void> hide();
}

class ChannelLinkNotice implements LinkNotice {
  const ChannelLinkNotice();

  static const _channel = MethodChannel('app.gotit/service');

  @override
  Future<bool> show(String title, {String? text}) async {
    try {
      return await _channel.invokeMethod<bool>('show', {
            'title': title,
            'text': text,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> hide() => _channel.invokeMethod<void>('hide');
}
